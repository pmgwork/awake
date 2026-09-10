//
//  AppUpdateService.swift
//  Awake
//
//  Lightweight GitHub Releases update checker. Works without a paid
//  Apple Developer account: it only reads the public releases API,
//  compares versions, and opens the release page in the browser.
//

import Foundation
import Combine
import AppKit

public struct AppRelease: Equatable, Sendable {
    public let version: String
    public let name: String
    public let url: URL
    public let notes: String
    public let prerelease: Bool

    public init(version: String, name: String, url: URL, notes: String, prerelease: Bool) {
        self.version = version
        self.name = name
        self.url = url
        self.notes = notes
        self.prerelease = prerelease
    }
}

public enum UpdateCheckState: Equatable, Sendable {
    case idle
    case checking
    case upToDate(currentVersion: String)
    case available(currentVersion: String, release: AppRelease)
    case failed(message: String)
}

@MainActor
public final class AppUpdateService: ObservableObject {
    public static let shared = AppUpdateService()

    public static let repositoryOwner = "PMGWork"
    public static let repositoryName = "awake"

    @Published public private(set) var state: UpdateCheckState = .idle
    @Published public private(set) var lastCheckedAt: Date?

    private let urlSession: URLSession
    private let settings: SettingsStore

    public init(
        urlSession: URLSession = .shared,
        settings: SettingsStore? = nil
    ) {
        self.urlSession = urlSession
        // SettingsStore.shared is @MainActor-isolated; optional injection keeps
        // unit tests off the shared singleton.
        if let settings {
            self.settings = settings
        } else {
            self.settings = SettingsStore.shared
        }
    }

    public var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    public var releasesURL: URL {
        URL(string: "https://github.com/\(Self.repositoryOwner)/\(Self.repositoryName)/releases")!
    }

    public func checkForUpdates(userInitiated: Bool = true) {
        guard state != .checking else { return }
        state = .checking
        Task {
            await performCheck(userInitiated: userInitiated)
        }
    }

    public func openRelease(_ release: AppRelease) {
        NSWorkspace.shared.open(release.url)
    }

    public func openReleasesPage() {
        NSWorkspace.shared.open(releasesURL)
    }

    // MARK: - Private

    private func performCheck(userInitiated: Bool) async {
        do {
            let release = try await fetchLatestRelease()
            lastCheckedAt = Date()
            settings.recordUpdateCheck(at: lastCheckedAt!)
            let current = currentVersion
            if Self.isNewer(latest: release.version, current: current) {
                state = .available(currentVersion: current, release: release)
                if !userInitiated {
                    notifyUpdateAvailable(release)
                }
            } else {
                state = .upToDate(currentVersion: current)
            }
        } catch {
            // Silent background checks must not surface errors; manual checks do.
            if userInitiated {
                state = .failed(message: error.localizedDescription)
            } else {
                state = .idle
            }
        }
    }

    private func fetchLatestRelease() async throws -> AppRelease {
        let url = URL(string: "https://api.github.com/repos/\(Self.repositoryOwner)/\(Self.repositoryName)/releases/latest")!
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.badResponse
        }
        let decoded = try JSONDecoder().decode(GitHubReleaseDTO.self, from: data)
        guard !decoded.draft, !decoded.prerelease else {
            throw UpdateError.noStableRelease
        }
        let version = Self.normalizedVersion(from: decoded.tagName)
        guard let pageURL = URL(string: decoded.htmlUrl) else {
            throw UpdateError.badResponse
        }
        return AppRelease(
            version: version,
            name: decoded.name ?? decoded.tagName,
            url: pageURL,
            notes: decoded.body ?? "",
            prerelease: decoded.prerelease
        )
    }

    private func notifyUpdateAvailable(_ release: AppRelease) {
        guard settings.notificationsEnabled else { return }
        NotificationManager.shared.sendNotification(
            title: L10n.format("Awake %@ is available", release.version),
            body: L10n.string("Open Settings to download the latest release."),
            identifier: "awake-update-available-\(release.version)"
        )
    }

    // MARK: - Version helpers (pure, unit-tested)

    nonisolated public static func normalizedVersion(from tag: String) -> String {
        var value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("v") {
            value = String(value.dropFirst())
        }
        return value
    }

    nonisolated public static func isNewer(latest: String, current: String) -> Bool {
        compareVersions(normalizedVersion(from: latest), normalizedVersion(from: current)) == .orderedDescending
    }

    nonisolated public static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = lhs.split(separator: ".").map { String($0) }
        let rhsParts = rhs.split(separator: ".").map { String($0) }
        let count = max(lhsParts.count, rhsParts.count)
        for index in 0..<count {
            let left = index < lhsParts.count ? lhsParts[index] : "0"
            let right = index < rhsParts.count ? rhsParts[index] : "0"
            if let leftNumber = Int(left), let rightNumber = Int(right) {
                if leftNumber != rightNumber {
                    return leftNumber < rightNumber ? .orderedAscending : .orderedDescending
                }
            } else if left != right {
                return left.compare(right, options: .numeric)
            }
        }
        return .orderedSame
    }

    public enum UpdateError: LocalizedError {
        case badResponse
        case noStableRelease

        public var errorDescription: String? {
            switch self {
            case .badResponse:
                return L10n.string("Could not check for updates. Please try again later.")
            case .noStableRelease:
                return L10n.string("No stable release is published yet.")
            }
        }
    }

    private struct GitHubReleaseDTO: Decodable {
        let tagName: String
        let name: String?
        let htmlUrl: String
        let body: String?
        let draft: Bool
        let prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlUrl = "html_url"
            case body
            case draft
            case prerelease
        }
    }
}
