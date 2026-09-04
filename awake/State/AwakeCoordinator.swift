//
//  AwakeCoordinator.swift
//  Awake
//

import Foundation
import Combine
import SwiftUI

@MainActor
public final class AwakeCoordinator: ObservableObject {
    public static let shared = AwakeCoordinator()

    // MARK: - Published State
    @Published public private(set) var isActive: Bool = false
    @Published public private(set) var currentExecutionState: AppExecutionState = .idle
    @Published public private(set) var remainingTimerSeconds: Int = 0
    @Published public private(set) var timerEndDate: Date?
    @Published public private(set) var lastStateChange: Date = Date()
    @Published public private(set) var statusMessage: String = L10n.string("Idle")

    // Sub-services
    public let settings = SettingsStore.shared
    public let sleepManager = SleepManager.shared
    public let lidMonitor = LidMonitor.shared
    public let displayMonitor = DisplayMonitor.shared
    public let powerMonitor = PowerMonitor.shared
    public let eventMonitor = AgentEventMonitor.shared
    public let hookIntegrationManager = HookIntegrationManager.shared
    public let thermalMonitor = ThermalMonitor.shared
    public let fanController = FanController.shared
    public let screenBehaviorManager = ScreenBehaviorManager.shared

    private var cancellables = Set<AnyCancellable>()
    private var heartbeatTimer: Timer?
    private var wasAgentRunning: Bool = false
    private var suppressAgentAutoStartUntilExit: Bool = false

    private enum PersistenceKeys {
        static let timerEndDate = "pmgwork.awake.activeTimerEndDate"
    }

    private init() {
        eventMonitor.updateEnabledProviders(settings.enabledProviders)
        setupSubscriptions()
        startHeartbeat()
        restorePersistedTimerIfNeeded()
    }

    deinit {
        heartbeatTimer?.invalidate()
    }

    // MARK: - User Intent Actions
    public func startKeepAwake() {
        guard !isActive else { return }
        guard !isLowBatteryCutoffActive else {
            statusMessage = L10n.string("Keep Awake Blocked (Battery 20% or Lower)")
            sendNotification(
                title: L10n.string("Keep Awake Blocked"),
                body: statusMessage,
                identifier: "awake-low-battery-blocked"
            )
            return
        }

        switch settings.selectedMode {
        case .whileAgentRunning:
            isActive = true
            statusMessage = eventMonitor.hasActiveSession
                ? L10n.string("Agent Running: Keep Awake Active")
                : L10n.string("Waiting for Monitored Agent...")
        case .indefinitely:
            isActive = true
            statusMessage = L10n.string("Keep Awake Active (Indefinitely)")
        case .timer:
            isActive = true
            setTimerEndDate(Date().addingTimeInterval(settings.selectedTimerDuration))
            updateRemainingTimerSeconds()
            statusMessage = L10n.format("Keep Awake Active (Timer: %@)", formattedRemainingTime)
        }

        evaluateState()
        sendNotification(
            title: L10n.string("Keep Awake Activated"),
            body: notificationDescriptionForCurrentMode,
            identifier: "awake-activated-\(UUID().uuidString)"
        )
    }

    public func stopKeepAwake(reason: String? = nil, manual: Bool = false) {
        guard isActive else { return }

        if manual && settings.selectedMode == .whileAgentRunning && eventMonitor.hasActiveSession {
            suppressAgentAutoStartUntilExit = true
        }

        let stopReason = reason ?? L10n.string("Awake is no longer preventing system sleep.")
        isActive = false
        remainingTimerSeconds = 0
        setTimerEndDate(nil)
        statusMessage = L10n.string("Keep Awake Stopped")

        evaluateState()
        sendNotification(
            title: L10n.string("Keep Awake Deactivated"),
            body: stopReason,
            identifier: "awake-deactivated-\(UUID().uuidString)"
        )
    }

    public func toggleKeepAwake() {
        if isActive {
            stopKeepAwake(reason: L10n.string("Manually stopped by user."), manual: true)
        } else {
            suppressAgentAutoStartUntilExit = false
            startKeepAwake()
        }
    }

    public func selectMode(_ mode: KeepAwakeModeType) {
        guard settings.selectedMode != mode else { return }

        if isActive {
            stopKeepAwake(reason: nil)
        }

        settings.selectedMode = mode
        suppressAgentAutoStartUntilExit = mode == .whileAgentRunning && eventMonitor.hasActiveSession
        wasAgentRunning = mode == .whileAgentRunning && eventMonitor.hasActiveSession
        evaluateState()
    }

    public func setTimerDuration(_ duration: TimeInterval) {
        guard duration > 0 else { return }
        settings.selectedTimerDuration = duration
        if isActive && settings.selectedMode == .timer {
            setTimerEndDate(Date().addingTimeInterval(duration))
            updateRemainingTimerSeconds()
        }
    }

    public var formattedRemainingTime: String {
        let totalSecs = remainingTimerSeconds
        let hours = totalSecs / 3600
        let minutes = (totalSecs % 3600) / 60
        let seconds = totalSecs % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    public var formattedTimerEndTime: String? {
        guard let timerEndDate else { return nil }
        return timerEndDate.formatted(date: .omitted, time: .shortened)
    }

    public var formattedMenuStatus: String {
        if !isActive {
            return L10n.string("Idle")
        }
        switch settings.selectedMode {
        case .whileAgentRunning:
            if eventMonitor.hasActiveSession {
                return L10n.format("Running (%@)", eventMonitor.activeProviderNames.sorted().joined(separator: ", "))
            } else {
                return L10n.string("Active (Waiting for Agent)")
            }
        case .indefinitely:
            return L10n.string("Active (Indefinitely)")
        case .timer:
            return L10n.format("Active (%@)", formattedRemainingTime)
        }
    }

    // MARK: - State Machine Evaluation
    public func evaluateState() {
        defer { applyScreenBehaviorPolicy() }
        // Global battery fail-safe: turn off Awake in every mode and restore
        // automatic fan control before the battery reaches a critical level.
        if isLowBatteryCutoffActive {
            if fanController.activeMode != .auto || fanController.isTestModeActive {
                fanController.restoreAuto()
            }
            if isActive, let batteryLevel = powerMonitor.batteryLevel {
                NSLog("[AwakeCoordinator] Battery reached %d%%. Turning Awake off.", batteryLevel)
                stopKeepAwake(reason: L10n.format("Battery reached %d%%. Awake was turned off.", batteryLevel))
                return
            }
        }

        // Check Agent Mode completion
        if isActive && settings.selectedMode == .whileAgentRunning {
            if wasAgentRunning && !eventMonitor.hasActiveSession {
                // All monitored agents just stopped!
                NSLog("[AwakeCoordinator] Monitored agents terminated. Stopping Keep Awake.")
                wasAgentRunning = false
                stopKeepAwake(reason: L10n.string("All monitored agents finished."))
                return
            }
            wasAgentRunning = eventMonitor.hasActiveSession
        }

        // Check Timer completion
        if isActive && settings.selectedMode == .timer {
            updateRemainingTimerSeconds()
            if remainingTimerSeconds <= 0 {
                NSLog("[AwakeCoordinator] Timer expired. Stopping Keep Awake.")
                stopKeepAwake(reason: L10n.string("Timer period completed."))
                return
            }
        }

        guard isActive else {
            // Idle State
            transition(to: .idle)
            sleepManager.disableSleepPrevention()
            if !fanController.isTestModeActive {
                fanController.restoreAuto()
            }
            return
        }

        if settings.selectedMode == .whileAgentRunning && !eventMonitor.hasActiveSession {
            transition(to: .idle)
            statusMessage = L10n.string("Waiting for Monitored Agent...")
            sleepManager.disableSleepPrevention()
            if !fanController.isTestModeActive {
                fanController.restoreAuto()
            }
            return
        }

        let isClosed = lidMonitor.isLidClosed
        let hasExternal = displayMonitor.hasExternalDisplay
        let isAC = powerMonitor.isOnACPower

        if !isClosed {
            // Awake / Lid Open
            transition(to: .awakeLidOpen)
            // caffeinate -s is AC-only. On battery, arm a limited-power system
            // assertion before the lid closes so the app remains scheduled long
            // enough to apply the M3/M4 fan unlock sequence.
            sleepManager.enableSleepPrevention(
                closedLid: false,
                prepareForClosedLid: !isAC,
                appliesToBattery: !isAC
            )
            if !fanController.isTestModeActive {
                fanController.restoreAuto()
            }
        } else if hasExternal && settings.excludeNormalClamshell {
            // Awake / Normal Clamshell (External Display Connected)
            transition(to: .normalClamshell)
            sleepManager.enableSleepPrevention(closedLid: false)
            if !fanController.isTestModeActive {
                fanController.restoreAuto()
            }
        } else {
            // Awake / Closed Lid Mode (No External Display)
            if settings.onlyOnACPower && !isAC {
                // AC power required but on battery: do not run fan cooling
                transition(to: .awakeLidOpen)
                sleepManager.enableSleepPrevention(closedLid: true, appliesToBattery: !isAC)
                if !fanController.isTestModeActive {
                    fanController.restoreAuto()
                }
            } else if settings.closedLidCoolingEnabled {
                // Apply Closed Lid Cooling
                transition(to: .awakeClosedLidCooling)
                sleepManager.enableSleepPrevention(closedLid: true, appliesToBattery: !isAC)
                if !fanController.isTestModeActive {
                    fanController.setFanMode(settings.closedLidFanMode)
                }
            } else {
                transition(to: .awakeLidOpen)
                sleepManager.enableSleepPrevention(closedLid: true, appliesToBattery: !isAC)
                if !fanController.isTestModeActive {
                    fanController.restoreAuto()
                }
            }
        }
    }

    private func transition(to state: AppExecutionState) {
        guard currentExecutionState != state else { return }
        currentExecutionState = state
        lastStateChange = Date()
    }

    // MARK: - Subscriptions & Heartbeat
    private func setupSubscriptions() {
        // Observe Settings agents change
        settings.$monitoredAgents
            .receive(on: DispatchQueue.main)
            .sink { agents in
                AwakeCoordinator.shared.eventMonitor.updateEnabledProviders(Set(agents.filter(\.isEnabled).compactMap(\.provider)))
            }
            .store(in: &cancellables)

        // Observe normalized Hook / Plugin session changes.
        eventMonitor.$hasActiveSession
            .receive(on: DispatchQueue.main)
            .sink { running in
                let coordinator = AwakeCoordinator.shared
                if !running {
                    coordinator.suppressAgentAutoStartUntilExit = false
                }
                if !coordinator.isActive &&
                    coordinator.settings.selectedMode == .whileAgentRunning &&
                    running &&
                    !coordinator.isLowBatteryCutoffActive &&
                    !coordinator.suppressAgentAutoStartUntilExit {
                    NSLog("[AwakeCoordinator] Monitored agent detected, auto-starting Keep Awake.")
                    coordinator.startKeepAwake()
                }
                coordinator.evaluateState()
            }
            .store(in: &cancellables)

        // Observe Lid state changes
        lidMonitor.$isLidClosed
            .receive(on: DispatchQueue.main)
            .sink { _ in
                AwakeCoordinator.shared.evaluateState()
            }
            .store(in: &cancellables)

        // Observe Display changes
        displayMonitor.$hasExternalDisplay
            .receive(on: DispatchQueue.main)
            .sink { _ in
                AwakeCoordinator.shared.evaluateState()
            }
            .store(in: &cancellables)

        // Observe Power changes
        powerMonitor.$isOnACPower
            .receive(on: DispatchQueue.main)
            .sink { _ in
                AwakeCoordinator.shared.evaluateState()
            }
            .store(in: &cancellables)

        powerMonitor.$batteryLevel
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { _ in
                AwakeCoordinator.shared.evaluateState()
            }
            .store(in: &cancellables)

        fanController.$controlError
            .compactMap { $0 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { error in
                AwakeCoordinator.shared.sendNotification(
                    title: L10n.string("Fan Control Failed"),
                    body: error,
                    identifier: "awake-fan-control-error"
                )
            }
            .store(in: &cancellables)

        sleepManager.$health
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { health in
                guard health == .degraded || health == .failed else { return }
                let coordinator = AwakeCoordinator.shared
                coordinator.sendNotification(
                    title: L10n.string("Sleep Prevention Problem"),
                    body: coordinator.sleepManager.lastError ?? health.displayName,
                    identifier: "awake-sleep-prevention-error"
                )
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            settings.$preventDisplaySleep,
            settings.$preventScreenSaver
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.applyScreenBehaviorPolicy()
        }
        .store(in: &cancellables)

        screenBehaviorManager.$lastError
            .compactMap { $0 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { error in
                AwakeCoordinator.shared.sendNotification(
                    title: L10n.string("Display Control Problem"),
                    body: error,
                    identifier: "awake-screen-behavior-error"
                )
            }
            .store(in: &cancellables)
    }

    private func startHeartbeat() {
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                let coordinator = AwakeCoordinator.shared
                if coordinator.isActive && coordinator.settings.selectedMode == .timer {
                    coordinator.updateRemainingTimerSeconds()
                }
                coordinator.evaluateState()
            }
        }
    }

    private var isLowBatteryCutoffActive: Bool {
        settings.stopAtLowBattery &&
            !powerMonitor.isOnACPower &&
            (powerMonitor.batteryLevel ?? 100) <= 20
    }

    private func applyScreenBehaviorPolicy() {
        screenBehaviorManager.update(
            sessionActive: isActive && currentExecutionState != .idle,
            preventDisplaySleep: settings.preventDisplaySleep,
            preventScreenSaver: settings.preventScreenSaver
        )
    }

    private var notificationDescriptionForCurrentMode: String {
        switch settings.selectedMode {
        case .whileAgentRunning:
            return L10n.string("Mode: While Agent is Running")
        case .indefinitely:
            return L10n.string("Mode: Indefinitely")
        case .timer:
            return L10n.format("Mode: Timer (%@)", formattedRemainingTime)
        }
    }

    private func sendNotification(title: String, body: String, identifier: String) {
        guard settings.notificationsEnabled else { return }
        NotificationManager.shared.sendNotification(
            title: title,
            body: body,
            identifier: identifier
        )
    }

    private func setTimerEndDate(_ endDate: Date?) {
        timerEndDate = endDate
        if let endDate {
            UserDefaults.standard.set(endDate, forKey: PersistenceKeys.timerEndDate)
        } else {
            UserDefaults.standard.removeObject(forKey: PersistenceKeys.timerEndDate)
        }
    }

    private func updateRemainingTimerSeconds(now: Date = Date()) {
        guard let timerEndDate else {
            remainingTimerSeconds = 0
            return
        }
        remainingTimerSeconds = max(0, Int(ceil(timerEndDate.timeIntervalSince(now))))
    }

    private func restorePersistedTimerIfNeeded() {
        guard let endDate = UserDefaults.standard.object(forKey: PersistenceKeys.timerEndDate) as? Date else {
            return
        }
        guard settings.selectedMode == .timer else {
            setTimerEndDate(nil)
            return
        }
        guard endDate > Date() else {
            setTimerEndDate(nil)
            sendNotification(
                title: L10n.string("Keep Awake Deactivated"),
                body: L10n.string("Timer period completed."),
                identifier: "awake-state-change"
            )
            return
        }
        guard !isLowBatteryCutoffActive else {
            setTimerEndDate(nil)
            sendNotification(
                title: L10n.string("Keep Awake Blocked"),
                body: L10n.string("Keep Awake Blocked (Battery 20% or Lower)"),
                identifier: "awake-low-battery-blocked"
            )
            return
        }

        timerEndDate = endDate
        updateRemainingTimerSeconds()
        isActive = true
        statusMessage = L10n.format("Keep Awake Active (Timer: %@)", formattedRemainingTime)
        evaluateState()
    }
}
