//
//  MenuBarView.swift
//  Awake
//

import SwiftUI

struct MenuBarView: View {
    @ObservedObject var coordinator: AwakeCoordinator
    @ObservedObject var settings: SettingsStore
    var openSettingsAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ModeSelectorView(
                coordinator: coordinator,
                settings: settings
            )

            Divider()
            HardwareStatusView(
                lidMonitor: coordinator.lidMonitor,
                displayMonitor: coordinator.displayMonitor,
                powerMonitor: coordinator.powerMonitor,
                thermalMonitor: coordinator.thermalMonitor,
                fanController: coordinator.fanController,
                sleepManager: coordinator.sleepManager
            )

            if settings.selectedMode == .whileAgentRunning {
                Divider()

                RunningAgentsView(
                    eventMonitor: coordinator.eventMonitor,
                    integrationManager: coordinator.hookIntegrationManager,
                    settings: settings
                )
            }

            Divider()

            Button(action: {
                coordinator.toggleKeepAwake()
            }) {
                Label(
                    coordinator.isActive ? L10n.string("Stop Keep Awake") : L10n.string("Start Keep Awake"),
                    systemImage: coordinator.isActive ? "stop.fill" : "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(coordinator.isActive ? .red : .accentColor)

            // Bottom Footer
            HStack {
                Button(action: openSettingsAction) {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                        Text(L10n.string("Settings..."))
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)

                Spacer()

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Text(L10n.string("Quit"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.top, 2)
        }
        .padding(12)
        .frame(width: 280)
    }
}
