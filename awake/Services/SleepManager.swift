//
//  SleepManager.swift
//  Awake
//

import Foundation
import AppKit
import Combine
import IOKit.pwr_mgt

public enum SleepPreventionHealth: String, Equatable {
    case inactive
    case active
    case degraded
    case failed

    public var displayName: String {
        switch self {
        case .inactive:
            return L10n.string("Inactive")
        case .active:
            return L10n.string("Active")
        case .degraded:
            return L10n.string("Degraded")
        case .failed:
            return L10n.string("Failed")
        }
    }
}

public final class SleepManager: ObservableObject {
    public static let shared = SleepManager()

    private var assertionID: IOPMAssertionID = 0
    private var closedLidAssertionID: IOPMAssertionID = 0
    private var closedLidAssertionAppliesToBattery = false
    private var caffeinateProcess: Process?
    private var batteryAssertionProcess: Process?
    @Published public private(set) var isSleepPrevented: Bool = false
    @Published public private(set) var isClosedLidMode: Bool = false
    @Published public private(set) var health: SleepPreventionHealth = .inactive
    @Published public private(set) var lastError: String?

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    deinit {
        releaseAllAssertions()
    }

    @objc private func handleAppWillTerminate() {
        releaseAllAssertions()
    }

    /// Enable sleep prevention.
    /// If `closedLid` is true, we take strong system-sleep prevention to avoid clamshell sleep.
    public func enableSleepPrevention(
        closedLid: Bool = false,
        prepareForClosedLid: Bool = false,
        appliesToBattery: Bool = false
    ) {
        self.isClosedLidMode = closedLid

        // Standard idle system sleep prevention (allows display sleep and screen lock)
        if assertionID == 0 {
            let reason = "Awake: Preventing System Sleep" as CFString
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &assertionID
            )
            if result != kIOReturnSuccess {
                NSLog("[SleepManager] Failed to create user idle sleep assertion: %d", result)
            } else {
                NSLog("[SleepManager] User idle system sleep assertion created (ID: %u)", assertionID)
            }
        }

        // Closed-lid system sleep assertion
        if closedLid || prepareForClosedLid {
            if closedLidAssertionID != 0,
               closedLidAssertionAppliesToBattery != appliesToBattery {
                releaseClosedLidAssertion()
            }

            if closedLidAssertionID == 0 {
                let closedReason = "Awake: Closed-Lid Keep Awake" as CFString
                let result = IOPMAssertionCreateWithName(
                    kIOPMAssertionTypePreventSystemSleep as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    closedReason,
                    &closedLidAssertionID
                )
                if result != kIOReturnSuccess {
                    NSLog("[SleepManager] Failed to create closed lid sleep assertion: %d", result)
                } else {
                    closedLidAssertionAppliesToBattery = appliesToBattery
                    NSLog(
                        "[SleepManager] Closed lid system sleep assertion created (ID: %u, battery: %@)",
                        closedLidAssertionID,
                        appliesToBattery ? "yes" : "no"
                    )
                }
            }

            // Caffeinate process fallback for closed lid
            if let process = caffeinateProcess, !process.isRunning {
                caffeinateProcess = nil
            }
            if closedLid && !appliesToBattery && caffeinateProcess == nil {
                startCaffeinateProcess()
            } else if !closedLid {
                stopCaffeinateProcess()
            }

            if let process = batteryAssertionProcess, !process.isRunning {
                batteryAssertionProcess = nil
            }
            if appliesToBattery && batteryAssertionProcess == nil {
                batteryAssertionProcess = SMCHelper.shared.startBatterySleepAssertion()
            } else if !appliesToBattery {
                stopBatteryAssertionProcess()
            }
        } else {
            // Not closed lid, release closed lid specific assertions if held
            releaseClosedLidAssertion()
        }

        updatePublishedStatus(
            expectsClosedLidAssertion: closedLid || prepareForClosedLid,
            expectsCaffeinate: closedLid && !appliesToBattery,
            expectsBatteryHelper: (closedLid || prepareForClosedLid) && appliesToBattery
        )
    }

    /// Disable all sleep prevention and return system to normal power management.
    public func disableSleepPrevention() {
        releaseAllAssertions()
    }

    private func releaseClosedLidAssertion() {
        if closedLidAssertionID != 0 {
            IOPMAssertionRelease(closedLidAssertionID)
            NSLog("[SleepManager] Released closed lid assertion (ID: %u)", closedLidAssertionID)
            closedLidAssertionID = 0
        }
        closedLidAssertionAppliesToBattery = false
        stopCaffeinateProcess()
        stopBatteryAssertionProcess()
    }

    private func releaseAllAssertions() {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            NSLog("[SleepManager] Released user idle assertion (ID: %u)", assertionID)
            assertionID = 0
        }
        releaseClosedLidAssertion()
        isSleepPrevented = false
        isClosedLidMode = false
        health = .inactive
        lastError = nil
    }

    private func startCaffeinateProcess() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        // -s: Prevent system sleep (on AC power) without simulating user activity or waking display
        // -w: Release the assertion and exit when Awake exits, so a crash or
        //     force-quit cannot leave the Mac permanently awake.
        process.arguments = [
            "-s",
            "-w", String(ProcessInfo.processInfo.processIdentifier),
        ]
        do {
            try process.run()
            self.caffeinateProcess = process
            NSLog("[SleepManager] Started helper caffeinate process (PID: %d)", process.processIdentifier)
        } catch {
            NSLog("[SleepManager] Failed to launch caffeinate helper: %@", error.localizedDescription)
        }
    }

    private func stopCaffeinateProcess() {
        if let proc = caffeinateProcess {
            if proc.isRunning {
                proc.terminate()
                NSLog("[SleepManager] Terminated caffeinate helper process")
            }
            caffeinateProcess = nil
        }
    }

    private func stopBatteryAssertionProcess() {
        if let process = batteryAssertionProcess {
            if process.isRunning {
                process.terminate()
                NSLog("[SleepManager] Terminated battery closed-lid assertion helper")
            }
            batteryAssertionProcess = nil
        }
    }

    private func updatePublishedStatus(
        expectsClosedLidAssertion: Bool,
        expectsCaffeinate: Bool,
        expectsBatteryHelper: Bool
    ) {
        var failures: [String] = []

        if assertionID == 0 {
            failures.append(L10n.string("Idle sleep assertion could not be created."))
        }

        if expectsClosedLidAssertion && closedLidAssertionID == 0 {
            failures.append(L10n.string("Closed-lid sleep assertion could not be created."))
        }

        if expectsCaffeinate && caffeinateProcess?.isRunning != true {
            failures.append(L10n.string("The caffeinate fallback is not running."))
        }

        if expectsBatteryHelper && batteryAssertionProcess?.isRunning != true {
            failures.append(L10n.string("The battery closed-lid helper is not running."))
        }

        let isEffective: Bool
        if isClosedLidMode {
            if expectsBatteryHelper {
                isEffective = batteryAssertionProcess?.isRunning == true
            } else {
                isEffective = closedLidAssertionID != 0 || caffeinateProcess?.isRunning == true
            }
        } else {
            isEffective = assertionID != 0
        }

        isSleepPrevented = isEffective
        lastError = failures.isEmpty ? nil : failures.joined(separator: " ")

        if !isEffective {
            health = .failed
        } else if failures.isEmpty {
            health = .active
        } else {
            health = .degraded
        }
    }
}
