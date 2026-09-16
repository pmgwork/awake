//
//  AppUpdater.swift
//  Awake
//
//  Sparkle-backed update handling. Sparkle reads the appcast.xml attached to
//  the latest stable GitHub Release, verifies the EdDSA signature of the
//  downloaded archive, and installs the new version in place. Works without a
//  paid Apple Developer account; only the initial download needs the manual
//  Gatekeeper approval described in the README.
//

import AppKit
import Combine
import Sparkle

@MainActor
public final class AppUpdater: NSObject, ObservableObject {
    public static let shared = AppUpdater()

    /// Where "View All Releases" and Sparkle's fallback links point to.
    public static let releasesPageURL = URL(string: "https://github.com/PMGWork/awake/releases")!

    /// Preferences used by the previous GitHub API based checker. They are
    /// migrated into Sparkle's own settings the first time this class runs.
    private static let legacyAutomaticallyCheckKey = "pmgwork.awake.automaticallyCheckForUpdates"
    private static let legacyLastCheckKey = "pmgwork.awake.lastUpdateCheckAt"

    private let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    @Published public private(set) var automaticallyChecksForUpdates = true
    @Published public private(set) var canCheckForUpdates = false
    @Published public private(set) var lastUpdateCheckDate: Date?

    private override init() {
        super.init()

        migrateLegacyPreferences()

        let updater = controller.updater
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        updater.publisher(for: \.lastUpdateCheckDate)
            .assign(to: &$lastUpdateCheckDate)
    }

    /// Starts a user-initiated check. Sparkle presents its own update window
    /// and, when the user agrees, downloads and installs the new version.
    public func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// Opens the GitHub releases page in the default browser.
    public func openReleasesPage() {
        NSWorkspace.shared.open(Self.releasesPageURL)
    }

    public func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }

    private func migrateLegacyPreferences() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.legacyAutomaticallyCheckKey) != nil else { return }
        controller.updater.automaticallyChecksForUpdates = defaults.bool(
            forKey: Self.legacyAutomaticallyCheckKey
        )
        defaults.removeObject(forKey: Self.legacyAutomaticallyCheckKey)
        defaults.removeObject(forKey: Self.legacyLastCheckKey)
    }
}
