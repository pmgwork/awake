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

            // Primary Toggle Action Button
            Button(action: {
                coordinator.toggleKeepAwake()
            }) {
                HStack {
                    Spacer()
                    Image(systemName: coordinator.isActive ? "stop.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(coordinator.isActive
                         ? L10n.string("Stop Keep Awake")
                         : L10n.string("Start Keep Awake"))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
                .padding(.vertical, 8)
                .background(coordinator.isActive ? Color.red.opacity(0.85) : Color.accentColor)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

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
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Text(L10n.string("Quit"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(12)
        .frame(width: 280)
    }
}
