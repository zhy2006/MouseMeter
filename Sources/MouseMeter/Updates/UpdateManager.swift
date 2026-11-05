import AppKit
import Foundation

@MainActor
final class UpdateManager: ObservableObject {
    @Published private(set) var availableUpdate: AvailableUpdate?
    @Published private(set) var isChecking = false
    @Published private(set) var isInstalling = false
    @Published private(set) var checked = false
    @Published private(set) var errorMessage: String?

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    private let session: URLSession
    private let defaults: UserDefaults
    private var pollingTask: Task<Void, Never>?
    static let releasesURL = URL(string: "https://github.com/zhy2006/MouseMeter/releases")!
    static let checkInterval: TimeInterval = 6 * 60 * 60

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
    }

    func start() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkIfDue()
                do { try await Task.sleep(for: .seconds(60 * 60)) }
                catch { return }
            }
        }
    }

    func checkIfDue() async {
        guard defaults.bool(forKey: SettingsKey.automaticallyCheckUpdates) else { return }
        let previous = defaults.object(forKey: SettingsKey.lastUpdateCheck) as? Date ?? .distantPast
        guard Date().timeIntervalSince(previous) >= Self.checkInterval else { return }
        await checkForUpdates()
    }

    func checkForUpdates() async {
        guard !isChecking, !isInstalling else { return }
        isChecking = true
        errorMessage = nil
        defer { isChecking = false }
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/zhy2006/MouseMeter/releases/latest")!)
            request.timeoutInterval = 30
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("MouseMeter/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw UpdateError.invalidRelease }
            if response.statusCode == 404 {
                availableUpdate = nil // No published release yet.
            } else {
                guard response.statusCode == 200 else { throw UpdateError.network(response.statusCode) }
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                availableUpdate = try release.update(currentVersion: currentVersion, architecture: MacArchitecture.current)
            }
            checked = true
            defaults.set(Date(), forKey: SettingsKey.lastUpdateCheck)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func installUpdate() async {
        guard let update = availableUpdate, !isInstalling, !isChecking else { return }
        isInstalling = true
        errorMessage = nil
        defer { isInstalling = false }
        do {
            let app = Bundle.main.bundleURL.resolvingSymlinksInPath()
            try UpdateInstaller.validateInstallLocation(app)
            var request = URLRequest(url: update.asset.browserDownloadURL)
            request.timeoutInterval = 300
            let (temporaryURL, response) = try await session.download(for: request)
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateError.invalidDownload
            }
            try await UpdateInstaller.prepareAndLaunch(download: temporaryURL, update: update, app: app)
            NSApp.terminate(nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
