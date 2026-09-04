//
//  GeneralSettingsView.swift
//  Awake
//

import SwiftUI
import UserNotifications

struct GeneralSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var notificationManager: NotificationManager

    var body: some View {
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

                if settings.notificationsEnabled && notificationManager.authorizationStatus == .denied {
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
                        Text("Displays the countdown next to the menu bar icon when Timer mode is active.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: $settings.stopAtLowBattery) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stop Awake at 20% Battery")
                            .font(.system(size: 13, weight: .medium))
                        Text("Turns off Awake in every mode and restores automatic fan control at 20% when unplugged.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
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

                Text("Awake only prevents system sleep. Screen lock, display sleep, and screensavers remain permitted so your Mac stays secure and energy-efficient.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer()

            // Version info
            HStack {
                Text("Awake v1.0.0")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(20)
        .onAppear {
            notificationManager.refreshAuthorizationStatus()
        }
    }
}
