//
//  AwakeCoordinator.swift
//  Awake
//

import Foundation
import Combine

@MainActor
public final class AwakeCoordinator: ObservableObject {
    public static let shared = AwakeCoordinator()

    // MARK: - Published State
    @Published public private(set) var isActive: Bool = false
    @Published public private(set) var isRemovingHardwareAuthorization = false
    @Published public private(set) var remainingTimerSeconds: Int = 0
    @Published public private(set) var timerEndDate: Date?
    /// End of the timed cooling mode; `nil` in every other mode.
    @Published public private(set) var forcedCoolingEndDate: Date?
    /// Whether the cooling mode currently wants the fans at 100%.
    @Published public private(set) var isForcedCoolingActive = false
    /// Whether the fan helper is installed. Published so the menu shows the
    /// cooling controls as soon as the asynchronous helper check finishes.
    @Published public private(set) var isFanHelperInstalled = false
    /// Whether the low-battery cutoff currently blocks the selected cooling mode.
    @Published public private(set) var isCoolingBlockedByLowBattery = false

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
    private let legacyScreenLockRecovery = LegacyScreenLockRecovery.shared
    public let closedDisplayModeManager = ClosedDisplayModeManager.shared
    public let lowPowerModeManager = LowPowerModeManager.shared

    private var cancellables = Set<AnyCancellable>()
    private var heartbeatTimer: Timer?
    /// Set when the user manually starts Keep Awake while the low-battery
    /// cutoff applies. It suspends the fail-safe for that session so a manual
    /// start is not immediately undone by the heartbeat.
    private var lowBatteryManualOverride = false

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
        // A Low Power Mode setting left over from a session that ended
        // without restoring it (for example after a restart).
        Task { await lowPowerModeManager.restoreSavedStateIfNeeded() }
    }

    deinit {
        heartbeatTimer?.invalidate()
    }

    // MARK: - User Intent Actions

    /// Starts Keep Awake. Actions driven by the user pass
    /// `userInitiated: true`, which lets them start even below the battery
    /// cutoff; automatic starts stay paused while the cutoff applies.
    public func startKeepAwake(userInitiated: Bool = false) {
        guard !isActive, !isRemovingHardwareAuthorization else { return }
        if settings.selectedMode == .whileAgentRunning {
            guard settings.agentMonitoringEnabled, eventMonitor.hasActiveSession else {
                return
            }
        }
        if settings.selectedMode == .whileDownloading {
            guard settings.downloadMonitoringEnabled, downloadMonitor.isDownloading else {
                return
            }
        }
        if isLowBatteryCutoffActive {
            guard userInitiated else {
                return
            }
            // A manual start below the threshold is allowed; remember it so the
            // fail-safe does not stop the session again until it ends or power
            // recovers.
            lowBatteryManualOverride = true
        }

        isActive = true
        if settings.selectedMode == .timer {
            setTimerEndDate(Date().addingTimeInterval(settings.selectedTimerDuration))
            updateRemainingTimerSeconds()
        }

        evaluateState()
    }

    // Only download completion, timer expiry, and battery cutoff opt into notifications.
    public func stopKeepAwake(reason: String? = nil, notify: Bool = false) {
        guard isActive else { return }

        isActive = false
        lowBatteryManualOverride = false
        remainingTimerSeconds = 0
        setTimerEndDate(nil)

        evaluateState()
        if notify {
            sendNotification(
                title: L10n.string("Keep Awake Stopped"),
                body: reason ?? L10n.string("Your Mac can sleep normally again."),
                identifier: "awake-deactivated-\(UUID().uuidString)"
            )
        }
    }

    // MARK: - Forced Cooling

    /// Whether the fan helper is installed and no battery fail-safe blocks
    /// the selected cooling mode.
    public var canUseForcedCooling: Bool {
        !isRemovingHardwareAuthorization &&
            !isCoolingCutOffByLowBattery &&
            isFanHelperInstalled
    }

    private var isCoolingCutOffByLowBattery: Bool {
        isLowBatteryCutoffEnforced && settings.coolingMode.stopsAtLowBattery
    }

    /// Selects a cooling mode. Switching modes while cooling is running stops
    /// it, like switching a Keep Awake mode; conditional modes start waiting
    /// for their condition right away.
    public func selectCoolingMode(_ mode: CoolingMode) {
        guard settings.coolingMode != mode else { return }
        settings.coolingMode = mode
        stopCooling()
        if mode.startsOnSelect {
            startCooling()
        }
    }

    /// Starts the selected cooling mode. Refused when the helper is missing or
    /// the battery fail-safe applies.
    public func startCooling() {
        guard canUseForcedCooling else { return }
        resetCoolingState()
        if settings.coolingMode == .timed {
            forcedCoolingEndDate = Date().addingTimeInterval(settings.forcedCoolingDuration)
        }
        settings.coolingArmed = true
        evaluateState()
    }

    public func stopCooling() {
        settings.coolingArmed = false
        resetCoolingState()
        evaluateState()
    }

    public func toggleCooling() {
        if settings.coolingArmed {
            stopCooling()
        } else {
            startCooling()
        }
    }

    public func setCoolingDuration(_ duration: TimeInterval) {
        guard duration > 0 else { return }
        settings.forcedCoolingDuration = duration
        if settings.coolingArmed && settings.coolingMode == .timed {
            forcedCoolingEndDate = Date().addingTimeInterval(duration)
            evaluateState()
        }
    }

    private func resetCoolingState() {
        forcedCoolingEndDate = nil
    }

    public func removeHardwareAuthorization() async -> Bool {
        guard !isRemovingHardwareAuthorization else { return false }
        isRemovingHardwareAuthorization = true
        defer { isRemovingHardwareAuthorization = false }
        settings.coolingArmed = false
        resetCoolingState()
        setForcedCoolingActive(false)

        // Block automatic restarts while each existing helper releases its
        // override. Never delete the privileged tool if restoration fails.
        let sleepStopped = await sleepManager.prepareForHelperRemoval()
        stopKeepAwake()
        let lidStopped = await closedDisplayModeManager.prepareForHelperRemoval()
        let lowPowerStopped = await lowPowerModeManager.prepareForHelperRemoval()
        let fansStopped = await fanController.prepareForHelperRemoval()
        guard sleepStopped, lidStopped, lowPowerStopped, fansStopped else { return false }
        guard await SMCHelper.shared.removeHelperTool() else { return false }
        settings.closedDisplayModeEnabled = false
        settings.lowPowerModeWhenLidClosed = false
        await closedDisplayModeManager.refreshHelperState()
        return true
    }

    public func toggleKeepAwake() {
        if isActive {
            stopKeepAwake()
        } else {
            startKeepAwake(userInitiated: true)
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
            if eventMonitor.hasActiveSession {
                startKeepAwake(userInitiated: true)
            } else {
                evaluateState()
            }
        } else {
            if isActive && settings.selectedMode == .whileAgentRunning {
                stopKeepAwake()
            } else {
                evaluateState()
            }
        }
    }

    public func setDownloadMonitoringEnabled(_ enabled: Bool) {
        guard settings.downloadMonitoringEnabled != enabled else { return }
        settings.downloadMonitoringEnabled = enabled

        if enabled {
            if downloadMonitor.isDownloading {
                startKeepAwake(userInitiated: true)
            } else {
                evaluateState()
            }
        } else if isActive && settings.selectedMode == .whileDownloading {
            stopKeepAwake()
        } else {
            evaluateState()
        }
    }

    public func selectMode(_ mode: KeepAwakeModeType) {
        guard settings.selectedMode != mode else { return }

        if isActive {
            stopKeepAwake()
        }

        settings.selectedMode = mode
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

    // MARK: - Sleep Prevention Policy
    public func evaluateState() {
        defer {
            applyScreenBehaviorPolicy()
            legacyScreenLockRecovery.restoreIfNeeded()
            applyClosedDisplayModePolicy()
            applyLowPowerModePolicy()
        }
        guard !isRemovingHardwareAuthorization else { return }
        // Plugging in does not end the override: unplugging again at the same
        // charge would otherwise stop a session the user started on purpose.
        if !isBatteryAtCutoffLevel {
            lowBatteryManualOverride = false
        }
        // Global battery fail-safe: turn off Keep Awake in every mode and stop
        // automatic cooling when the battery reaches the configured level.
        // Manual cooling keeps running. A manual start below the threshold
        // suspends the fail-safe until the session ends or the charge recovers.
        if isLowBatteryCutoffEnforced {
            if fanController.isTestModeActive {
                fanController.restoreAuto()
            }
            if isActive, let batteryLevel = powerMonitor.batteryLevel {
                NSLog("[AwakeCoordinator] Battery reached %d%%. Turning Awake off.", batteryLevel)
                stopKeepAwake(reason: L10n.format("Battery is at %d%%, so Keep Awake stopped.", batteryLevel), notify: true)
                return
            }
        }

        if isActive && (settings.selectedMode == .whileAgentRunning || settings.selectedMode == .whileDownloading) {
            let isAgentMode = settings.selectedMode == .whileAgentRunning
            let isRunning = isAgentMode ? eventMonitor.hasActiveSession : downloadMonitor.isDownloading
            if !isRunning {
                stopKeepAwake(
                    reason: L10n.string(isAgentMode ? "All monitored agents have finished." : "All downloads finished."),
                    notify: !isAgentMode
                )
                return
            }
        }

        // Check Timer completion
        if isActive && settings.selectedMode == .timer {
            updateRemainingTimerSeconds()
            if remainingTimerSeconds <= 0 {
                NSLog("[AwakeCoordinator] Timer expired. Stopping Keep Awake.")
                stopKeepAwake(reason: L10n.string("The set time has ended."), notify: true)
                return
            }
        }

        updateForcedCooling()

        guard isActive else {
            // Idle State
            sleepManager.disableSleepPrevention()
            applyFanPolicy()
            return
        }

        let isClosed = lidMonitor.isLidClosed
        let hasExternal = displayMonitor.hasExternalDisplay
        let isAC = powerMonitor.isOnACPower

        if !isClosed {
            // Awake / Lid Open
            // caffeinate -s is AC-only. On battery, arm a limited-power system
            // assertion before the lid closes so the app remains scheduled long
            // enough to apply the M3/M4 fan unlock sequence.
            sleepManager.enableSleepPrevention(
                closedLid: false,
                prepareForClosedLid: !isAC,
                appliesToBattery: !isAC
            )
        } else if hasExternal {
            // Awake / Normal Clamshell (External Display Connected)
            sleepManager.enableSleepPrevention(closedLid: false)
        } else {
            // Awake / Closed Lid Mode (No External Display)
            sleepManager.enableSleepPrevention(closedLid: true, appliesToBattery: !isAC)
        }
        // Fans last, once the sleep assertion is in place.
        applyFanPolicy()
    }

    /// Runs the fans at the cooling fan speed while a cooling mode wants it,
    /// and hands them back to the system otherwise. A fan test owns the fans
    /// while it runs.
    private func applyFanPolicy() {
        guard displayBehaviorPolicy.allowsCooling else {
            fanController.restoreAuto()
            return
        }
        guard !fanController.isTestModeActive else { return }
        if isForcedCoolingActive {
            fanController.setFanMode(settings.coolingMode == .whileAgentRunning
                ? settings.automaticCoolingFanMode : settings.manualCoolingFanMode)
        } else {
            fanController.restoreAuto()
        }
    }

    private func updateForcedCooling(now: Date = Date()) {
        updateCoolingAvailability()

        if settings.coolingArmed && isRemovingHardwareAuthorization {
            settings.coolingArmed = false
            resetCoolingState()
        }
        if settings.coolingArmed && isCoolingCutOffByLowBattery {
            settings.coolingArmed = false
            resetCoolingState()
            if let batteryLevel = powerMonitor.batteryLevel {
                NSLog("[AwakeCoordinator] Battery reached %d%%. Stopping agent cooling.", batteryLevel)
                sendNotification(
                    title: L10n.string("Agent Cooling Stopped"),
                    body: L10n.format("Battery is at %d%%, so agent cooling stopped.", batteryLevel),
                    identifier: "awake-cooling-stopped-\(UUID().uuidString)"
                )
            }
        }

        // While the helper is missing (or its state is still being read at
        // launch) a started mode stays started but cannot act yet.
        var active = false
        if settings.coolingArmed && isFanHelperInstalled {
            switch settings.coolingMode {
            case .forced:
                active = true
            case .timed:
                if let end = forcedCoolingEndDate, end > now {
                    active = true
                } else {
                    // The timer ran out: stop, keeping the selected mode.
                    settings.coolingArmed = false
                    resetCoolingState()
                }
            case .whileAgentRunning:
                active = isAgentCoolingNeeded
            }
        }
        setForcedCoolingActive(active && displayBehaviorPolicy.allowsCooling)
    }

    /// Agent cooling runs only with the lid closed and no external display.
    private var isAgentCoolingNeeded: Bool {
        guard eventMonitor.hasActiveSession else { return false }
        guard displayBehaviorPolicy.allowsAgentCooling else { return false }
        if settings.onlyOnACPower && !powerMonitor.isOnACPower { return false }
        return true
    }

    private func updateCoolingAvailability() {
        // @Published fires on every assignment, and this runs on the 1 Hz heartbeat.
        let installed = SMCHelper.shared.checkHelperInstalled()
        if isFanHelperInstalled != installed {
            isFanHelperInstalled = installed
        }
        let blocked = isCoolingCutOffByLowBattery
        if isCoolingBlockedByLowBattery != blocked {
            isCoolingBlockedByLowBattery = blocked
        }
    }

    private func setForcedCoolingActive(_ active: Bool) {
        // @Published fires on every assignment, and this runs on the 1 Hz heartbeat.
        guard isForcedCoolingActive != active else { return }
        isForcedCoolingActive = active
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

        // Re-apply the battery fail-safe when the threshold itself changes.
        settings.$lowBatteryThreshold
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { _ in
                let coordinator = AwakeCoordinator.shared
                coordinator.lowBatteryManualOverride = false
                coordinator.evaluateState()
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

    }

    private func startHeartbeat() {
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                let coordinator = AwakeCoordinator.shared
                coordinator.evaluateState()
            }
        }
    }

    private var isBatteryAtCutoffLevel: Bool {
        settings.lowBatteryThreshold > 0 &&
            (powerMonitor.batteryLevel ?? 100) <= settings.lowBatteryThreshold
    }

    private var isLowBatteryCutoffActive: Bool {
        isBatteryAtCutoffLevel && !powerMonitor.isOnACPower
    }

    /// Whether the cutoff should still stop Awake or block automatic starts.
    private var isLowBatteryCutoffEnforced: Bool {
        isLowBatteryCutoffActive && !lowBatteryManualOverride
    }

    private func applyScreenBehaviorPolicy() {
        screenBehaviorManager.update(
            sessionActive: isActive,
            preventDisplaySleep: settings.preventDisplaySleep,
            preventScreenSaver: settings.preventScreenSaver,
            lidClosed: lidMonitor.isLidClosed,
            hasExternalDisplay: displayMonitor.hasExternalDisplay
        )
    }

    private func applyClosedDisplayModePolicy() {
        closedDisplayModeManager.update(
            sessionActive: isActive && !isRemovingHardwareAuthorization,
            enabled: settings.closedDisplayModeEnabled && displayBehaviorPolicy.needsClosedDisplayOverride
        )
    }

    private var displayBehaviorPolicy: DisplayBehaviorPolicy {
        DisplayBehaviorPolicy(
            lidClosed: lidMonitor.isLidClosed,
            hasExternalDisplay: displayMonitor.hasExternalDisplay
        )
    }

    /// Low Power Mode while the lid is closed during a session, unless an
    /// external display is attached (the Mac is then in normal clamshell use).
    private func applyLowPowerModePolicy() {
        lowPowerModeManager.update(
            requested: isActive
                && !isRemovingHardwareAuthorization
                && settings.closedDisplayModeEnabled
                && settings.lowPowerModeWhenLidClosed
                && lidMonitor.isLidClosed
                && !displayMonitor.hasExternalDisplay
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
                title: L10n.string("Keep Awake Stopped"),
                body: L10n.string("The set time has ended."),
                identifier: "awake-state-change"
            )
            return
        }
        guard !isLowBatteryCutoffActive else {
            setTimerEndDate(nil)
            return
        }

        timerEndDate = endDate
        updateRemainingTimerSeconds()
        isActive = true
        evaluateState()
    }
}
