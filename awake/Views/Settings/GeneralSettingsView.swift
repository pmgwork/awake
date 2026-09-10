import SwiftUI
import UserNotifications
import AppKit

struct GeneralSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var notificationManager: NotificationManager
    @ObservedObject var screenBehaviorManager: ScreenBehaviorManager
    @ObservedObject var updateService: AppUpdateService

    var body: some View {
        Form {
            Section {
                Toggle(L10n.string("Launch Awake at Login"), isOn: $settings.launchAtLogin)
                Toggle(L10n.string("Enable Notifications"), isOn: $settings.notificationsEnabled)
                if settings.notificationsEnabled && notificationManager.authorizationStatus == .denied {
                    Label(
                        L10n.string("Notifications are disabled in System Settings."),
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.secondary)
                }
                Toggle(L10n.string("Show Remaining Time in Menu Bar"), isOn: $settings.showTimerInMenuBar)
                Toggle(L10n.string("Stop Awake at 20% Battery"), isOn: $settings.stopAtLowBattery)
            } header: {
                Text(L10n.string("General Preferences"))
            }

            Section {
                Toggle(L10n.string("Prevent Display Sleep"), isOn: $settings.preventDisplaySleep)
                Toggle(
                    L10n.string("Prevent Screen Saver & Automatic Lock"),
                    isOn: $settings.preventScreenSaver
                )
                if let error = screenBehaviorManager.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            } header: {
                Text(L10n.string("Display During Sessions"))
            } footer: {
                Text(L10n.string("These preferences apply only while Awake is actively preventing system sleep."))
            }

            Section {
                LabeledContent {
                    HStack {
                        Text(settings.downloadFolderPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button(L10n.string("Choose...")) {
                            chooseDownloadFolder()
                        }
                    }
                } label: {
                    Text(L10n.string("Monitored Folder"))
                }
            } header: {
                Text(L10n.string("Download Monitoring"))
            } footer: {
                Text(L10n.string("Awake detects unfinished Chrome, Safari, Firefox, Edge, Brave, and Opera downloads in this folder."))
            }

            Section {
                Toggle(
                    L10n.string("Automatically check for updates"),
                    isOn: $settings.automaticallyCheckForUpdates
                )

                LabeledContent {
                    HStack {
                        updateStatusView
                        Button(L10n.string("Check Now")) {
                            updateService.checkForUpdates(userInitiated: true)
                        }
                        .disabled(updateService.state == .checking)
                    }
                } label: {
                    Text(L10n.string("Software Updates"))
                }

                if case .available(_, let release) = updateService.state {
                    LabeledContent {
                        Button(L10n.string("Download...")) {
                            updateService.openRelease(release)
                        }
                    } label: {
                        Text(L10n.format("Awake %@", release.version))
                    }
                }
            } footer: {
                Text(L10n.string("Checks GitHub Releases on launch. No account or signing required."))
            }

            Section {
                LabeledContent(L10n.string("Version"), value: appVersion)
                Button(L10n.string("Show Welcome Guide...")) {
                    OnboardingWindowController.shared.showOnboarding(coordinator: AwakeCoordinator.shared)
                }
                Button(L10n.string("View All Releases")) {
                    updateService.openReleasesPage()
                }
            } header: {
                Text(L10n.string("About"))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            notificationManager.refreshAuthorizationStatus()
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private func chooseDownloadFolder() {
        let panel = NSOpenPanel()
        panel.title = L10n.string("Choose Download Folder")
        panel.prompt = L10n.string("Choose")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: settings.downloadFolderPath, isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url {
            settings.downloadFolderPath = url.path
        }
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateService.state {
        case .idle:
            if let lastChecked = settings.lastUpdateCheckAt {
                Text(L10n.format("Last checked %@", lastChecked.formatted(date: .abbreviated, time: .shortened)))
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.string("Not Checked"))
                    .foregroundStyle(.secondary)
            }
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .upToDate:
            Label(L10n.string("Up to Date"), systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .available(_, let release):
            Label(L10n.format("Version %@ Available", release.version), systemImage: "arrow.down.circle")
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }
}
