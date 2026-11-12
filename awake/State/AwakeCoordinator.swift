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
    @Published public private(set) var isManualKeepAwakeActive = false
    @Published public private(set) var isAgentKeepAwakeActive = false
    @Published public private(set) var isDownloadKeepAwakeActive = false
    @Published public private(set) var isRemovingHardwareAuthorization = false
    @Published public private(set) var remainingTimerSeconds: Int = 0
    @Published public private(set) var timerEndDate: Date?
    /// End of the timed cooling mode; `nil` in every other mode.
    @Published public private(set) var forcedCoolingEndDate: Date?
    /// Whether the cooling mode currently wants the fans at 100%.
    @Published public private(set) var isForcedCoolingActive = false
    @Published public private(set) var isAutomaticCoolingActive = false
    @Published public private(set) var isManualCoolingActive = false
    @Published public private(set) var isRenderCoolingActive = false
    /// Whether the fan helper is installed. Published so the menu shows the
    /// cooling controls as soon as the asynchronous helper check finishes.
    @Published public private(set) var isFanHelperInstalled = false
    /// Whether a helper from an earlier version is installed and must be
    /// updated before cooling and closed-lid operation work again.
    @Published public private(set) var isFanHelperOutdated = false
    /// Whether the low-battery cutoff currently blocks the selected cooling mode.
    @Published public private(set) var isCoolingBlockedByLowBattery = false

    @Published public private(set) var agentCompletionGraceEndDate: Date?
    private var agentCompletionGrace = AgentCompletionGrace()

    // Sub-services
    public let settings = SettingsStore.shared
    public let sleepManager = SleepManager.shared
    public let lidMonitor = LidMonitor.shared
    public let displayMonitor = DisplayMonitor.shared
    public let powerMonitor = PowerMonitor.shared
    public let eventMonitor = AgentEventMonitor.shared
    public let downloadMonitor = DownloadMonitor.shared
    public let renderMonitor = RenderMonitor.shared
    public let hookIntegrationManager = HookIntegrationManager.shared
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
        renderMonitor.updateEnabledApps(settings.enabledRenderApps)
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
        guard !isRemovingHardwareAuthorization else { return }
        if isLowBatteryCutoffActive {
            guard userInitiated else {
                return
            }
            // A manual start below the threshold is allowed; remember it so the
            // fail-safe does not stop the session again until it ends or power
            // recovers.
            lowBatteryManualOverride = true
        }

        isManualKeepAwakeActive = true
        if settings.selectedMode == .timer {
            setTimerEndDate(Date().addingTimeInterval(settings.selectedTimerDuration))
            updateRemainingTimerSeconds()
        }

        evaluateState()
    }

    /// Explicit global stop (CLI and hardware removal) also disables automation.
    public func stopKeepAwake() {
        settings.agentMonitoringEnabled = false
        settings.downloadMonitoringEnabled = false
        agentCompletionGrace = AgentCompletionGrace()
        agentCompletionGraceEndDate = nil
        isAgentKeepAwakeActive = false
        isDownloadKeepAwakeActive = false
        isActive = false
        stopManualKeepAwake()
    }

    public func stopManualKeepAwake() {
        lowBatteryManualOverride = false
        isManualKeepAwakeActive = false
        remainingTimerSeconds = 0
        setTimerEndDate(nil)
        evaluateState()
    }

    // MARK: - Forced Cooling

    /// Whether the fan helper is installed and no battery fail-safe blocks
    /// the selected cooling mode.
    public var canUseForcedCooling: Bool {
        canStartCooling(settings.coolingMode)
    }

    /// Checks the requested mode before a CLI action changes the current selection.
    public func canStartCooling(_ mode: CoolingMode) -> Bool {
        !isRemovingHardwareAuthorization &&
            !(isLowBatteryCutoffEnforced && mode.stopsAtLowBattery) &&
            isFanHelperInstalled
    }

    private var isCoolingCutOffByLowBattery: Bool {
        isLowBatteryCutoffEnforced
    }

    /// Legacy automatic mode commands now enable the independent switch.
    public func selectCoolingMode(_ mode: CoolingMode) {
        if mode == .whileKeepAwakeIsOn {
            setAutomaticCoolingEnabled(true)
            return
        }
        guard settings.coolingMode != mode else { return }
        settings.coolingMode = mode
        stopManualCooling()
    }

    public func setAutomaticCoolingEnabled(_ enabled: Bool) {
        guard !enabled || canStartCooling(.whileKeepAwakeIsOn) else { return }
        settings.automaticCoolingEnabled = enabled
        evaluateState()
    }

    public func setRenderCoolingEnabled(_ enabled: Bool) {
        guard !enabled || canStartCooling(.whileKeepAwakeIsOn) else { return }
        settings.renderCoolingEnabled = enabled
        evaluateState()
    }

    /// Starts manual cooling. Refused when the helper is unavailable.
    public func startCooling() {
        guard canUseForcedCooling else { return }
        resetCoolingState()
        if settings.coolingMode == .timed {
            forcedCoolingEndDate = Date().addingTimeInterval(settings.forcedCoolingDuration)
        }
        settings.coolingArmed = true
        evaluateState()
    }

    /// Explicit global stop for CLI; the menu button controls manual cooling.
    public func stopCooling() {
        settings.automaticCoolingEnabled = false
        settings.renderCoolingEnabled = false
        stopManualCooling()
    }

    public func stopManualCooling() {
        settings.coolingArmed = false
        resetCoolingState()
        evaluateState()
    }

    public func toggleCooling() {
        if settings.coolingArmed {
            stopManualCooling()
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
        settings.automaticCoolingEnabled = false
        settings.renderCoolingEnabled = false
        settings.coolingArmed = false
        isAutomaticCoolingActive = false
        isManualCoolingActive = false
        isRenderCoolingActive = false
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
        if isManualKeepAwakeActive {
            stopManualKeepAwake()
        } else {
            startKeepAwake(userInitiated: true)
        }
    }

    public func togglePrimaryAction() {
        toggleKeepAwake()
    }

    public func setAgentMonitoringEnabled(_ enabled: Bool) {
        guard settings.agentMonitoringEnabled != enabled else { return }
        settings.agentMonitoringEnabled = enabled
        evaluateState()
    }

    public func setDownloadMonitoringEnabled(_ enabled: Bool) {
        guard settings.downloadMonitoringEnabled != enabled else { return }
        settings.downloadMonitoringEnabled = enabled
        evaluateState()
    }

    public func selectMode(_ mode: KeepAwakeModeType) {
        // Retain the legacy CLI names as independent automation commands.
        if mode == .whileAgentRunning {
            setAgentMonitoringEnabled(true)
            return
        }
        if mode == .whileDownloading {
            setDownloadMonitoringEnabled(true)
            return
        }
        guard settings.selectedMode != mode else { return }
        lowBatteryManualOverride = false
        isManualKeepAwakeActive = false
        remainingTimerSeconds = 0
        setTimerEndDate(nil)
        settings.selectedMode = mode
        evaluateState()
    }

    public func setTimerDuration(_ duration: TimeInterval) {
        guard duration > 0 else { return }
        settings.selectedTimerDuration = duration
        if isManualKeepAwakeActive && settings.selectedMode == .timer {
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
        let wasActive = isActive
        let wasDownloading = isDownloadKeepAwakeActive
        var completionReason: String?
        if isLowBatteryCutoffEnforced {
            if isManualKeepAwakeActive { isManualKeepAwakeActive = false }
            if remainingTimerSeconds != 0 { remainingTimerSeconds = 0 }
            if timerEndDate != nil { setTimerEndDate(nil) }
            if wasActive, let batteryLevel = powerMonitor.batteryLevel {
                completionReason = L10n.format("Battery is at %d%%, so Keep Awake stopped.", batteryLevel)
            }
        }

        if settings.agentMonitoringEnabled && !isLowBatteryCutoffEnforced {
            let end = agentCompletionGrace.update(
                running: eventMonitor.hasActiveSession,
                duration: settings.completionGraceDuration,
                now: Date()
            )
            if agentCompletionGraceEndDate != end { agentCompletionGraceEndDate = end }
        } else {
            agentCompletionGrace = AgentCompletionGrace()
            if agentCompletionGraceEndDate != nil { agentCompletionGraceEndDate = nil }
        }

        if isManualKeepAwakeActive && settings.selectedMode == .timer {
            updateRemainingTimerSeconds()
            if remainingTimerSeconds <= 0 {
                isManualKeepAwakeActive = false
                lowBatteryManualOverride = false
                setTimerEndDate(nil)
                completionReason = L10n.string("The set time has ended.")
            }
        }

        let policy = KeepAwakeActivity(
            manual: isManualKeepAwakeActive,
            agentEnabled: settings.agentMonitoringEnabled,
            agentRunning: eventMonitor.hasActiveSession,
            graceActive: agentCompletionGraceEndDate.map { $0 > Date() } ?? false,
            downloadEnabled: settings.downloadMonitoringEnabled,
            downloading: downloadMonitor.isDownloading,
            batteryBlocked: isLowBatteryCutoffEnforced
        )
        if isAgentKeepAwakeActive != policy.agent { isAgentKeepAwakeActive = policy.agent }
        if isDownloadKeepAwakeActive != policy.download { isDownloadKeepAwakeActive = policy.download }
        if isActive != policy.active { isActive = policy.active }
        if !isActive { lowBatteryManualOverride = false }
        if wasDownloading && !downloadMonitor.isDownloading && completionReason == nil {
            completionReason = L10n.string("All downloads finished.")
        }
        if wasActive && !isActive, let completionReason {
            sendNotification(title: L10n.string("Keep Awake Stopped"), body: completionReason,
                             identifier: "awake-deactivated-\(UUID().uuidString)")
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
    /// and hands them back to the system otherwise.
    private func applyFanPolicy() {
        if isForcedCoolingActive {
            fanController.setFanMode(isManualCoolingActive
                ? settings.manualCoolingFanMode : settings.automaticCoolingFanMode)
        } else {
            fanController.restoreAuto()
        }
    }

    private func updateForcedCooling(now: Date = Date()) {
        updateCoolingAvailability()

        if isRemovingHardwareAuthorization {
            settings.automaticCoolingEnabled = false
            settings.renderCoolingEnabled = false
            settings.coolingArmed = false
            resetCoolingState()
        }
        if settings.automaticCoolingEnabled && isCoolingCutOffByLowBattery {
            settings.automaticCoolingEnabled = false
            if let batteryLevel = powerMonitor.batteryLevel {
                sendNotification(
                    title: L10n.string("Automatic Cooling Stopped"),
                    body: L10n.format("Battery is at %d%%, so automatic cooling stopped.", batteryLevel),
                    identifier: "awake-cooling-stopped-\(UUID().uuidString)"
                )
            }
        }
        if settings.coolingArmed && settings.coolingMode == .timed,
           forcedCoolingEndDate.map({ $0 <= now }) ?? true {
            settings.coolingArmed = false
            resetCoolingState()
        }

        let activity = CoolingActivity(
            manualArmed: settings.coolingArmed,
            manualMode: settings.coolingMode,
            automaticEnabled: settings.automaticCoolingEnabled,
            automaticRequested: displayBehaviorPolicy.requestsAutomaticCooling(
                keepAwakeActive: isActive,
                onlyOnACPower: settings.onlyOnACPower,
                isOnACPower: powerMonitor.isOnACPower
            ),
            renderingRequested: settings.renderCoolingEnabled && renderMonitor.isRendering,
            batteryBlocked: isCoolingCutOffByLowBattery,
            helperAvailable: isFanHelperInstalled && !isRemovingHardwareAuthorization
        )
        if isManualCoolingActive != activity.manual { isManualCoolingActive = activity.manual }
        if isAutomaticCoolingActive != activity.automatic { isAutomaticCoolingActive = activity.automatic }
        if isRenderCoolingActive != activity.rendering { isRenderCoolingActive = activity.rendering }
        setForcedCoolingActive(activity.active)
    }

    private func updateCoolingAvailability() {
        // @Published fires on every assignment, and this runs on the 1 Hz heartbeat.
        let installed = SMCHelper.shared.checkHelperInstalled()
        if isFanHelperInstalled != installed {
            isFanHelperInstalled = installed
        }
        let outdated = !installed
            && SMCHelper.shared.hasCheckedHelperInstallState
            && SMCHelper.shared.isHelperToolPresent()
        if isFanHelperOutdated != outdated {
            isFanHelperOutdated = outdated
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
        settings.$agentMonitoringEnabled
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] needed in
                guard let self else { return }
                if needed { self.eventMonitor.startMonitoring() }
                else { self.eventMonitor.stopMonitoring() }
            }
            .store(in: &cancellables)

        settings.$downloadMonitoringEnabled
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { self.downloadMonitor.startMonitoring() }
                else { self.downloadMonitor.stopMonitoring() }
            }
            .store(in: &cancellables)

        // Observe Settings agents change
        settings.$monitoredAgents
            .receive(on: DispatchQueue.main)
            .sink { agents in
                AwakeCoordinator.shared.eventMonitor.updateEnabledProviders(Set(agents.filter(\.isEnabled).compactMap(\.provider)))
            }
            .store(in: &cancellables)

        eventMonitor.$hasActiveSession
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluateState() }
            .store(in: &cancellables)

        downloadMonitor.$isDownloading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluateState() }
            .store(in: &cancellables)

        settings.$enabledRenderApps
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] apps in self?.renderMonitor.updateEnabledApps(apps) }
            .store(in: &cancellables)

        settings.$renderCoolingEnabled
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { self.renderMonitor.startMonitoring() }
                else { self.renderMonitor.stopMonitoring() }
            }
            .store(in: &cancellables)

        renderMonitor.$renderingApps
            .map(\.isEmpty)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluateState() }
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
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { _ in
                AwakeCoordinator.shared.evaluateState()
            }
            .store(in: &cancellables)

        // Observe Display changes
        displayMonitor.$hasExternalDisplay
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { _ in
                AwakeCoordinator.shared.evaluateState()
            }
            .store(in: &cancellables)

        // Observe Power changes
        powerMonitor.$isOnACPower
            .removeDuplicates()
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

        settings.$keepScreenOn
            .removeDuplicates()
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
            keepScreenOn: settings.keepScreenOn,
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
        isManualKeepAwakeActive = true
        evaluateState()
    }
}
