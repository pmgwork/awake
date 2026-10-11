//
//  AppUpdater.swift
//  Awake
//
//  Sparkle-backed update handling. Sparkle reads the selected stable or beta
//  feed, verifies the EdDSA signature of the
//  downloaded archive, and installs the new version in place. Works without a
//  paid Apple Developer account; only the initial download needs the manual
//  Gatekeeper approval described in the README.
//

import Combine
import Sparkle

@MainActor
public final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    public static let shared = AppUpdater()

    /// Preferences used by the previous GitHub API based checker. They are
    /// migrated into Sparkle's own settings the first time this class runs.
    private static let legacyAutomaticallyCheckKey = "pmgwork.awake.automaticallyCheckForUpdates"
    private static let legacyLastCheckKey = "pmgwork.awake.lastUpdateCheckAt"

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    @Published public private(set) var automaticallyChecksForUpdates = true
    @Published public private(set) var receivesBetaUpdates = false
    @Published public private(set) var canCheckForUpdates = false
    @Published public private(set) var isUpdateInProgress = false
    @Published public private(set) var lastUpdateCheckDate: Date?

    private override init() {
        super.init()

        receivesBetaUpdates = UpdateChannel.stored() == .beta
        migrateLegacyPreferences()

        let updater = controller.updater
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        updater.publisher(for: \.sessionInProgress)
            .assign(to: &$isUpdateInProgress)
        updater.publisher(for: \.lastUpdateCheckDate)
            .assign(to: &$lastUpdateCheckDate)
        controller.startUpdater()
    }

    /// Starts a user-initiated check. Sparkle presents its own update window
    /// and, when the user agrees, downloads and installs the new version.
    public func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    public func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }

    public func setReceivesBetaUpdates(_ enabled: Bool) {
        guard !isUpdateInProgress, receivesBetaUpdates != enabled else { return }
        receivesBetaUpdates = enabled
        (enabled ? UpdateChannel.beta : .stable).save()
        controller.updater.resetUpdateCycleAfterShortDelay()
    }

    public func feedURLString(for updater: SPUUpdater) -> String? {
        (receivesBetaUpdates ? UpdateChannel.beta : .stable).feedURL
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
