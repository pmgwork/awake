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

            if coordinator.completionGraceEndDate != nil {
                Label(
                    coordinator.formattedGraceStatus,
                    systemImage: "hourglass"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            if settings.selectedMode == .whileAgentRunning {
                Divider()

                RunningAgentsView(
                    eventMonitor: coordinator.eventMonitor,
                    integrationManager: coordinator.hookIntegrationManager,
                    settings: settings
                )
            }

            if settings.selectedMode == .whileDownloading {
                Divider()

                DownloadStatusView(
                    monitor: coordinator.downloadMonitor,
                    settings: settings
                )
            }

            Divider()

            Button(action: {
                coordinator.togglePrimaryAction()
            }) {
                Label(
                    primaryActionTitle,
                    systemImage: primaryActionSystemImage
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(primaryActionTint)

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

    private var primaryActionTitle: String {
        if settings.selectedMode == .whileAgentRunning {
            return settings.agentMonitoringEnabled
                ? L10n.string("Pause Agent Monitoring")
                : L10n.string("Resume Agent Monitoring")
        }
        if settings.selectedMode == .whileDownloading {
            return settings.downloadMonitoringEnabled
                ? L10n.string("Pause Download Monitoring")
                : L10n.string("Resume Download Monitoring")
        }
        return coordinator.isActive ? L10n.string("Stop Keep Awake") : L10n.string("Start Keep Awake")
    }

    private var primaryActionSystemImage: String {
        if settings.selectedMode == .whileAgentRunning {
            return settings.agentMonitoringEnabled ? "pause.fill" : "play.fill"
        }
        if settings.selectedMode == .whileDownloading {
            return settings.downloadMonitoringEnabled ? "pause.fill" : "play.fill"
        }
        return coordinator.isActive ? "stop.fill" : "play.fill"
    }

    private var primaryActionTint: Color {
        if settings.selectedMode == .whileAgentRunning {
            return settings.agentMonitoringEnabled ? .orange : .accentColor
        }
        if settings.selectedMode == .whileDownloading {
            return settings.downloadMonitoringEnabled ? .orange : .accentColor
        }
        return coordinator.isActive ? .red : .accentColor
    }
}

private struct DownloadStatusView: View {
    @ObservedObject var monitor: DownloadMonitor
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.string("Downloads"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                if monitor.isDownloading {
                    Text(L10n.format("%d downloading", monitor.activeDownloadCount))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.green)
                }
            }

            if monitor.activeFileNames.isEmpty {
                Text(L10n.string("No active downloads."))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(monitor.activeFileNames.prefix(3).enumerated()), id: \.offset) { _, name in
                    Label(name, systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
            }

            Text(settings.downloadFolderPath)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
