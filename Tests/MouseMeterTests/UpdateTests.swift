import CryptoKit
import Foundation
import Testing
import Synchronization
@testable import MouseMeter

struct UpdateTests {
    private func release(_ version: String = "1.10.0", architecture: String = "arm64", host: String = "github.com") -> GitHubRelease {
        let name = "MouseMeter-\(version)-\(architecture).dmg"
        let asset = GitHubRelease.Asset(
            name: name,
            browserDownloadURL: URL(string: "https://\(host)/zhy2006/MouseMeter/releases/download/v\(version)/\(name)")!,
            size: 3, digest: nil
        )
        return GitHubRelease(tagName: "v\(version)", draft: false, prerelease: false, assets: [asset])
    }

    @Test func comparesVersionsNumericallyAndRejectsNonStableVersions() {
        #expect(ReleaseVersion("v1.10.0")! > ReleaseVersion("1.9.9")!)
        #expect(ReleaseVersion("2.0.0")! > ReleaseVersion("1.99.99")!)
        #expect(ReleaseVersion("1.0.1")! > ReleaseVersion("1.0.0")!)
        #expect(ReleaseVersion("v1.0.0") == ReleaseVersion("1.0.0"))
        for invalid in ["1.0", "1.0.0-beta", "1.0.0.0", "-1.0.0", "v1..0", "999999999999999999999.0.0"] {
            #expect(ReleaseVersion(invalid) == nil)
        }
    }

    @Test func selectsArchitectureAndNeverDowngrades() throws {
        #expect(try release().update(currentVersion: "1.9.0", architecture: "arm64")?.version == "1.10.0")
        #expect(throws: UpdateError.self) { try release().update(currentVersion: "1.9.0", architecture: "x64") }
        #expect(try release().update(currentVersion: "1.10.0", architecture: "arm64") == nil)
        #expect(try release().update(currentVersion: "2.0.0", architecture: "arm64") == nil)
        #expect(throws: UpdateError.self) {
            try release(host: "example.com").update(currentVersion: "1.0.0", architecture: "arm64")
        }
        let prerelease = GitHubRelease(tagName: "v2.0.0", draft: false, prerelease: true, assets: [])
        #expect(throws: UpdateError.self) { try prerelease.update(currentVersion: "1.0.0", architecture: "arm64") }
    }

    @Test func rejectsIncompleteAndCorruptDownloads() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let data = Data("abc".utf8)
        try data.write(to: file)
        let url = URL(string: "https://github.com/zhy2006/MouseMeter/test.dmg")!
        let digest = "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try UpdateInstaller.verifyDownload(file, asset: .init(name: "test.dmg", browserDownloadURL: url, size: 3, digest: digest))
        #expect(throws: UpdateError.self) {
            try UpdateInstaller.verifyDownload(file, asset: .init(name: "test.dmg", browserDownloadURL: url, size: 4, digest: nil))
        }
        #expect(throws: UpdateError.self) {
            try UpdateInstaller.verifyDownload(file, asset: .init(name: "test.dmg", browserDownloadURL: url, size: 3, digest: "sha256:wrong"))
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MOUSEMETER_SIGNED_TEST_APP"] != nil))
    func validatesFlickSignatureAndRejectsResigning() throws {
        let path = try #require(ProcessInfo.processInfo.environment["MOUSEMETER_SIGNED_TEST_APP"])
        let current = URL(fileURLWithPath: path)
        let bundle = try #require(Bundle(url: current))
        let version = try #require(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        try UpdateInstaller.verifyApp(current, current: current, version: version)
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".app")
        defer { try? FileManager.default.removeItem(at: copy) }
        try FileManager.default.copyItem(at: current, to: copy)
        try UpdateInstaller.verifyApp(copy, current: current, version: version)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--sign", "-", copy.path]
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(throws: UpdateError.self) { try UpdateInstaller.verifyApp(copy, current: current, version: version) }
    }

    @Test func rejectsUnsignedApplications() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".app")
        defer { try? FileManager.default.removeItem(at: app) }
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let metadata = ["CFBundleIdentifier": "com.zhy2006.MouseMeter", "CFBundleShortVersionString": "1.1.0"]
        try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        #expect(throws: UpdateError.self) { try UpdateInstaller.verifyApp(app, current: app, version: "1.1.0") }
        #expect(throws: UpdateError.self) { try UpdateInstaller.verifyApp(app, current: app, version: "1.2.0") }
    }

    @Test func installerReplacesAppOrRestoresItOnMoveFailure() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("Update Test \(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let scriptURL = try #require(L10n.resourceBundle.url(forResource: "install-update", withExtension: "sh"))
        // Exercise the real filesystem transaction without launching a GUI app.
        let template = try String(contentsOf: scriptURL, encoding: .utf8)
        for (hasReplacement, canOpen) in [(true, true), (false, true), (true, false)] {
            let script = template.replacingOccurrences(of: "/usr/bin/open", with: canOpen ? "/usr/bin/true" : "/usr/bin/false")
            let folder = root.appendingPathComponent(UUID().uuidString)
            let app = folder.appendingPathComponent("Mouse Meter.app")
            let staging = folder.appendingPathComponent("staging")
            let work = folder.appendingPathComponent("work")
            try fm.createDirectory(at: app, withIntermediateDirectories: true)
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            try Data("old".utf8).write(to: app.appendingPathComponent("marker"))
            if hasReplacement {
                let newApp = staging.appendingPathComponent("MouseMeter.app")
                try fm.createDirectory(at: newApp, withIntermediateDirectories: true)
                try Data("new".utf8).write(to: newApp.appendingPathComponent("marker"))
            }
            let helper = work.appendingPathComponent("helper.sh")
            try script.write(to: helper, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [helper.path, "2147483647", app.path, staging.path, work.path]
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == (hasReplacement && canOpen ? 0 : 1))
            #expect(try String(contentsOf: app.appendingPathComponent("marker"), encoding: .utf8) == (hasReplacement && canOpen ? "new" : "old"))
        }
    }
}

private final class UpdateURLProtocol: URLProtocol {
    private struct State {
        var status = 200
        var body = Data()
        var requests = 0
    }
    private static let state = Mutex(State())
    static var status: Int {
        get { state.withLock { $0.status } }
        set { state.withLock { $0.status = newValue } }
    }
    static var body: Data {
        get { state.withLock { $0.body } }
        set { state.withLock { $0.body = newValue } }
    }
    static var requests: Int {
        get { state.withLock { $0.requests } }
        set { state.withLock { $0.requests = newValue } }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
@MainActor
struct UpdateManagerTests {
    @Test func handlesMissingReleasesErrorsAndAutoCheckPreference() async throws {
        let name = "MouseMeterUpdatesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: SettingsKey.automaticallyCheckUpdates)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let manager = UpdateManager(session: session, defaults: defaults)
        UpdateURLProtocol.requests = 0
        await manager.checkIfDue()
        #expect(UpdateURLProtocol.requests == 0)
        UpdateURLProtocol.status = 404
        await manager.checkForUpdates()
        #expect(manager.checked)
        #expect(manager.availableUpdate == nil)
        #expect(manager.errorMessage == nil)
        #expect(defaults.object(forKey: SettingsKey.lastUpdateCheck) != nil)
        defaults.set(true, forKey: SettingsKey.automaticallyCheckUpdates)
        await manager.checkIfDue()
        #expect(UpdateURLProtocol.requests == 1) // Successful checks are throttled.
        let version = "999.0.0"
        let assetName = "MouseMeter-\(version)-\(MacArchitecture.current).dmg"
        UpdateURLProtocol.status = 200
        UpdateURLProtocol.body = try JSONSerialization.data(withJSONObject: [
            "tag_name": "v\(version)", "draft": false, "prerelease": false,
            "assets": [["name": assetName, "size": 3,
                        "browser_download_url": "https://github.com/zhy2006/MouseMeter/releases/download/v\(version)/\(assetName)"]]
        ])
        await manager.checkForUpdates()
        #expect(manager.availableUpdate?.version == version)
        #expect(manager.errorMessage == nil)
        UpdateURLProtocol.status = 403
        await manager.checkForUpdates()
        #expect(manager.errorMessage != nil)
        #expect(!manager.isChecking)
        UpdateURLProtocol.status = 200
        UpdateURLProtocol.body = Data("invalid json".utf8)
        await manager.checkForUpdates()
        #expect(manager.errorMessage != nil)
        #expect(!manager.isChecking)
    }
}
