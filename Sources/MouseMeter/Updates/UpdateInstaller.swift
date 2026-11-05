import CryptoKit
import Foundation
import Security

/// Stage and validate before asking the running app to exit. All command arguments
/// are passed separately; paths and release data are never interpreted as shell code.
enum UpdateInstaller {
    static func validateInstallLocation(_ app: URL) throws {
        guard app.pathExtension == "app", Bundle(url: app)?.bundleIdentifier == "com.zhy2006.MouseMeter" else {
            throw UpdateError.invalidApp
        }
        let parent = app.deletingLastPathComponent()
        let values = try parent.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        guard values.volumeIsReadOnly != true,
              FileManager.default.isWritableFile(atPath: parent.path),
              FileManager.default.isWritableFile(atPath: app.path) else { throw UpdateError.installLocation }
    }

    static func verifyDownload(_ url: URL, asset: GitHubRelease.Asset) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard Int64(data.count) == asset.size else { throw UpdateError.invalidDownload }
        if let digest = asset.digest {
            let actual = "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == actual else { throw UpdateError.invalidDownload }
        }
    }

    static func verifyApp(_ candidate: URL, current: URL, version: String) throws {
        guard let bundle = Bundle(url: candidate),
              bundle.bundleIdentifier == "com.zhy2006.MouseMeter",
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version else {
            throw UpdateError.invalidApp
        }
        if let minimum = bundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String {
            let parts = minimum.split(separator: ".").compactMap { Int($0) }
            guard !parts.isEmpty, parts.count <= 3 else { throw UpdateError.invalidApp }
            let required = OperatingSystemVersion(majorVersion: parts[0], minorVersion: parts.count > 1 ? parts[1] : 0,
                                                  patchVersion: parts.count > 2 ? parts[2] : 0)
            guard ProcessInfo.processInfo.isOperatingSystemAtLeast(required) else { throw UpdateError.unsupportedOS }
        }
        var currentCode: SecStaticCode?
        var newCode: SecStaticCode?
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        guard SecStaticCodeCreateWithPath(current as CFURL, [], &currentCode) == errSecSuccess,
              SecStaticCodeCreateWithPath(candidate as CFURL, [], &newCode) == errSecSuccess,
              let currentCode, let newCode,
              SecStaticCodeCheckValidity(currentCode, flags, nil) == errSecSuccess else { throw UpdateError.signature }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(currentCode, [], &requirement) == errSecSuccess,
              let requirement,
              SecStaticCodeCheckValidity(newCode, flags, requirement) == errSecSuccess else { throw UpdateError.signature }
        // Explicitly require the exact same leaf certificate, including for Flick's
        // self-signed identity. Ad hoc signed builds cannot authorize an update.
        func certificate(_ code: SecStaticCode) -> Data? {
            var information: CFDictionary?
            guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
                  let dictionary = information as? [String: Any],
                  let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate],
                  let certificate = certificates.first else { return nil }
            return SecCertificateCopyData(certificate) as Data
        }
        guard let original = certificate(currentCode), original == certificate(newCode) else { throw UpdateError.signature }
    }

    static func prepareAndLaunch(download: URL, update: AvailableUpdate, app: URL) async throws {
        try await Task.detached {
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("MouseMeter-update-\(UUID().uuidString)", isDirectory: true)
            let staging = app.deletingLastPathComponent().appendingPathComponent(".MouseMeter-update-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: work, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var handedOff = false
            defer {
                if !handedOff {
                    try? fm.removeItem(at: work)
                    try? fm.removeItem(at: staging)
                }
            }
            try verifyDownload(download, asset: update.asset)
            let image = work.appendingPathComponent("update.dmg")
            try fm.copyItem(at: download, to: image)
            let mount = work.appendingPathComponent("mount", isDirectory: true)
            try fm.createDirectory(at: mount, withIntermediateDirectories: true)
            try run("/usr/bin/hdiutil", ["attach", image.path, "-mountpoint", mount.path, "-readonly", "-nobrowse", "-noautoopen", "-quiet"])
            var mounted = true
            defer { if mounted { try? run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"]) } }
            let source = mount.appendingPathComponent("MouseMeter.app", isDirectory: true)
            try verifyApp(source, current: app, version: update.version)
            try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let stagedApp = staging.appendingPathComponent("MouseMeter.app", isDirectory: true)
            try run("/usr/bin/ditto", [source.path, stagedApp.path])
            try verifyApp(stagedApp, current: app, version: update.version)
            let executable = stagedApp.appendingPathComponent("Contents/MacOS/MouseMeter")
            try run("/usr/bin/lipo", [executable.path, "-verify_arch", MacArchitecture.current == "arm64" ? "arm64" : "x86_64"])
            try run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"])
            mounted = false
            guard let script = L10n.resourceBundle.url(forResource: "install-update", withExtension: "sh") else {
                throw UpdateError.invalidApp
            }
            let helper = work.appendingPathComponent("install-update.sh")
            try fm.copyItem(at: script, to: helper)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [helper.path, String(ProcessInfo.processInfo.processIdentifier), app.path, staging.path, work.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            handedOff = true
        }.value
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.toolFailed(URL(fileURLWithPath: executable).lastPathComponent) }
    }
}
