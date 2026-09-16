import SwiftUI
import UserNotifications
import AppKit

struct GeneralSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var notificationManager: NotificationManager
    @ObservedObject var updater: AppUpdater

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
                Picker(L10n.string("Battery Cutoff When Unplugged"), selection: $settings.lowBatteryThreshold) {
                    Text(L10n.string("Off")).tag(0)
                    ForEach([5, 10, 15, 20, 25], id: \.self) { threshold in
                        Text("\(threshold)%").tag(threshold)
                    }
                }
            } header: {
                Text(L10n.string("General Preferences"))
            }

            Section {
                Toggle(
                    L10n.string("Automatically check for updates"),
                    isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.setAutomaticallyChecksForUpdates($0) }
                    )
                )

                LabeledContent {
                    Button(L10n.string("Check Now")) {
                        updater.checkForUpdates()
                    }
                    .disabled(!updater.canCheckForUpdates)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.string("Check for Updates"))
                        lastCheckedText
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(L10n.string("Software Updates"))
            } footer: {
                Text(L10n.string("Updates are downloaded and installed inside Awake."))
            }

            Section {
                LabeledContent(L10n.string("Version"), value: appVersion)
                Button(L10n.string("Show Welcome Guide...")) {
                    OnboardingWindowController.shared.showOnboarding(coordinator: AwakeCoordinator.shared)
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

    @ViewBuilder
    private var lastCheckedText: some View {
        if let lastChecked = updater.lastUpdateCheckDate {
            Text(L10n.format("Last checked %@", lastChecked.formatted(date: .abbreviated, time: .shortened)))
        } else {
            Text(L10n.string("Not Checked"))
        }
    }
}
