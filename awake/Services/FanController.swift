//
//  FanController.swift
//  Awake
//

import Foundation
import Combine
import AppKit

@MainActor
public final class FanController: ObservableObject {
    public static let shared = FanController()

    @Published public private(set) var activeMode: FanMode = .auto
    @Published public private(set) var controlError: String?

    // SMC helper processes run at Default QoS. Matching their caller avoids a
    // priority inversion while waiting for a short privileged hardware command.
    private let queue = DispatchQueue(label: "pmgwork.awake.fancontroller", qos: .default)
    private var requestedMode: FanMode = .auto
    private var modeInFlight: FanMode?
    private var failedMode: FanMode?
    private var failedAt: Date?
    private var watchdogTimer: Timer?
    private var isWatchdogCheckInFlight = false
    /// Only an explicit user action may ask for an administrator password to
    /// restore the fans. Automatic retries from the heartbeat never prompt.
    private var restorePromptAllowed = false
    /// A failed automatic restore is retried after this delay so the fail-safe
    /// recovers on its own without hammering the SMC on every heartbeat.
    private let autoRetryDelay: TimeInterval = 15
    /// The lease helper re-asserts manual control itself when macOS takes the
    /// fans back (thermalmonitord, or a sleep and wake). The watchdog only
    /// replaces a helper that exited and retries a failed engage.
    private let watchdogInterval: TimeInterval = 5
    /// A failed manual engage is retried after this delay instead of leaving
    /// cooling off until the mode changes. The engage itself can take up to
    /// about 30 seconds, so a short delay does not hammer the SMC.
    private let manualRetryDelay: TimeInterval = 5

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
        recoverAutomaticControlIfNeeded()
        startWatchdog()
    }

    deinit {
        watchdogTimer?.invalidate()
    }

    @objc private func handleAppWillTerminate() {
        requestedMode = .auto
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
        if force { restorePromptAllowed = true }
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
        applyRequestedModeIfNeeded()
    }

    private func applyRequestedModeIfNeeded() {
        guard modeInFlight == nil else { return }
        guard failedMode != requestedMode else { return }
        guard requestedMode != activeMode || controlError != nil else { return }

        let mode = requestedMode
        modeInFlight = mode
        let allowsPrompt = mode == .auto && restorePromptAllowed
        if mode == .auto { restorePromptAllowed = false }
        queue.async {
            switch mode {
            case .auto:
                self.performRestoreAuto(allowAuthorizationPrompt: allowsPrompt)
            case .maximum:
                self.performApplyMaximumCooling()
            case .aggressive:
                self.performApplyAggressiveCooling()
            case .moderate:
                self.performApplyModerateCooling()
            }
        }
    }

    private nonisolated func performRestoreAuto(allowAuthorizationPrompt: Bool) {
        NSLog("[FanController] Fail-safe: Restoring fans to Auto (System SMC control)")
        let success = self.executeSMCRestoreAuto(allowAuthorizationPrompt: allowAuthorizationPrompt)

        Task { @MainActor in
            let controller = FanController.shared
            controller.finishApplying(
                mode: .auto,
                success: success,
                errorMessage: L10n.string("Couldn't return the fans to automatic control. If they stay fast, restart your Mac.")
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
                errorMessage: L10n.string("Fan control failed because the SMC rejected the command. Check the diagnostic log.")
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
                errorMessage: L10n.string("Fan control failed because the SMC rejected the command. Check the diagnostic log.")
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
                errorMessage: L10n.string("Fan control failed because the SMC rejected the command. Check the diagnostic log.")
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
        } else {
            failedMode = mode
            failedAt = Date()
            controlError = errorMessage
        }

        // The policy may have changed while the SMC command was running. Apply
        // the latest request immediately instead of leaving requested/active
        // state out of sync until another lid event.
        if requestedMode != mode {
            applyRequestedModeIfNeeded()
        }
    }

    public func allowPolicyRetry() {
        failedMode = nil
        failedAt = nil
        requestedMode = activeMode
    }

    public func prepareForHelperRemoval() async -> Bool {
        restoreAuto(force: true)
        let deadline = Date().addingTimeInterval(60)
        while modeInFlight != nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return modeInFlight == nil && activeMode == .auto && controlError == nil
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

    private nonisolated func executeSMCRestoreAuto(allowAuthorizationPrompt: Bool) -> Bool {
        NSLog("[FanController] Sending fan auto restore command to AppleSMC")
        return SMCHelper.shared.setFanAuto(allowAuthorizationPrompt: allowAuthorizationPrompt)
    }

    private func recoverAutomaticControlIfNeeded() {
        queue.async {
            guard SMCClient.shared.areAnyFansInManualMode() else { return }
            let success = SMCHelper.shared.setFanAuto(allowAuthorizationPrompt: false)
            Task { @MainActor in
                if success {
                    FanController.shared.activeMode = .auto
                    FanController.shared.controlError = nil
                } else {
                    FanController.shared.controlError = L10n.string("The fans may still be under manual control. Restart your Mac to return them to automatic control.")
                }
            }
        }
    }

    // MARK: - Watchdog

    private func startWatchdog() {
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: watchdogInterval, repeats: true) { _ in
            Task { @MainActor in
                FanController.shared.verifyManualControl()
            }
        }
    }

    /// Re-applies a manual mode whose lease helper exited or whose engage failed.
    private func verifyManualControl() {
        let mode = requestedMode
        // Only the installed helper can engage without an authorization prompt.
        guard mode != .auto, modeInFlight == nil, SMCHelper.shared.checkHelperInstalled() else { return }

        if failedMode == mode {
            guard let failedAt, Date().timeIntervalSince(failedAt) >= manualRetryDelay else { return }
            NSLog("[FanController] Retrying fan mode %@ after a failure", mode.rawValue)
            failedMode = nil
            self.failedAt = nil
            applyRequestedModeIfNeeded()
            return
        }

        guard activeMode == mode, !isWatchdogCheckInFlight else { return }
        isWatchdogCheckInFlight = true
        queue.async {
            // Restarting a running lease would first return the fans to the
            // system, so only a helper that exited is replaced.
            let held = SMCHelper.shared.isFanControlLeaseRunning
            Task { @MainActor in
                let controller = FanController.shared
                controller.isWatchdogCheckInFlight = false
                guard !held,
                      controller.modeInFlight == nil,
                      controller.activeMode == mode,
                      controller.requestedMode == mode else { return }
                NSLog("[FanController] Fan control lease exited. Re-applying %@", mode.rawValue)
                // The fans are no longer in this mode; let the request apply again.
                controller.activeMode = .auto
                controller.applyRequestedModeIfNeeded()
            }
        }
    }
}
