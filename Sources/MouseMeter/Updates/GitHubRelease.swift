import Foundation
import Darwin

struct ReleaseVersion: Comparable, Equatable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ value: String) {
        let value = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]) else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

struct GitHubRelease: Decodable, Sendable {
    struct Asset: Decodable, Sendable {
        let name: String
        let browserDownloadURL: URL
        let size: Int64
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case name, size, digest
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case draft, prerelease, assets
        case tagName = "tag_name"
    }

    func update(currentVersion: String, architecture: String) throws -> AvailableUpdate? {
        guard !draft, !prerelease, tagName.hasPrefix("v"), let version = ReleaseVersion(tagName),
              let current = ReleaseVersion(currentVersion) else { throw UpdateError.invalidRelease }
        guard version > current else { return nil }
        let versionString = String(tagName.dropFirst())
        let name = "MouseMeter-\(versionString)-\(architecture).dmg"
        let expected = "https://github.com/zhy2006/MouseMeter/releases/download/\(tagName)/\(name)"
        guard let asset = assets.first(where: { $0.name == name }),
              asset.browserDownloadURL.absoluteString == expected, asset.size > 0 else {
            throw UpdateError.missingAsset
        }
        return AvailableUpdate(version: versionString, asset: asset)
    }
}

struct AvailableUpdate: Sendable {
    let version: String
    let asset: GitHubRelease.Asset
}

enum UpdateError: LocalizedError {
    case invalidRelease, missingAsset, network(Int), invalidDownload, signature, installLocation, invalidApp, unsupportedOS, toolFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidRelease: L10n.text("update_invalid_release")
        case .missingAsset: L10n.text("update_missing_asset")
        case .network(let status): L10n.format("update_http_error", status)
        case .invalidDownload: L10n.text("update_invalid_download")
        case .signature: L10n.text("update_signature_error")
        case .installLocation: L10n.text("update_install_location")
        case .invalidApp: L10n.text("update_invalid_app")
        case .unsupportedOS: L10n.text("update_unsupported_os")
        case .toolFailed(let tool): L10n.format("update_tool_error", tool)
        }
    }
}

enum MacArchitecture {
    static var current: String {
        #if arch(arm64)
        return "arm64"
        #else
        // A translated Intel build should migrate to the native Apple silicon build.
        var translated: Int32 = 0
        var size = MemoryLayout.size(ofValue: translated)
        if sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0, translated == 1 {
            return "arm64"
        }
        return "x64"
        #endif
    }
}
