//
//  FanController.swift
//  Awake
//

import Foundation
import Combine
import AppKit
import IOKit

@MainActor
public final class FanController: ObservableObject {
    public static let shared = FanController()

    @Published public private(set) var currentStatus: FanStatus = FanStatus(mode: .auto, isOverridden: false)
    @Published public private(set) var activeMode: FanMode = .auto
    @Published public private(set) var isTestModeActive: Bool = false
    @Published public private(set) var testModeEndDate: Date?
    @Published public private(set) var controlError: String?

    // SMC helper processes run at Default QoS. Matching their caller avoids a
    // priority inversion while waiting for a short privileged hardware command.
    private let queue = DispatchQueue(label: "pmgwork.awake.fancontroller", qos: .default)
    private var requestedMode: FanMode = .auto
    private var modeInFlight: FanMode?
    private var failedMode: FanMode?
    private var failedAt: Date?
    private var testResetTimer: Timer?
    private let testDuration: TimeInterval = 60
    /// A failed automatic restore is retried after this delay so the fail-safe
    /// recovers on its own without hammering the SMC on every heartbeat.
    private let autoRetryDelay: TimeInterval = 15

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
        refreshFanStatus()
        recoverAutomaticControlIfNeeded()
    }

    deinit {
        testResetTimer?.invalidate()
    }

    @objc private func handleAppWillTerminate() {
        cancelTestResetTimer()
        requestedMode = .auto
        isTestModeActive = false
        // Let a helper that is still starting up give up instead of blocking
        // termination behind the SMC engage.
        SMCHelper.shared.requestTermination()
        queue.sync {
            _ = SMCHelper.shared.setFanAuto(allowAuthorizationPrompt: false)
        }
    }

    /// Sets the fan mode according to policy
    public func setFanMode(_ mode: FanMode) {
        if requestedMode != mode {
            failedMode = nil
            failedAt = nil
        }
        requestedMode = mode
        applyRequestedModeIfNeeded()
    }

    /// Safe revert to Auto mode (Fail-Safe requirement).
    ///
    /// A failed restore is retried after `autoRetryDelay` instead of being
    /// blocked forever; `force` is used by explicit user actions.
    public func restoreAuto(force: Bool = false) {
        cancelTestResetTimer()
        if requestedMode != .auto {
            failedMode = nil
            failedAt = nil
        } else if !force,
                  failedMode == .auto,
                  let failedAt,
                  Date().timeIntervalSince(failedAt) < autoRetryDelay {
            // Still backing off: keep the failure so the 1 Hz heartbeat does
            // not hammer the SMC with a failing restore.
        } else {
            failedMode = nil
            failedAt = nil
        }
        requestedMode = .auto
        isTestModeActive = false
        applyRequestedModeIfNeeded()
    }

    private func applyRequestedModeIfNeeded() {
        guard modeInFlight == nil else { return }
        guard failedMode != requestedMode else { return }
        guard requestedMode != activeMode || controlError != nil else { return }

        let mode = requestedMode
        modeInFlight = mode
        queue.async {
            switch mode {
            case .auto:
                self.performRestoreAuto()
            case .maximum:
                self.performApplyMaximumCooling()
            case .aggressive:
                self.performApplyAggressiveCooling()
            case .moderate:
                self.performApplyModerateCooling()
            }
        }
    }

    private nonisolated func performRestoreAuto() {
        NSLog("[FanController] Fail-safe: Restoring fans to Auto (System SMC control)")
        let success = self.executeSMCRestoreAuto()

        Task { @MainActor in
            let controller = FanController.shared
            controller.isTestModeActive = false
            controller.finishApplying(
                mode: .auto,
                success: success,
                errorMessage: L10n.string("Could not restore automatic fan control. Restart the Mac if manual control remains active.")
            )
        }
    }

    private nonisolated func performApplyMaximumCooling() {
        NSLog("[FanController] Applying Maximum Fan Cooling for Closed Lid Mode")
        let success = self.executeSMCFanSpeed(targetMode: .maximum)

        Task { @MainActor in
            let controller = FanController.shared
            controller.finishApplying(
                mode: .maximum,
                success: success,
                errorMessage: L10n.string("Fan control failed because the SMC rejected the command. See the diagnostic log.")
            )
        }
    }

    private nonisolated func performApplyAggressiveCooling() {
        NSLog("[FanController] Applying Aggressive Fan Cooling")
        let success = self.executeSMCFanSpeed(targetMode: .aggressive)

        Task { @MainActor in
            let controller = FanController.shared
            controller.finishApplying(
                mode: .aggressive,
                success: success,
                errorMessage: L10n.string("Fan control failed because the SMC rejected the command. See the diagnostic log.")
            )
        }
    }

    private nonisolated func performApplyModerateCooling() {
        NSLog("[FanController] Applying Moderate Fan Cooling")
        let success = self.executeSMCFanSpeed(targetMode: .moderate)

        Task { @MainActor in
            let controller = FanController.shared
            controller.finishApplying(
                mode: .moderate,
                success: success,
                errorMessage: L10n.string("Fan control failed because the SMC rejected the command. See the diagnostic log.")
            )
        }
    }

    private func finishApplying(mode: FanMode, success: Bool, errorMessage: String) {
        modeInFlight = nil
        if success {
            failedMode = nil
            failedAt = nil
            activeMode = mode
            controlError = nil
            refreshFanStatus()
            refreshFanStatusAfterRamp()
        } else {
            failedMode = mode
            failedAt = Date()
            isTestModeActive = false
            cancelTestResetTimer()
            controlError = errorMessage
            refreshFanStatus()
        }

        // The policy may have changed while the SMC command was running. Apply
        // the latest request immediately instead of leaving requested/active
        // state out of sync until another lid event.
        if requestedMode != mode {
            applyRequestedModeIfNeeded()
        }
    }

    public func testFanSpeed(mode: FanMode) {
        if mode == .auto {
            restoreAuto(force: true)
            return
        }
        failedMode = nil
        failedAt = nil
        requestedMode = mode
        isTestModeActive = true
        scheduleTestReset()
        applyRequestedModeIfNeeded()
    }

    public func retryFanMode(_ mode: FanMode) {
        failedMode = nil
        failedAt = nil
        requestedMode = activeMode
        setFanMode(mode)
    }

    public func allowPolicyRetry() {
        failedMode = nil
        failedAt = nil
        requestedMode = activeMode
    }

    public func refreshFanStatus() {
        let mode = self.activeMode
        let overridden = (mode != .auto)
        let liveRPM = SMCClient.shared.getFanCurrentRPM(fanIndex: 0)
        let maxRPM = SMCClient.shared.getFanMaxRPM(fanIndex: 0) ?? 6000
        self.currentStatus = FanStatus(
            mode: mode,
            currentRPM: liveRPM,
            maxRPM: maxRPM,
            isOverridden: overridden
        )
    }

    private func refreshFanStatusAfterRamp() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.refreshFanStatus()
        }
    }

    // MARK: - SMC Control Implementations
    private nonisolated func executeSMCFanSpeed(targetMode: FanMode) -> Bool {
        NSLog("[FanController] Sending fan control command to AppleSMC (Mode: %@)", targetMode.rawValue)
        switch targetMode {
        case .maximum:
            return SMCHelper.shared.setFanMaximum()
        case .aggressive:
            return SMCHelper.shared.setFanAggressive()
        case .moderate:
            return SMCHelper.shared.setFanModerate()
        case .auto:
            return false
        }
    }

    private nonisolated func executeSMCRestoreAuto() -> Bool {
        NSLog("[FanController] Sending fan auto restore command to AppleSMC")
        return SMCHelper.shared.setFanAuto()
    }

    private func recoverAutomaticControlIfNeeded() {
        queue.async {
            guard SMCClient.shared.areAnyFansInManualMode() else { return }
            let success = SMCHelper.shared.setFanAuto(allowAuthorizationPrompt: false)
            Task { @MainActor in
                if success {
                    FanController.shared.activeMode = .auto
                    FanController.shared.controlError = nil
                    FanController.shared.refreshFanStatus()
                } else {
                    FanController.shared.controlError = L10n.string("Fans may be in manual mode. Restore Auto or restart the Mac.")
                }
            }
        }
    }

    private func scheduleTestReset() {
        testResetTimer?.invalidate()
        let endDate = Date().addingTimeInterval(testDuration)
        testModeEndDate = endDate
        testResetTimer = Timer.scheduledTimer(withTimeInterval: testDuration, repeats: false) { _ in
            Task { @MainActor in
                guard FanController.shared.testModeEndDate == endDate else { return }
                NSLog("[FanController] Fan test lease expired. Restoring Auto mode.")
                FanController.shared.restoreAuto()
            }
        }
    }

    private func cancelTestResetTimer() {
        testResetTimer?.invalidate()
        testResetTimer = nil
        testModeEndDate = nil
    }
}
