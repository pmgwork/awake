//
//  SettingsView.swift
//  Awake
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var coordinator: AwakeCoordinator

    var body: some View {
        TabView {
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

            AgentSettingsView(
                settings: coordinator.settings,
                eventMonitor: coordinator.eventMonitor,
                integrationManager: coordinator.hookIntegrationManager
            )
            .tabItem {
                Label(L10n.string("Agents"), systemImage: "cpu")
            }

            CoolingSettingsView(
                settings: coordinator.settings,
                fanController: coordinator.fanController,
                thermalMonitor: coordinator.thermalMonitor
            )
            .tabItem {
                Label(L10n.string("Cooling"), systemImage: "wind")
            }
        }
        .frame(width: 540)
        .frame(maxHeight: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
