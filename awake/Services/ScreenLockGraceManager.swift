//
//  ScreenLockGraceManager.swift
//  Awake
//

import AppKit
import Combine
import Foundation

/// Read/write access to the macOS "require password after screensaver begins
/// or display is turned off" delay. Abstracted behind a protocol so the
/// manager can be unit tested without touching real system preferences.
public protocol ScreenLockPreferenceStore {
    func copyDelay() -> Int?
    func copyAskForPassword() -> Bool?
    @discardableResult func setDelay(_ delay: Int?) -> Bool
}

/// Live implementation backed by CFPreferences.
///
/// The setting lives in `com.apple.screensaver` (ByHost) under the key
/// `askForPasswordDelay` (integer seconds). Passing `nil` to `setDelay`
/// removes the key, restoring the "never customized" state.
public struct CFScreenLockPreferenceStore: ScreenLockPreferenceStore {
    private let appID = "com.apple.screensaver" as CFString
    private let delayKey = "askForPasswordDelay" as CFString
    private let askKey = "askForPassword" as CFString

    public init() {}

    public func copyDelay() -> Int? {
        CFPreferencesCopyValue(
            delayKey, appID, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost
        ) as? Int
    }

    public func copyAskForPassword() -> Bool? {
        CFPreferencesCopyValue(
            askKey, appID, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost
        ) as? Bool
    }

    @discardableResult
    public func setDelay(_ delay: Int?) -> Bool {
        CFPreferencesSetValue(
            delayKey, delay as CFPropertyList?, appID,
            kCFPreferencesCurrentUser, kCFPreferencesCurrentHost
        )
        return CFPreferencesSynchronize(appID, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }
}

/// Temporarily extends the automatic-lock delay while a Keep Awake session
/// is active, so the setting is in place before the lid closes, then restores
/// the original value when the session ends.
///
/// Use `update(sessionActive:enabled:)` from the coordinator heartbeat.
/// The original value is captured once per grace period and persisted, so a
/// crash or force-quit cannot leave the machine unprotected: the next launch
/// restores the saved value (see `recoverStaleIfNeeded`).
@MainActor
public final class ScreenLockGraceManager: NSObject, ObservableObject {
    public static let shared = ScreenLockGraceManager()

    /// Effectively "never lock while grace is applied" (Int32.max, the value
    /// with real-world precedent in enterprise screen-lock profiles).
    public static let appliedDelay = 2_147_483_647

    @Published public private(set) var isGraceActive = false
    @Published public private(set) var lastError: String?

    private let store: ScreenLockPreferenceStore
    private let defaults: UserDefaults

    private enum MarkerKeys {
        static let applied = "pmgwork.awake.lockGraceApplied"
        static let hadOriginal = "pmgwork.awake.lockGraceHadOriginal"
        static let originalDelay = "pmgwork.awake.lockGraceOriginalDelay"
    }

    init(
        store: ScreenLockPreferenceStore? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.store = store ?? CFScreenLockPreferenceStore()
        self.defaults = defaults
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
        recoverStaleIfNeeded()
    }

    @objc private func handleAppWillTerminate() {
        restore()
    }

    /// Applies the grace delay while `sessionActive && enabled`, restoring
    /// the original setting otherwise. Safe to call every heartbeat.
    public func update(sessionActive: Bool, enabled: Bool) {
        if sessionActive && enabled {
            apply()
        } else {
            restore()
        }
    }

    private func apply() {
        // If the machine never requires a password, there is nothing to defer.
        if store.copyAskForPassword() == false {
            isGraceActive = false
            lastError = nil
            return
        }

        if !defaults.bool(forKey: MarkerKeys.applied) {
            let current = store.copyDelay()
            if let value = current {
                defaults.set(value, forKey: MarkerKeys.originalDelay)
                defaults.set(true, forKey: MarkerKeys.hadOriginal)
            } else {
                defaults.set(false, forKey: MarkerKeys.hadOriginal)
            }
            defaults.set(true, forKey: MarkerKeys.applied)
        }

        if store.copyDelay() == Self.appliedDelay {
            isGraceActive = true
            lastError = nil
            return
        }

        // The write may be ignored on macOS versions that no longer honor
        // manual edits to this domain. The read-back check detects that so
        // the UI can report it instead of pretending grace is active.
        guard store.setDelay(Self.appliedDelay),
            store.copyDelay() == Self.appliedDelay
        else {
            isGraceActive = false
            lastError = L10n.string("Automatic lock delay could not be changed on this macOS version.")
            NSLog("[ScreenLockGraceManager] Failed to apply lock grace delay (read-back mismatch)")
            return
        }
        isGraceActive = true
        lastError = nil
    }

    private func restore() {
        guard defaults.bool(forKey: MarkerKeys.applied) || isGraceActive else { return }
        if defaults.bool(forKey: MarkerKeys.hadOriginal) {
            // The saved original must exist; if it does not (e.g. the app's
            // own defaults were wiped), keep the marker and retry later
            // rather than applying a wrong value.
            guard let target = defaults.object(forKey: MarkerKeys.originalDelay) as? Int else {
                lastError = L10n.string("Could not restore the automatic lock setting.")
                NSLog("[ScreenLockGraceManager] Original lock delay missing, will retry")
                return
            }
            guard store.setDelay(target) else {
                lastError = L10n.string("Could not restore the automatic lock setting.")
                NSLog("[ScreenLockGraceManager] Failed to restore lock delay")
                return
            }
        } else if !store.setDelay(nil) {
            lastError = L10n.string("Could not restore the automatic lock setting.")
            NSLog("[ScreenLockGraceManager] Failed to remove lock delay override")
            return
        }
        clearMarker()
        isGraceActive = false
        lastError = nil
    }

    /// Restores a grace delay left applied by a previous run that did not
    /// shut down cleanly (crash, force-quit, power loss).
    private func recoverStaleIfNeeded() {
        guard defaults.bool(forKey: MarkerKeys.applied) else { return }
        NSLog("[ScreenLockGraceManager] Restoring stale lock grace from previous run")
        restore()
    }

    private func clearMarker() {
        defaults.removeObject(forKey: MarkerKeys.applied)
        defaults.removeObject(forKey: MarkerKeys.hadOriginal)
        defaults.removeObject(forKey: MarkerKeys.originalDelay)
    }
}
