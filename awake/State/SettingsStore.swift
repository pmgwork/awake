//
//  SettingsStore.swift
//  Awake
//

import Foundation
import Combine
import ServiceManagement

@MainActor
public final class SettingsStore: ObservableObject {
    public static let shared = SettingsStore()

    private enum Keys {
        static let monitoredAgents = "pmgwork.awake.monitoredAgents"
        static let selectedMode = "pmgwork.awake.selectedMode"
        static let agentMonitoringEnabled = "pmgwork.awake.agentMonitoringEnabled"
        static let downloadMonitoringEnabled = "pmgwork.awake.downloadMonitoringEnabled"
        static let downloadFolderPath = "pmgwork.awake.downloadFolderPath"
        static let completionGraceDuration = "pmgwork.awake.completionGraceDuration"
        static let selectedTimerDuration = "pmgwork.awake.selectedTimerDuration"
        /// Replaced by the "While Keep Awake Is On" cooling mode; read once to migrate.
        static let legacyClosedLidCoolingEnabled = "pmgwork.awake.closedLidCoolingEnabled"
        static let coolingFanMode = "pmgwork.awake.coolingFanMode"
        static let automaticCoolingFanMode = "pmgwork.awake.automaticCoolingFanMode"
        static let manualCoolingFanMode = "pmgwork.awake.manualCoolingFanMode"
        /// Renamed to coolingFanMode; read once to migrate.
        static let legacyClosedLidFanMode = "pmgwork.awake.closedLidFanMode"
        static let onlyOnACPower = "pmgwork.awake.onlyOnACPower"
        static let forcedCoolingDuration = "pmgwork.awake.forcedCoolingDuration"
        static let coolingMode = "pmgwork.awake.coolingMode"
        static let coolingArmed = "pmgwork.awake.coolingArmed"
        static let stopAtLowBattery = "pmgwork.awake.stopAtLowBattery"
        static let lowBatteryThreshold = "pmgwork.awake.lowBatteryThreshold"
        static let launchAtLogin = "pmgwork.awake.launchAtLogin"
        static let notificationsEnabled = "pmgwork.awake.notificationsEnabled"
        static let showTimerInMenuBar = "pmgwork.awake.showTimerInMenuBar"
        static let keepScreenOn = "pmgwork.awake.keepScreenOn"
        /// Merged into keepScreenOn; read once to migrate and left for older builds.
        static let legacyPreventDisplaySleep = "pmgwork.awake.preventDisplaySleep"
        static let legacyPreventScreenSaver = "pmgwork.awake.preventScreenSaver"
        static let closedDisplayModeEnabled = "pmgwork.awake.closedDisplayModeEnabled"
        static let lowPowerModeWhenLidClosed = "pmgwork.awake.lowPowerModeWhenLidClosed"
        static let providerLastTestedAt = "pmgwork.awake.providerLastTestedAt"
        static let hasCompletedOnboarding = "pmgwork.awake.hasCompletedOnboarding"
    }

    @Published public var monitoredAgents: [MonitoredAgent] {
        didSet {
            saveAgents()
        }
    }

    @Published public private(set) var providerLastTestedAt: [AgentProvider: Date] = [:]

    @Published public var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.preferenceKey)
        }
    }

    @Published public var selectedMode: KeepAwakeModeType {
        didSet {
            UserDefaults.standard.set(selectedMode.rawValue, forKey: Keys.selectedMode)
        }
    }

    @Published public var agentMonitoringEnabled: Bool {
        didSet {
            UserDefaults.standard.set(agentMonitoringEnabled, forKey: Keys.agentMonitoringEnabled)
        }
    }

    @Published public var downloadMonitoringEnabled: Bool {
        didSet {
            UserDefaults.standard.set(downloadMonitoringEnabled, forKey: Keys.downloadMonitoringEnabled)
        }
    }

    @Published public var downloadFolderPath: String {
        didSet {
            UserDefaults.standard.set(downloadFolderPath, forKey: Keys.downloadFolderPath)
        }
    }

    @Published public var completionGraceDuration: TimeInterval {
        didSet {
            UserDefaults.standard.set(completionGraceDuration, forKey: Keys.completionGraceDuration)
        }
    }

    /// Reuses the original preference key so earlier user choices survive.
    static func storedCompletionGraceDuration(in defaults: UserDefaults) -> TimeInterval {
        guard defaults.object(forKey: Keys.completionGraceDuration) != nil else { return 180 }
        let duration = defaults.double(forKey: Keys.completionGraceDuration)
        return duration.isFinite ? max(0, duration) : 180
    }

    @Published public var selectedTimerDuration: TimeInterval {
        didSet {
            UserDefaults.standard.set(selectedTimerDuration, forKey: Keys.selectedTimerDuration)
        }
    }

    @Published public var automaticCoolingFanMode: FanMode {
        didSet {
            UserDefaults.standard.set(automaticCoolingFanMode.rawValue, forKey: Keys.automaticCoolingFanMode)
        }
    }

    @Published public var manualCoolingFanMode: FanMode {
        didSet {
            UserDefaults.standard.set(manualCoolingFanMode.rawValue, forKey: Keys.manualCoolingFanMode)
        }
    }

    @Published public var onlyOnACPower: Bool {
        didSet {
            UserDefaults.standard.set(onlyOnACPower, forKey: Keys.onlyOnACPower)
        }
    }

    /// The selected cooling mode. Selecting it starts only conditional modes.
    @Published public var coolingMode: CoolingMode {
        didSet {
            UserDefaults.standard.set(coolingMode.rawValue, forKey: Keys.coolingMode)
        }
    }

    /// Whether cooling has been started for the selected mode.
    @Published public var coolingArmed: Bool {
        didSet {
            UserDefaults.standard.set(coolingArmed, forKey: Keys.coolingArmed)
        }
    }

    /// How long the timed cooling mode runs before returning to System.
    @Published public var forcedCoolingDuration: TimeInterval {
        didSet {
            UserDefaults.standard.set(forcedCoolingDuration, forKey: Keys.forcedCoolingDuration)
        }
    }

    /// Zero disables the battery cutoff.
    @Published public var lowBatteryThreshold: Int {
        didSet {
            UserDefaults.standard.set(lowBatteryThreshold, forKey: Keys.lowBatteryThreshold)
        }
    }

    @Published public var launchAtLogin: Bool {
        didSet {
            guard !isSynchronizingLaunchAtLogin else { return }
            UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin)
            if !updateLaunchAtLogin(enabled: launchAtLogin) {
                isSynchronizingLaunchAtLogin = true
                launchAtLogin = SMAppService.mainApp.status == .enabled
                UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin)
                isSynchronizingLaunchAtLogin = false
            }
        }
    }

    @Published public var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
            if notificationsEnabled {
                NotificationManager.shared.requestAuthorization()
            }
        }
    }

    @Published public var showTimerInMenuBar: Bool {
        didSet {
            UserDefaults.standard.set(showTimerInMenuBar, forKey: Keys.showTimerInMenuBar)
        }
    }

    /// Keeps the screen on and prevents the screen saver and automatic lock.
    @Published public var keepScreenOn: Bool {
        didSet {
            UserDefaults.standard.set(keepScreenOn, forKey: Keys.keepScreenOn)
        }
    }

    /// Opt-in to keeping the Mac running when the built-in display is closed.
    @Published public var closedDisplayModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(closedDisplayModeEnabled, forKey: Keys.closedDisplayModeEnabled)
        }
    }

    /// Turns on Low Power Mode while the lid is closed during a session.
    @Published public var lowPowerModeWhenLidClosed: Bool {
        didSet {
            UserDefaults.standard.set(lowPowerModeWhenLidClosed, forKey: Keys.lowPowerModeWhenLidClosed)
        }
    }

    @Published public var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        }
    }

    public static let forcedCoolingDurations: [TimeInterval] = [5 * 60, 10 * 60, 15 * 60, 30 * 60]

    private var isSynchronizingLaunchAtLogin = false

    static func storedCoolingFanModes(in defaults: UserDefaults, isExistingInstall: Bool) -> (automatic: FanMode, manual: FanMode) {
        func speed(for key: String) -> FanMode? {
            guard let raw = defaults.string(forKey: key),
                  let mode = FanMode(rawValue: raw), mode != .auto else { return nil }
            return mode
        }
        let previous = speed(for: Keys.coolingFanMode)
            ?? speed(for: Keys.legacyClosedLidFanMode)
            ?? (isExistingInstall ? .aggressive : .maximum)
        return (
            speed(for: Keys.automaticCoolingFanMode) ?? previous,
            speed(for: Keys.manualCoolingFanMode) ?? previous
        )
    }

    /// Earlier versions had separate display-sleep and screen-saver settings.
    /// Either one kept the screen on, so either one carries over.
    static func storedKeepScreenOn(in defaults: UserDefaults) -> Bool {
        if defaults.object(forKey: Keys.keepScreenOn) != nil {
            return defaults.bool(forKey: Keys.keepScreenOn)
        }
        let displaySleep = defaults.object(forKey: Keys.legacyPreventDisplaySleep) == nil
            ? false : defaults.bool(forKey: Keys.legacyPreventDisplaySleep)
        let screenSaver = defaults.object(forKey: Keys.legacyPreventScreenSaver) == nil
            ? true : defaults.bool(forKey: Keys.legacyPreventScreenSaver)
        return displaySleep || screenSaver
    }

    /// Reads the saved cooling mode and whether it is armed, migrating
    /// settings from earlier versions.
    static func storedCoolingState(in defaults: UserDefaults) -> (mode: CoolingMode, armed: Bool) {
        // Earlier automatic modes now follow Keep Awake; preserve their armed state.
        let savedCoolingRaw = defaults.string(forKey: Keys.coolingMode)
            .map { ["whileLidClosed", "whileAgentRunning"].contains($0) ? CoolingMode.whileKeepAwakeIsOn.rawValue : $0 }
        if let savedCoolingMode = savedCoolingRaw.flatMap(CoolingMode.init(rawValue:)) {
            return (savedCoolingMode, savedCoolingMode.survivesRelaunch
                && defaults.bool(forKey: Keys.coolingArmed))
        }
        if savedCoolingRaw != nil {
            // A mode that no longer exists, such as "system" (fans left to
            // macOS), which is now just a stopped mode.
            return (.whileKeepAwakeIsOn, false)
        }
        // Closed-lid cooling used to be a separate setting that was on by
        // default; carry it over as the "While Keep Awake Is On" mode,
        // which is also the default for new installs.
        let legacyEnabled = defaults.object(forKey: Keys.legacyClosedLidCoolingEnabled) == nil
            ? true : defaults.bool(forKey: Keys.legacyClosedLidCoolingEnabled)
        return (.whileKeepAwakeIsOn, legacyEnabled)
    }

    private init() {
        language = AppLanguage.stored()
        // Load agents or default presets
        if let data = UserDefaults.standard.data(forKey: Keys.monitoredAgents),
           let decoded = try? JSONDecoder().decode([MonitoredAgent].self, from: data),
           !decoded.isEmpty {
            let existingProviders = Set(decoded.compactMap(\.provider))
            let missingPresets = MonitoredAgent.defaultPresets.filter { preset in
                guard let provider = preset.provider else { return false }
                return !existingProviders.contains(provider)
            }
            let migratedAgents = decoded + missingPresets
            self.monitoredAgents = migratedAgents
            if let migratedData = try? JSONEncoder().encode(migratedAgents) {
                UserDefaults.standard.set(migratedData, forKey: Keys.monitoredAgents)
            }
        } else {
            self.monitoredAgents = MonitoredAgent.defaultPresets
        }

        // Read before any setting is written below, to tell new installs
        // from existing ones.
        let isExistingInstall = UserDefaults.standard.object(forKey: Keys.selectedMode) != nil
            || UserDefaults.standard.object(forKey: Keys.hasCompletedOnboarding) != nil
            || UserDefaults.standard.object(forKey: Keys.monitoredAgents) != nil

        // Mode (defaults to the agent mode, the main use of Awake)
        if let modeRaw = UserDefaults.standard.string(forKey: Keys.selectedMode),
           let mode = KeepAwakeModeType(rawValue: modeRaw) {
            self.selectedMode = mode
        } else {
            // Existing installs that never changed the mode keep the old default.
            self.selectedMode = isExistingInstall ? .indefinitely : .whileAgentRunning
        }

        if UserDefaults.standard.object(forKey: Keys.agentMonitoringEnabled) != nil {
            self.agentMonitoringEnabled = UserDefaults.standard.bool(forKey: Keys.agentMonitoringEnabled)
        } else {
            self.agentMonitoringEnabled = true
        }

        if UserDefaults.standard.object(forKey: Keys.downloadMonitoringEnabled) != nil {
            self.downloadMonitoringEnabled = UserDefaults.standard.bool(forKey: Keys.downloadMonitoringEnabled)
        } else {
            self.downloadMonitoringEnabled = true
        }
        self.downloadFolderPath = UserDefaults.standard.string(forKey: Keys.downloadFolderPath)
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!.path

        self.completionGraceDuration = Self.storedCompletionGraceDuration(in: .standard)

        // Timer Duration (default 30 minutes)
        let savedDuration = UserDefaults.standard.double(forKey: Keys.selectedTimerDuration)
        self.selectedTimerDuration = savedDuration > 0 ? savedDuration : 30 * 60

        // Cooling settings
        // Native clamshell now always leaves hardware control to macOS.
        // Retain the old excludeNormalClamshell preference on disk for older builds.

        let fanModes = Self.storedCoolingFanModes(in: .standard, isExistingInstall: isExistingInstall)
        self.automaticCoolingFanMode = fanModes.automatic
        self.manualCoolingFanMode = fanModes.manual
        UserDefaults.standard.set(fanModes.automatic.rawValue, forKey: Keys.automaticCoolingFanMode)
        UserDefaults.standard.set(fanModes.manual.rawValue, forKey: Keys.manualCoolingFanMode)

        self.onlyOnACPower = UserDefaults.standard.bool(forKey: Keys.onlyOnACPower)
        // Automatic cooling is limited to closed-lid operation. Preserve the former
        // agentCoolingRequiresLidClosed preference on disk for older builds.

        let cooling = Self.storedCoolingState(in: .standard)
        self.coolingMode = cooling.mode
        self.coolingArmed = cooling.armed
        UserDefaults.standard.set(cooling.mode.rawValue, forKey: Keys.coolingMode)
        UserDefaults.standard.set(cooling.armed, forKey: Keys.coolingArmed)
        let savedBoostDuration = UserDefaults.standard.double(forKey: Keys.forcedCoolingDuration)
        self.forcedCoolingDuration = Self.forcedCoolingDurations.contains(savedBoostDuration)
            ? savedBoostDuration : 10 * 60

        if UserDefaults.standard.object(forKey: Keys.lowBatteryThreshold) != nil {
            let threshold = UserDefaults.standard.integer(forKey: Keys.lowBatteryThreshold)
            self.lowBatteryThreshold = [0, 5, 10, 15, 20, 25].contains(threshold) ? threshold : 20
        } else if UserDefaults.standard.object(forKey: Keys.stopAtLowBattery) != nil {
            self.lowBatteryThreshold = UserDefaults.standard.bool(forKey: Keys.stopAtLowBattery) ? 20 : 0
        } else {
            self.lowBatteryThreshold = 20
        }


        if UserDefaults.standard.object(forKey: Keys.showTimerInMenuBar) != nil {
            self.showTimerInMenuBar = UserDefaults.standard.bool(forKey: Keys.showTimerInMenuBar)
        } else {
            self.showTimerInMenuBar = true
        }

        // Check SMAppService status for Launch at Login
        self.launchAtLogin = SMAppService.mainApp.status == .enabled

        self.notificationsEnabled = UserDefaults.standard.bool(forKey: Keys.notificationsEnabled)
        let keepScreenOn = Self.storedKeepScreenOn(in: .standard)
        self.keepScreenOn = keepScreenOn
        UserDefaults.standard.set(keepScreenOn, forKey: Keys.keepScreenOn)

        self.closedDisplayModeEnabled = UserDefaults.standard.object(forKey: Keys.closedDisplayModeEnabled) == nil
            ? true : UserDefaults.standard.bool(forKey: Keys.closedDisplayModeEnabled)
        self.lowPowerModeWhenLidClosed = UserDefaults.standard.bool(forKey: Keys.lowPowerModeWhenLidClosed)

        if let data = UserDefaults.standard.data(forKey: Keys.providerLastTestedAt),
           let decoded = try? JSONDecoder().decode([AgentProvider: Date].self, from: data) {
            self.providerLastTestedAt = decoded
        }

        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Keys.hasCompletedOnboarding)
    }

    private func saveAgents() {
        if let encoded = try? JSONEncoder().encode(monitoredAgents) {
            UserDefaults.standard.set(encoded, forKey: Keys.monitoredAgents)
        }
    }

    public func deleteAgent(id: String) {
        monitoredAgents.removeAll { $0.id == id }
    }

    public func enableAgent(for provider: AgentProvider) {
        if let index = monitoredAgents.firstIndex(where: { $0.provider == provider }),
           !monitoredAgents[index].isEnabled {
            monitoredAgents[index].isEnabled = true
        }
    }

    public func toggleAgent(id: String) {
        if let index = monitoredAgents.firstIndex(where: { $0.id == id }) {
            monitoredAgents[index].isEnabled.toggle()
        }
    }

    public func markProviderTested(_ provider: AgentProvider, at date: Date = Date()) {
        providerLastTestedAt[provider] = date
        saveProviderTestDates()
    }

    public func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    public func clearProviderTest(_ provider: AgentProvider) {
        providerLastTestedAt.removeValue(forKey: provider)
        saveProviderTestDates()
    }

    private func saveProviderTestDates() {
        if let data = try? JSONEncoder().encode(providerLastTestedAt) {
            UserDefaults.standard.set(data, forKey: Keys.providerLastTestedAt)
        }
    }

    public var enabledProviders: Set<AgentProvider> {
        Set(monitoredAgents.filter(\.isEnabled).compactMap(\.provider))
    }

    @discardableResult
    private func updateLaunchAtLogin(enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("[SettingsStore] Failed to update launch at login: %@", error.localizedDescription)
            return false
        }
    }
}
