//
//  SettingsView.swift
//  Awake
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var coordinator: AwakeCoordinator
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView(
                settings: coordinator.settings,
                notificationManager: NotificationManager.shared,
                screenBehaviorManager: coordinator.screenBehaviorManager,
                updater: AppUpdater.shared,
                shortcutManager: coordinator.shortcutManager
            )
            .tabItem {
                Label(L10n.string("General"), systemImage: "gearshape")
            }
            .tag(SettingsTab.general)

            AgentSettingsView(
                settings: coordinator.settings,
                eventMonitor: coordinator.eventMonitor,
                integrationManager: coordinator.hookIntegrationManager
            )
            .tabItem {
                Label(L10n.string("Agents"), systemImage: "cpu")
            }
            .tag(SettingsTab.agents)

            CoolingSettingsView(
                settings: coordinator.settings,
                fanController: coordinator.fanController,
                thermalMonitor: coordinator.thermalMonitor
            )
            .tabItem {
                Label(L10n.string("Cooling"), systemImage: "wind")
            }
            .tag(SettingsTab.cooling)
        }
        .frame(width: 540)
        .frame(height: selectedTab.preferredHeight)
        .contentSizedVerticalScrolling()
    }
}

private enum SettingsTab: Hashable {
    case general
    case agents
    case cooling

    var preferredHeight: CGFloat {
        switch self {
        case .general, .cooling:
            return 540
        case .agents:
            return 500
        }
    }
}

private extension View {
    @ViewBuilder
    func contentSizedVerticalScrolling() -> some View {
        if #available(macOS 13.3, *) {
            scrollBounceBehavior(.basedOnSize, axes: .vertical)
        } else {
            self
        }
    }
}
