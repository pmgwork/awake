//
//  ScreenBehaviorManager.swift
//  Awake
//

import AppKit
import Combine
import CoreGraphics
import Foundation
import IOKit.pwr_mgt

@MainActor
public final class ScreenBehaviorManager: ObservableObject {
    public static let shared = ScreenBehaviorManager()

    private static let userActivityRefreshInterval: TimeInterval = 30

    @Published public private(set) var lastError: String?

    private let screenSaverBundleIdentifier = "com.apple.ScreenSaver.Engine"

    private var screenSaverActivityAssertionID: IOPMAssertionID = 0
    private var screenSaverPreventionRequested = false
    private var lastUserActivityDeclaration: Date?
    private var screenSaverControlFailed = false
    private var workspaceObserver: NSObjectProtocol?
    private var screenLockedObserver: NSObjectProtocol?
    private var screenUnlockedObserver: NSObjectProtocol?
    private var isScreenLocked = false

    private init() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            else {
                return
            }
            Task { @MainActor in
                ScreenBehaviorManager.shared.handleApplicationLaunch(application)
            }
        }

        let distributedCenter = DistributedNotificationCenter.default()
        screenLockedObserver = distributedCenter.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                ScreenBehaviorManager.shared.isScreenLocked = true
            }
        }
        screenUnlockedObserver = distributedCenter.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                ScreenBehaviorManager.shared.isScreenLocked = false
                ScreenBehaviorManager.shared.refreshUserActivityAssertion(force: true)
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    public func update(
        sessionActive: Bool,
        keepScreenOn: Bool,
        lidClosed: Bool,
        hasExternalDisplay: Bool
    ) {
        let policy = DisplayBehaviorPolicy(
            lidClosed: lidClosed, hasExternalDisplay: hasExternalDisplay
        )
        configureScreenSaverPrevention(enabled: sessionActive && keepScreenOn && policy.allowsScreenPrevention)
        if screenSaverPreventionRequested {
            stopRunningScreenSaverIfNeeded()
        }
        refreshLastError()
    }

    @objc private func handleAppWillTerminate() {
        configureScreenSaverPrevention(enabled: false)
    }

    private func configureScreenSaverPrevention(enabled: Bool) {
        screenSaverPreventionRequested = enabled

        guard enabled else {
            releaseUserActivityAssertion()
            screenSaverControlFailed = false
            return
        }

        // Declaring user activity resets macOS's user-idle timer, so the display
        // stays on and the idle screen saver and automatic lock never begin.
        refreshUserActivityAssertion()
    }

    private func refreshUserActivityAssertion(force: Bool = false) {
        guard screenSaverPreventionRequested, !currentSessionIsLocked else { return }

        let now = Date()
        if !force,
            let lastUserActivityDeclaration,
            now.timeIntervalSince(lastUserActivityDeclaration)
                < Self.userActivityRefreshInterval
        {
            return
        }

        let result = IOPMAssertionDeclareUserActivity(
            "Awake: Preventing Automatic Screen Lock" as CFString,
            kIOPMUserActiveLocal,
            &screenSaverActivityAssertionID
        )
        guard result == kIOReturnSuccess, screenSaverActivityAssertionID != 0 else {
            screenSaverControlFailed = true
            NSLog(
                "[ScreenBehaviorManager] Failed to declare continuous user activity: %d", result)
            return
        }

        lastUserActivityDeclaration = now
        screenSaverControlFailed = false
    }

    private func releaseUserActivityAssertion() {
        if screenSaverActivityAssertionID != 0 {
            IOPMAssertionRelease(screenSaverActivityAssertionID)
            screenSaverActivityAssertionID = 0
        }
        lastUserActivityDeclaration = nil
    }

    private func handleApplicationLaunch(_ application: NSRunningApplication) {
        guard screenSaverPreventionRequested, !currentSessionIsLocked,
            application.bundleIdentifier == screenSaverBundleIdentifier
        else {
            return
        }
        terminateScreenSaver(application)
    }

    private func stopRunningScreenSaverIfNeeded() {
        guard !currentSessionIsLocked else { return }
        for application in NSWorkspace.shared.runningApplications
        where application.bundleIdentifier == screenSaverBundleIdentifier {
            terminateScreenSaver(application)
        }
    }

    private func terminateScreenSaver(_ application: NSRunningApplication) {
        refreshUserActivityAssertion(force: true)
        guard application.terminate() else {
            screenSaverControlFailed = true
            refreshLastError()
            NSLog("[ScreenBehaviorManager] Could not stop ScreenSaverEngine")
            return
        }
        screenSaverControlFailed = false
        refreshLastError()
        NSLog("[ScreenBehaviorManager] Prevented ScreenSaverEngine from remaining active")
    }

    private func refreshLastError() {
        let error: String?
        if screenSaverPreventionRequested && screenSaverControlFailed {
            error = L10n.string("Couldn't prevent the automatic screen lock.")
        } else {
            error = nil
        }
        // Runs on every heartbeat; @Published fires on every assignment.
        if lastError != error { lastError = error }
    }

    private var currentSessionIsLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
            let locked = session["CGSSessionScreenIsLocked"] as? Bool
        else {
            return isScreenLocked
        }
        return locked
    }
}
