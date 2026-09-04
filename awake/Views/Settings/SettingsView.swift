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
                screenBehaviorManager: coordinator.screenBehaviorManager
            )
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            AgentSettingsView(
                settings: coordinator.settings,
                processMonitor: coordinator.processMonitor
            )
            .tabItem {
                Label("Agents", systemImage: "cpu")
            }

            CoolingSettingsView(
                settings: coordinator.settings,
                fanController: coordinator.fanController,
                thermalMonitor: coordinator.thermalMonitor
            )
            .tabItem {
                Label("Cooling", systemImage: "wind")
            }
        }
        .frame(minWidth: 480, idealWidth: 500, minHeight: 480, idealHeight: 550)
    }
}
