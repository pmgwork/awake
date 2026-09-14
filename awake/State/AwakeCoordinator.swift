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
    @Published public private(set) var completionGraceEndDate: Date?
    @Published public private(set) var remainingGraceSeconds: Int = 0
    @Published public private(set) var lastStateChange: Date = Date()
    @Published public private(set) var statusMessage: String = L10n.string("Idle")

    // Sub-services
    public let settings = SettingsStore.shared
    public let sleepManager = SleepManager.shared
    public let lidMonitor = LidMonitor.shared
    public let displayMonitor = DisplayMonitor.shared
    public let powerMonitor = PowerMonitor.shared
    public let eventMonitor = AgentEventMonitor.shared
    public let downloadMonitor = DownloadMonitor.shared
    public let hookIntegrationManager = HookIntegrationManager.shared
    public let thermalMonitor = ThermalMonitor.shared
    public let fanController = FanController.shared
    public let screenBehaviorManager = ScreenBehaviorManager.shared
    public let shortcutManager = GlobalShortcutManager.shared

    private var cancellables = Set<AnyCancellable>()
    private var heartbeatTimer: Timer?
    private var completionGrace = CompletionGracePeriod()

    private enum PersistenceKeys {
        static let timerEndDate = "pmgwork.awake.activeTimerEndDate"
    }

    private init() {
        eventMonitor.updateEnabledProviders(settings.enabledProviders)
        downloadMonitor.updateFolder(path: settings.downloadFolderPath)
        SMCHelper.shared.prewarmHelperInstallState()
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
        if settings.selectedMode == .whileAgentRunning {
            guard settings.agentMonitoringEnabled, eventMonitor.hasActiveSession else {
                statusMessage = settings.agentMonitoringEnabled
                    ? L10n.string("Waiting for Monitored Agent...")
                    : L10n.string("Agent Monitoring Paused")
                return
            }
        }
        if settings.selectedMode == .whileDownloading {
            guard settings.downloadMonitoringEnabled, downloadMonitor.isDownloading else {
                statusMessage = settings.downloadMonitoringEnabled
                    ? L10n.string("Waiting for Download...")
                    : L10n.string("Download Monitoring Paused")
                return
            }
        }
        guard !isLowBatteryCutoffActive else {
            statusMessage = L10n.format("Keep Awake Blocked (Battery %d%% or Lower)", settings.lowBatteryThreshold)
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
        case .whileDownloading:
            isActive = true
            statusMessage = L10n.string("Download Running: Keep Awake Active")
        }

        evaluateState()
    }

    // Only download completion, timer expiry, and battery cutoff opt into notifications.
    public func stopKeepAwake(reason: String? = nil, notify: Bool = false) {
        guard isActive else { return }

        let stopReason = reason ?? L10n.string("Awake is no longer preventing system sleep.")
        isActive = false
        completionGrace.reset()
        completionGraceEndDate = nil
        remainingGraceSeconds = 0
        remainingTimerSeconds = 0
        setTimerEndDate(nil)
        statusMessage = L10n.string("Keep Awake Stopped")

        evaluateState()
        if notify {
            sendNotification(
                title: L10n.string("Keep Awake Deactivated"),
                body: stopReason,
                identifier: "awake-deactivated-\(UUID().uuidString)"
            )
        }
    }

    public func toggleKeepAwake() {
        if isActive {
            stopKeepAwake(reason: L10n.string("Manually stopped by user."))
        } else {
            startKeepAwake()
        }
    }

    public func togglePrimaryAction() {
        switch settings.selectedMode {
        case .whileAgentRunning:
            setAgentMonitoringEnabled(!settings.agentMonitoringEnabled)
        case .whileDownloading:
            setDownloadMonitoringEnabled(!settings.downloadMonitoringEnabled)
        case .indefinitely, .timer:
            toggleKeepAwake()
        }
    }

    public func setAgentMonitoringEnabled(_ enabled: Bool) {
        guard settings.agentMonitoringEnabled != enabled else { return }
        settings.agentMonitoringEnabled = enabled

        if enabled {
            statusMessage = L10n.string("Waiting for Monitored Agent...")
            if eventMonitor.hasActiveSession {
                startKeepAwake()
            } else {
                evaluateState()
            }
        } else {
            if isActive && settings.selectedMode == .whileAgentRunning {
                stopKeepAwake(reason: L10n.string("Agent monitoring was paused."))
            } else {
                statusMessage = L10n.string("Agent Monitoring Paused")
                evaluateState()
            }
        }
    }

    public func setDownloadMonitoringEnabled(_ enabled: Bool) {
        guard settings.downloadMonitoringEnabled != enabled else { return }
        settings.downloadMonitoringEnabled = enabled

        if enabled {
            statusMessage = L10n.string("Waiting for Download...")
            if downloadMonitor.isDownloading {
                startKeepAwake()
            } else {
                evaluateState()
            }
        } else if isActive && settings.selectedMode == .whileDownloading {
            stopKeepAwake(reason: L10n.string("Download monitoring was paused."))
        } else {
            statusMessage = L10n.string("Download Monitoring Paused")
            evaluateState()
        }
    }

    public func selectMode(_ mode: KeepAwakeModeType) {
        guard settings.selectedMode != mode else { return }

        if isActive {
            stopKeepAwake()
        }

        settings.selectedMode = mode
        if mode == .whileAgentRunning && settings.agentMonitoringEnabled && eventMonitor.hasActiveSession {
            startKeepAwake()
        } else if mode == .whileDownloading && settings.downloadMonitoringEnabled && downloadMonitor.isDownloading {
            startKeepAwake()
        } else {
            evaluateState()
        }
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
        if completionGraceEndDate != nil {
            return formattedGraceStatus
        }
        if !isActive {
            if settings.selectedMode == .whileAgentRunning {
                return settings.agentMonitoringEnabled
                    ? L10n.string("Monitoring (Waiting for Agent)")
                    : L10n.string("Agent Monitoring Paused")
            }
            if settings.selectedMode == .whileDownloading {
                return settings.downloadMonitoringEnabled
                    ? L10n.string("Monitoring (Waiting for Download)")
                    : L10n.string("Download Monitoring Paused")
            }
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
        case .whileDownloading:
            return L10n.format("Downloading (%d)", downloadMonitor.activeDownloadCount)
        }
    }

    // MARK: - State Machine Evaluation
    public var formattedGraceStatus: String {
        L10n.format("Releasing in %@", String(format: "%d:%02d", remainingGraceSeconds / 60, remainingGraceSeconds % 60))
    }

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
                stopKeepAwake(reason: L10n.format("Battery reached %d%%. Awake was turned off.", batteryLevel), notify: true)
                return
            }
        }

        if isActive && (settings.selectedMode == .whileAgentRunning || settings.selectedMode == .whileDownloading) {
            let isAgentMode = settings.selectedMode == .whileAgentRunning
            let isRunning = isAgentMode ? eventMonitor.hasActiveSession : downloadMonitor.isDownloading
            let now = Date()
            completionGrace.update(isRunning: isRunning, now: now)
            completionGraceEndDate = completionGrace.endDate(duration: settings.completionGraceDuration)
            remainingGraceSeconds = completionGrace.remainingSeconds(duration: settings.completionGraceDuration, now: now)
            if isRunning {
                statusMessage = L10n.string(isAgentMode ? "Agent Running: Keep Awake Active" : "Download Running: Keep Awake Active")
            } else {
                statusMessage = formattedGraceStatus
                if remainingGraceSeconds == 0 {
                    stopKeepAwake(
                        reason: L10n.string(isAgentMode ? "All monitored agents finished." : "All downloads finished."),
                        notify: !isAgentMode
                    )
                    return
                }
            }
        }

        // Check Timer completion
        if isActive && settings.selectedMode == .timer {
            updateRemainingTimerSeconds()
            if remainingTimerSeconds <= 0 {
                NSLog("[AwakeCoordinator] Timer expired. Stopping Keep Awake.")
                stopKeepAwake(reason: L10n.string("Timer period completed."), notify: true)
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

        if settings.selectedMode == .whileAgentRunning && !eventMonitor.hasActiveSession && completionGraceEndDate == nil {
            transition(to: .idle)
            statusMessage = L10n.string("Waiting for Monitored Agent...")
            sleepManager.disableSleepPrevention()
            if !fanController.isTestModeActive {
                fanController.restoreAuto()
            }
            return
        }
        if settings.selectedMode == .whileDownloading && !downloadMonitor.isDownloading && completionGraceEndDate == nil {
            transition(to: .idle)
            statusMessage = L10n.string("Waiting for Download...")
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
                if !coordinator.isActive &&
                    coordinator.settings.selectedMode == .whileAgentRunning &&
                    coordinator.settings.agentMonitoringEnabled &&
                    running &&
                    !coordinator.isLowBatteryCutoffActive {
                    NSLog("[AwakeCoordinator] Monitored agent detected, auto-starting Keep Awake.")
                    coordinator.startKeepAwake()
                }
                coordinator.evaluateState()
            }
            .store(in: &cancellables)

        downloadMonitor.$isDownloading
            .receive(on: DispatchQueue.main)
            .sink { downloading in
                let coordinator = AwakeCoordinator.shared
                if !coordinator.isActive &&
                    coordinator.settings.selectedMode == .whileDownloading &&
                    coordinator.settings.downloadMonitoringEnabled &&
                    downloading &&
                    !coordinator.isLowBatteryCutoffActive {
                    NSLog("[AwakeCoordinator] Download detected, auto-starting Keep Awake.")
                    coordinator.startKeepAwake()
                }
                coordinator.evaluateState()
            }
            .store(in: &cancellables)

        settings.$downloadFolderPath
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { path in
                AwakeCoordinator.shared.downloadMonitor.updateFolder(path: path)
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

        Publishers.CombineLatest(
            settings.$preventDisplaySleep,
            settings.$preventScreenSaver
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.applyScreenBehaviorPolicy()
        }
        .store(in: &cancellables)

        // Keep the global hot key in sync with the persisted shortcut. The
        // publisher replays the stored value, so this also registers at launch.
        settings.$toggleShortcut
            .receive(on: DispatchQueue.main)
            .sink { shortcut in
                AwakeCoordinator.shared.shortcutManager.register(shortcut) {
                    AwakeCoordinator.shared.togglePrimaryAction()
                }
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
        settings.lowBatteryThreshold > 0 &&
            !powerMonitor.isOnACPower &&
            (powerMonitor.batteryLevel ?? 100) <= settings.lowBatteryThreshold
    }

    private func applyScreenBehaviorPolicy() {
        screenBehaviorManager.update(
            sessionActive: isActive && currentExecutionState != .idle,
            preventDisplaySleep: settings.preventDisplaySleep,
            preventScreenSaver: settings.preventScreenSaver
        )
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
            statusMessage = L10n.format("Keep Awake Blocked (Battery %d%% or Lower)", settings.lowBatteryThreshold)
            return
        }

        timerEndDate = endDate
        updateRemainingTimerSeconds()
        isActive = true
        statusMessage = L10n.format("Keep Awake Active (Timer: %@)", formattedRemainingTime)
        evaluateState()
    }
}
