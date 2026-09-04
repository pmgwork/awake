//
//  GeneralSettingsView.swift
//  Awake
//

import SwiftUI
import UserNotifications

struct GeneralSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var notificationManager: NotificationManager
    @ObservedObject var screenBehaviorManager: ScreenBehaviorManager

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("General Preferences")
                        .font(.headline)
                    Text("Configure startup and menu bar display settings.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    // Launch at Login
                    Toggle(isOn: $settings.launchAtLogin) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Launch Awake at Login")
                                .font(.system(size: 13, weight: .medium))
                            Text("Automatically start in the menu bar when logging in to your Mac.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)

                    Toggle(isOn: $settings.notificationsEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Notifications")
                                .font(.system(size: 13, weight: .medium))
                            Text("Notify when Keep Awake starts, stops, or when agents finish.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)

                    if settings.notificationsEnabled
                        && notificationManager.authorizationStatus == .denied
                    {
                        Text("Notifications are disabled in System Settings.")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                            .padding(.leading, 20)
                    }

                    // Show Timer in Menu Bar
                    Toggle(isOn: $settings.showTimerInMenuBar) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show Remaining Time in Menu Bar")
                                .font(.system(size: 13, weight: .medium))
                            Text(
                                "Displays the countdown next to the menu bar icon when Timer mode is active."
                            )
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)

                    Toggle(isOn: $settings.stopAtLowBattery) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Stop Awake at 20% Battery")
                                .font(.system(size: 13, weight: .medium))
                            Text(
                                "Turns off Awake in every mode and restores automatic fan control at 20% when unplugged."
                            )
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Display During Sessions")
                            .font(.headline)
                        Text(
                            "These preferences apply only while Awake is actively preventing system sleep."
                        )
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    }

                    Toggle(isOn: $settings.preventDisplaySleep) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Prevent Display Sleep")
                                .font(.system(size: 13, weight: .medium))
                            Text(
                                "Keeps connected displays on without waking a display that is already asleep."
                            )
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)

                    Toggle(isOn: $settings.preventScreenSaver) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Prevent Screen Saver & Automatic Lock")
                                .font(.system(size: 13, weight: .medium))
                            Text(
                                "Prevents the screen saver and automatic idle lock while Awake is active. Manual locking remains available."
                            )
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)

                    if let error = screenBehaviorManager.lastError {
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                            .padding(.leading, 20)
                    }
                }

                Divider()

                // System Sleep vs Display Sleep Explanation
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.accentColor)
                        Text("About Sleep & Screen Lock")
                            .font(.system(size: 12, weight: .semibold))
                    }

                    Text(
                        "By default, Awake keeps the system and display awake and prevents automatic idle locking. Disable both options above to restore normal display and locking behavior."
                    )
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color.accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Spacer()

                // Version info
                HStack {
                    Text(L10n.format("Awake v%@", appVersion))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .padding(20)
        }
        .onAppear {
            notificationManager.refreshAuthorizationStatus()
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
