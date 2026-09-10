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
        static let selectedTimerDuration = "pmgwork.awake.selectedTimerDuration"
        static let closedLidCoolingEnabled = "pmgwork.awake.closedLidCoolingEnabled"
        static let excludeNormalClamshell = "pmgwork.awake.excludeNormalClamshell"
        static let closedLidFanMode = "pmgwork.awake.closedLidFanMode"
        static let onlyOnACPower = "pmgwork.awake.onlyOnACPower"
        static let stopAtLowBattery = "pmgwork.awake.stopAtLowBattery"
        static let launchAtLogin = "pmgwork.awake.launchAtLogin"
        static let notificationsEnabled = "pmgwork.awake.notificationsEnabled"
        static let showTemperatureInMenuBar = "pmgwork.awake.showTemperatureInMenuBar"
        static let showTimerInMenuBar = "pmgwork.awake.showTimerInMenuBar"
        static let preventDisplaySleep = "pmgwork.awake.preventDisplaySleep"
        static let preventScreenSaver = "pmgwork.awake.preventScreenSaver"
        static let providerLastTestedAt = "pmgwork.awake.providerLastTestedAt"
        static let hasCompletedOnboarding = "pmgwork.awake.hasCompletedOnboarding"
        static let automaticallyCheckForUpdates = "pmgwork.awake.automaticallyCheckForUpdates"
        static let lastUpdateCheckAt = "pmgwork.awake.lastUpdateCheckAt"
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

    @Published public var selectedTimerDuration: TimeInterval {
        didSet {
            UserDefaults.standard.set(selectedTimerDuration, forKey: Keys.selectedTimerDuration)
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

    @Published public var stopAtLowBattery: Bool {
        didSet {
            UserDefaults.standard.set(stopAtLowBattery, forKey: Keys.stopAtLowBattery)
        }
    }

    @Published public var launchAtLogin: Bool {
        didSet {
            guard !isSynchronizingLaunchAtLogin else { return }
            UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin)
            if !updateLaunchAtLogin(enabled: launchAtLogin) {
                isSynchronizingLaunchAtLogin = true
                if #available(macOS 13.0, *) {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
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

    @Published public var automaticallyCheckForUpdates: Bool {
        didSet {
            UserDefaults.standard.set(automaticallyCheckForUpdates, forKey: Keys.automaticallyCheckForUpdates)
        }
    }

    @Published public private(set) var lastUpdateCheckAt: Date?

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

        // Mode
        if let modeRaw = UserDefaults.standard.string(forKey: Keys.selectedMode),
           let mode = KeepAwakeModeType(rawValue: modeRaw) {
            self.selectedMode = mode
        } else {
            self.selectedMode = .whileAgentRunning
        }

        // Timer Duration (default 2 hours)
        let savedDuration = UserDefaults.standard.double(forKey: Keys.selectedTimerDuration)
        self.selectedTimerDuration = savedDuration > 0 ? savedDuration : 2 * 60 * 60

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
            self.closedLidFanMode = .maximum
        }

        self.onlyOnACPower = UserDefaults.standard.bool(forKey: Keys.onlyOnACPower)

        if UserDefaults.standard.object(forKey: Keys.stopAtLowBattery) != nil {
            self.stopAtLowBattery = UserDefaults.standard.bool(forKey: Keys.stopAtLowBattery)
        } else {
            self.stopAtLowBattery = true
        }

        self.showTemperatureInMenuBar = UserDefaults.standard.bool(forKey: Keys.showTemperatureInMenuBar)

        if UserDefaults.standard.object(forKey: Keys.showTimerInMenuBar) != nil {
            self.showTimerInMenuBar = UserDefaults.standard.bool(forKey: Keys.showTimerInMenuBar)
        } else {
            self.showTimerInMenuBar = true
        }

        // Check SMAppService status for Launch at Login
        if #available(macOS 13.0, *) {
            self.launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            self.launchAtLogin = UserDefaults.standard.bool(forKey: Keys.launchAtLogin)
        }

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

        if UserDefaults.standard.object(forKey: Keys.automaticallyCheckForUpdates) != nil {
            self.automaticallyCheckForUpdates = UserDefaults.standard.bool(forKey: Keys.automaticallyCheckForUpdates)
        } else {
            self.automaticallyCheckForUpdates = true
        }

        self.lastUpdateCheckAt = UserDefaults.standard.object(forKey: Keys.lastUpdateCheckAt) as? Date
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
        closedLidCoolingEnabled = true
        excludeNormalClamshell = true
        closedLidFanMode = .maximum
        onlyOnACPower = false
        stopAtLowBattery = true
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

    public func recordUpdateCheck(at date: Date = Date()) {
        lastUpdateCheckAt = date
        UserDefaults.standard.set(date, forKey: Keys.lastUpdateCheckAt)
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
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
                return true
            } catch {
                NSLog("[SettingsStore] Failed to update launch at login: %@", error.localizedDescription)
                return false
            }
        }
        return true
    }
}
