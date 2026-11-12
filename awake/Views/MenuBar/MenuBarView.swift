//
//  MenuBarView.swift
//  Awake
//

import SwiftUI

struct MenuBarView: View {
    @ObservedObject var coordinator: AwakeCoordinator
    @ObservedObject var settings: SettingsStore
    var popoverCloseAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ModeSelectorView(
                coordinator: coordinator,
                settings: settings
            )

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
            .tint(.orange)

            if coordinator.isFanHelperInstalled && !coordinator.isRemovingHardwareAuthorization {
                Divider()

                CoolingModeSelectorView(
                    coordinator: coordinator,
                    settings: settings
                )

                coolingActionButton

                if coordinator.isCoolingBlockedByLowBattery {
                    Text(L10n.string("Automatic cooling is unavailable while the battery is low."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if coordinator.isFanHelperOutdated && !coordinator.isRemovingHardwareAuthorization {
                Divider()

                helperUpdateNotice
            }

            if settings.agentMonitoringEnabled && coordinator.isAgentKeepAwakeActive {
                Divider()

                RunningAgentsView(
                    eventMonitor: coordinator.eventMonitor,
                    integrationManager: coordinator.hookIntegrationManager,
                    settings: settings
                )
            }

            if settings.downloadMonitoringEnabled && coordinator.isDownloadKeepAwakeActive {
                Divider()

                DownloadStatusView(
                    monitor: coordinator.downloadMonitor,
                    settings: settings
                )
            }

            Divider()

            // Bottom Footer
            HStack {
                settingsButton

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

    private var settingsLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "gearshape")
            Text(L10n.string("Settings…"))
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var settingsButton: some View {
        Button {
            popoverCloseAction()
            SettingsWindowController.shared.show()
        } label: {
            settingsLabel
        }
        .buttonStyle(.borderless)
    }

    /// Shown after an update that changed the helper, until it is reinstalled.
    private var helperUpdateNotice: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(L10n.string("Update the hardware helper in Permissions to use cooling and closed-lid operation."),
                  systemImage: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(L10n.string("Open Permissions")) {
                popoverCloseAction()
                SettingsWindowController.shared.show(tab: .permissions)
            }
            .buttonStyle(.link)
            .font(.system(size: 11))
        }
    }

    @ViewBuilder
    private var coolingActionButton: some View {
        Button(action: {
            coordinator.toggleCooling()
        }) {
            Label(coolingActionTitle, systemImage: coolingActionSystemImage)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.blue)
        .disabled(!coordinator.canUseForcedCooling && !settings.coolingArmed)
    }

    private var coolingActionTitle: String {
        settings.coolingArmed ? L10n.string("Stop Cooling") : L10n.string("Start Cooling")
    }

    private var coolingActionSystemImage: String {
        settings.coolingArmed ? "stop.fill" : "fanblades.fill"
    }

    private var primaryActionTitle: String {
        coordinator.isManualKeepAwakeActive ? L10n.string("Stop Keep Awake") : L10n.string("Start Keep Awake")
    }

    private var primaryActionSystemImage: String {
        coordinator.isManualKeepAwakeActive ? "stop.fill" : "play.fill"
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
                Text(L10n.string("No downloads in progress."))
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
