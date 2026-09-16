//
//  SettingsStore.swift
//  Awake
//

import Foundation
import Combine
import SwiftUI
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
        static let selectedTimerDuration = "pmgwork.awake.selectedTimerDuration"
        static let completionGraceDuration = "pmgwork.awake.completionGraceDuration"
        static let closedLidCoolingEnabled = "pmgwork.awake.closedLidCoolingEnabled"
        static let excludeNormalClamshell = "pmgwork.awake.excludeNormalClamshell"
        static let closedLidFanMode = "pmgwork.awake.closedLidFanMode"
        static let onlyOnACPower = "pmgwork.awake.onlyOnACPower"
        static let stopAtLowBattery = "pmgwork.awake.stopAtLowBattery"
        static let lowBatteryThreshold = "pmgwork.awake.lowBatteryThreshold"
        static let launchAtLogin = "pmgwork.awake.launchAtLogin"
        static let notificationsEnabled = "pmgwork.awake.notificationsEnabled"
        static let showTemperatureInMenuBar = "pmgwork.awake.showTemperatureInMenuBar"
        static let showTimerInMenuBar = "pmgwork.awake.showTimerInMenuBar"
        static let preventDisplaySleep = "pmgwork.awake.preventDisplaySleep"
        static let preventScreenSaver = "pmgwork.awake.preventScreenSaver"
        static let providerLastTestedAt = "pmgwork.awake.providerLastTestedAt"
        static let hasCompletedOnboarding = "pmgwork.awake.hasCompletedOnboarding"
    }

    @Published public var monitoredAgents: [MonitoredAgent] {
        didSet {
            saveAgents()
        }
    }

    @Published public private(set) var providerLastTestedAt: [AgentProvider: Date] = [:]

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

    @Published public var selectedTimerDuration: TimeInterval {
        didSet {
            UserDefaults.standard.set(selectedTimerDuration, forKey: Keys.selectedTimerDuration)
        }
    }

    @Published public var completionGraceDuration: TimeInterval {
        didSet {
            UserDefaults.standard.set(completionGraceDuration, forKey: Keys.completionGraceDuration)
        }
    }

    @Published public var closedLidCoolingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(closedLidCoolingEnabled, forKey: Keys.closedLidCoolingEnabled)
        }
    }

    @Published public var excludeNormalClamshell: Bool {
        didSet {
            UserDefaults.standard.set(excludeNormalClamshell, forKey: Keys.excludeNormalClamshell)
        }
    }

    @Published public var closedLidFanMode: FanMode {
        didSet {
            UserDefaults.standard.set(closedLidFanMode.rawValue, forKey: Keys.closedLidFanMode)
        }
    }

    @Published public var onlyOnACPower: Bool {
        didSet {
            UserDefaults.standard.set(onlyOnACPower, forKey: Keys.onlyOnACPower)
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

    @Published public var showTemperatureInMenuBar: Bool {
        didSet {
            UserDefaults.standard.set(showTemperatureInMenuBar, forKey: Keys.showTemperatureInMenuBar)
        }
    }

    @Published public var showTimerInMenuBar: Bool {
        didSet {
            UserDefaults.standard.set(showTimerInMenuBar, forKey: Keys.showTimerInMenuBar)
        }
    }

    @Published public var preventDisplaySleep: Bool {
        didSet {
            UserDefaults.standard.set(preventDisplaySleep, forKey: Keys.preventDisplaySleep)
        }
    }

    @Published public var preventScreenSaver: Bool {
        didSet {
            UserDefaults.standard.set(preventScreenSaver, forKey: Keys.preventScreenSaver)
        }
    }

    @Published public var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        }
    }

    private var isSynchronizingLaunchAtLogin = false

    private init() {
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

        // Mode (defaults to Indefinitely until the user picks another mode)
        if let modeRaw = UserDefaults.standard.string(forKey: Keys.selectedMode),
           let mode = KeepAwakeModeType(rawValue: modeRaw) {
            self.selectedMode = mode
        } else {
            self.selectedMode = .indefinitely
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

        // Timer Duration (default 30 minutes) and completion grace (default 1 minute)
        let savedDuration = UserDefaults.standard.double(forKey: Keys.selectedTimerDuration)
        self.selectedTimerDuration = savedDuration > 0 ? savedDuration : 30 * 60
        self.completionGraceDuration = UserDefaults.standard.object(forKey: Keys.completionGraceDuration) == nil
            ? 60 : max(0, UserDefaults.standard.double(forKey: Keys.completionGraceDuration))

        // Cooling settings
        if UserDefaults.standard.object(forKey: Keys.closedLidCoolingEnabled) != nil {
            self.closedLidCoolingEnabled = UserDefaults.standard.bool(forKey: Keys.closedLidCoolingEnabled)
        } else {
            self.closedLidCoolingEnabled = true
        }

        if UserDefaults.standard.object(forKey: Keys.excludeNormalClamshell) != nil {
            self.excludeNormalClamshell = UserDefaults.standard.bool(forKey: Keys.excludeNormalClamshell)
        } else {
            self.excludeNormalClamshell = true
        }

        if let fanRaw = UserDefaults.standard.string(forKey: Keys.closedLidFanMode),
           let fan = FanMode(rawValue: fanRaw) {
            self.closedLidFanMode = fan
        } else {
            self.closedLidFanMode = .aggressive
        }

        self.onlyOnACPower = UserDefaults.standard.bool(forKey: Keys.onlyOnACPower)

        if UserDefaults.standard.object(forKey: Keys.lowBatteryThreshold) != nil {
            let threshold = UserDefaults.standard.integer(forKey: Keys.lowBatteryThreshold)
            self.lowBatteryThreshold = [0, 5, 10, 15, 20, 25].contains(threshold) ? threshold : 20
        } else if UserDefaults.standard.object(forKey: Keys.stopAtLowBattery) != nil {
            self.lowBatteryThreshold = UserDefaults.standard.bool(forKey: Keys.stopAtLowBattery) ? 20 : 0
        } else {
            self.lowBatteryThreshold = 20
        }

        self.showTemperatureInMenuBar = UserDefaults.standard.bool(forKey: Keys.showTemperatureInMenuBar)

        if UserDefaults.standard.object(forKey: Keys.showTimerInMenuBar) != nil {
            self.showTimerInMenuBar = UserDefaults.standard.bool(forKey: Keys.showTimerInMenuBar)
        } else {
            self.showTimerInMenuBar = true
        }

        // Check SMAppService status for Launch at Login
        self.launchAtLogin = SMAppService.mainApp.status == .enabled

        self.notificationsEnabled = UserDefaults.standard.bool(forKey: Keys.notificationsEnabled)
        if UserDefaults.standard.object(forKey: Keys.preventDisplaySleep) != nil {
            self.preventDisplaySleep = UserDefaults.standard.bool(forKey: Keys.preventDisplaySleep)
        } else {
            self.preventDisplaySleep = true
        }

        if UserDefaults.standard.object(forKey: Keys.preventScreenSaver) != nil {
            self.preventScreenSaver = UserDefaults.standard.bool(forKey: Keys.preventScreenSaver)
        } else {
            self.preventScreenSaver = true
        }

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

    public func addCustomAgent(name: String, processNames: [String]) {
        let cleanedNames = processNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !name.isEmpty, !cleanedNames.isEmpty else { return }

        let newAgent = MonitoredAgent(
            name: name,
            processNames: cleanedNames,
            isEnabled: true,
            isPreset: false
        )
        monitoredAgents.append(newAgent)
    }

    public func removeAgent(at indexSet: IndexSet) {
        monitoredAgents.remove(atOffsets: indexSet)
    }

    public func deleteAgent(id: String) {
        monitoredAgents.removeAll { $0.id == id }
    }

    public func toggleAgent(id: String) {
        if let index = monitoredAgents.firstIndex(where: { $0.id == id }) {
            monitoredAgents[index].isEnabled.toggle()
        }
    }

    public func resetToDefaults() {
        monitoredAgents = MonitoredAgent.defaultPresets
        agentMonitoringEnabled = true
        downloadMonitoringEnabled = true
        completionGraceDuration = 60
        downloadFolderPath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!.path
        closedLidCoolingEnabled = true
        excludeNormalClamshell = true
        closedLidFanMode = .aggressive
        onlyOnACPower = false
        lowBatteryThreshold = 20
        preventDisplaySleep = true
        preventScreenSaver = true
    }

    public func markProviderTested(_ provider: AgentProvider, at date: Date = Date()) {
        providerLastTestedAt[provider] = date
        saveProviderTestDates()
    }

    public func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    public func resetOnboardingForTesting() {
        hasCompletedOnboarding = false
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
