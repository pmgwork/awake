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

    @Published public private(set) var isDisplaySleepPrevented = false
    @Published public private(set) var isScreenSaverPrevented = false
    @Published public private(set) var lastError: String?

    private let screenSaverBundleIdentifier = "com.apple.ScreenSaver.Engine"

    private var displaySleepAssertionID: IOPMAssertionID = 0
    private var screenSaverActivityAssertionID: IOPMAssertionID = 0
    private var displaySleepPreventionRequested = false
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
        preventDisplaySleep: Bool,
        preventScreenSaver: Bool
    ) {
        displaySleepPreventionRequested = sessionActive && preventDisplaySleep

        configureDisplaySleepPrevention(enabled: displaySleepPreventionRequested)
        isScreenSaverPrevented = sessionActive && preventScreenSaver
        if !isScreenSaverPrevented {
            screenSaverControlFailed = false
            if screenSaverActivityAssertionID != 0 {
                IOPMAssertionRelease(screenSaverActivityAssertionID)
                screenSaverActivityAssertionID = 0
            }
        }
        if isScreenSaverPrevented {
            stopRunningScreenSaverIfNeeded()
        }
        refreshLastError()
    }

    @objc private func handleAppWillTerminate() {
        configureDisplaySleepPrevention(enabled: false)
        isScreenSaverPrevented = false
        if screenSaverActivityAssertionID != 0 {
            IOPMAssertionRelease(screenSaverActivityAssertionID)
            screenSaverActivityAssertionID = 0
        }
    }

    private func configureDisplaySleepPrevention(enabled: Bool) {
        if enabled {
            guard displaySleepAssertionID == 0 else {
                isDisplaySleepPrevented = true
                return
            }

            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Awake: Preventing Display Sleep" as CFString,
                &displaySleepAssertionID
            )
            isDisplaySleepPrevented = result == kIOReturnSuccess && displaySleepAssertionID != 0
            if !isDisplaySleepPrevented {
                displaySleepAssertionID = 0
                NSLog(
                    "[ScreenBehaviorManager] Failed to create display sleep assertion: %d", result)
            }
        } else {
            releaseDisplaySleepAssertion()
        }
    }

    private func releaseDisplaySleepAssertion() {
        if displaySleepAssertionID != 0 {
            IOPMAssertionRelease(displaySleepAssertionID)
            displaySleepAssertionID = 0
        }
        isDisplaySleepPrevented = false
    }

    private func handleApplicationLaunch(_ application: NSRunningApplication) {
        guard isScreenSaverPrevented, !currentSessionIsLocked,
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
        if screenSaverActivityAssertionID != 0 {
            IOPMAssertionRelease(screenSaverActivityAssertionID)
            screenSaverActivityAssertionID = 0
        }
        _ = IOPMAssertionDeclareUserActivity(
            "Awake: Preventing Screen Saver" as CFString,
            kIOPMUserActiveLocal,
            &screenSaverActivityAssertionID
        )
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
        if displaySleepPreventionRequested && !isDisplaySleepPrevented {
            lastError = L10n.string("Display sleep prevention could not be enabled.")
        } else if isScreenSaverPrevented && screenSaverControlFailed {
            lastError = L10n.string("The running screen saver could not be stopped.")
        } else {
            lastError = nil
        }
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
