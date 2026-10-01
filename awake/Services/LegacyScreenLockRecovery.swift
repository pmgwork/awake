import AppKit
import Foundation

protocol LegacyScreenLockPreferenceStore {
    @discardableResult func setDelay(_ delay: Int?) -> Bool
}

private struct CFScreenLockPreferenceStore: LegacyScreenLockPreferenceStore {
    func setDelay(_ delay: Int?) -> Bool {
        let appID = "com.apple.screensaver" as CFString
        CFPreferencesSetValue(
            "askForPasswordDelay" as CFString, delay as CFPropertyList?, appID,
            kCFPreferencesCurrentUser, kCFPreferencesCurrentHost
        )
        return CFPreferencesSynchronize(appID, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }
}

/// Restores the lock preference changed by older releases. This migration
/// never applies an override and retains its marker until restoration succeeds.
@MainActor
final class LegacyScreenLockRecovery: NSObject {
    static let shared = LegacyScreenLockRecovery()

    private let store: LegacyScreenLockPreferenceStore
    private let defaults: UserDefaults

    private enum MarkerKeys {
        static let applied = "pmgwork.awake.lockGraceApplied"
        static let hadOriginal = "pmgwork.awake.lockGraceHadOriginal"
        static let originalDelay = "pmgwork.awake.lockGraceOriginalDelay"
    }

    init(store: LegacyScreenLockPreferenceStore? = nil, defaults: UserDefaults = .standard) {
        self.store = store ?? CFScreenLockPreferenceStore()
        self.defaults = defaults
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(restoreIfNeeded),
            name: NSApplication.willTerminateNotification, object: nil
        )
        restoreIfNeeded()
    }

    @objc func restoreIfNeeded() {
        guard defaults.bool(forKey: MarkerKeys.applied) else { return }
        let originalDelay: Int?
        if defaults.bool(forKey: MarkerKeys.hadOriginal) {
            guard let saved = defaults.object(forKey: MarkerKeys.originalDelay) as? Int else {
                NSLog("[LegacyScreenLockRecovery] Original lock delay missing; will retry")
                return
            }
            originalDelay = saved
        } else {
            originalDelay = nil
        }
        guard store.setDelay(originalDelay) else {
            NSLog("[LegacyScreenLockRecovery] Could not restore lock delay; will retry")
            return
        }
        defaults.removeObject(forKey: MarkerKeys.applied)
        defaults.removeObject(forKey: MarkerKeys.hadOriginal)
        defaults.removeObject(forKey: MarkerKeys.originalDelay)
    }
}
