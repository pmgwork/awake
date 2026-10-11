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
                        L10n.string("Notifications are turned off in System Settings."),
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.red)
                }
                Toggle(L10n.string("Show Remaining Time in Menu Bar"), isOn: $settings.showTimerInMenuBar)
                Picker(L10n.string("Language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
            } header: {
                Text(L10n.string("General Preferences"))
            }

            Section {
                Toggle(
                    L10n.string("Receive Beta Updates"),
                    isOn: Binding(
                        get: { updater.receivesBetaUpdates },
                        set: { updater.setReceivesBetaUpdates($0) }
                    )
                )
                .disabled(updater.isUpdateInProgress)
                Text(L10n.string("Include beta releases when checking for updates. Turn this off to receive only stable releases; your installed version will not be downgraded."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(
                    L10n.string("Check for Updates Automatically"),
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
            }

            Section {
                LabeledContent(L10n.string("Version"), value: appVersion)
                Button(L10n.string("Show Welcome Guide…")) {
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
            Text(L10n.format("Last checked %@", lastChecked.formatted(
                Date.FormatStyle(date: .abbreviated, time: .shortened).locale(settings.language.locale)
            )))
        } else {
            Text(L10n.string("Not Checked"))
        }
    }
}
