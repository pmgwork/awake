//
//  SettingsView.swift
//  Awake
//

import SwiftUI
import Combine
import AppKit

/// The panes of the settings window, shown as a preference-style toolbar.
public enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case agents
    case cooling

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return L10n.string("General")
        case .agents: return L10n.string("Agents")
        case .cooling: return L10n.string("Cooling")
        }
    }

    public var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .agents: return "cpu"
        case .cooling: return "wind"
        }
    }

    var toolbarIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("settings.tab.\(rawValue)")
    }

    init?(toolbarIdentifier: NSToolbarItem.Identifier) {
        guard let tab = SettingsTab.allCases.first(where: { $0.toolbarIdentifier == toolbarIdentifier }) else {
            return nil
        }
        self = tab
    }
}

/// Observable selection shared between the window's toolbar and its content.
@MainActor
public final class SettingsTabSelection: ObservableObject {
    @Published public var tab: SettingsTab = .general

    public init() {}
}

struct SettingsView: View {
    @ObservedObject var coordinator: AwakeCoordinator
    @ObservedObject var selection: SettingsTabSelection

    var body: some View {
        Group {
            switch selection.tab {
            case .general:
                GeneralSettingsView(
                    settings: coordinator.settings,
                    notificationManager: NotificationManager.shared,
                    screenBehaviorManager: coordinator.screenBehaviorManager,
                    updater: AppUpdater.shared,
                    shortcutManager: coordinator.shortcutManager
                )
            case .agents:
                AgentSettingsView(
                    settings: coordinator.settings,
                    eventMonitor: coordinator.eventMonitor,
                    integrationManager: coordinator.hookIntegrationManager
                )
            case .cooling:
                CoolingSettingsView(
                    settings: coordinator.settings,
                    fanController: coordinator.fanController,
                    thermalMonitor: coordinator.thermalMonitor
                )
            }
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 520, idealHeight: 600)
    }
}
