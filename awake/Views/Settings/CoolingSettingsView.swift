//
//  CoolingSettingsView.swift
//  Awake
//

import SwiftUI

struct CoolingSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var fanController: FanController
    @ObservedObject var thermalMonitor: ThermalMonitor

    @State private var isInstallingHelper = false
    @State private var isHelperInstalled = SMCHelper.shared.checkHelperInstalled()
    @State private var isHelperPresent = SMCHelper.shared.isHelperToolPresent()
    @State private var helperStatusText: String = ""

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Closed-Lid Cooling & Thermal Management")
                        .font(.headline)
                    Text("Controls fan speed when MacBook lid is closed during unattended AI Agent workloads.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    // Closed Lid Cooling Toggle
                    Toggle(isOn: $settings.closedLidCoolingEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Closed-Lid Cooling")
                                .font(.system(size: 13, weight: .medium))
                            Text("Spins up fans to prevent heat accumulation when the lid is closed.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)

                    // Exclude Normal Clamshell Toggle
                    Toggle(isOn: $settings.excludeNormalClamshell) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Exclude Normal Clamshell (Recommended)")
                                .font(.system(size: 13, weight: .medium))
                            Text("Do not intervene when an external display is connected (leaves control to macOS).")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(!settings.closedLidCoolingEnabled)

                    // Fan Mode Picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Closed-Lid Fan Mode:")
                            .font(.system(size: 12, weight: .medium))

                        Picker("", selection: $settings.closedLidFanMode) {
                            ForEach(FanMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .disabled(!settings.closedLidCoolingEnabled)
                    }
                    .padding(.leading, 20)

                    // AC Power Only Toggle
                    Toggle(isOn: $settings.onlyOnACPower) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Closed-Lid Cooling only on AC Power")
                                .font(.system(size: 13, weight: .medium))
                            Text("Avoids heavy battery drain by only activating Closed-Lid Cooling when plugged in.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(!settings.closedLidCoolingEnabled)

                }

                Divider()

                // Helper Authorization Section
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: isHelperInstalled ? "checkmark.seal.fill" : "lock.shield")
                            .foregroundColor(isHelperInstalled ? .green : .orange)
                        Text(isHelperInstalled
                             ? L10n.string("Fan Control Access Authorized")
                             : L10n.string("Fan Control Authorization Required"))
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Button(helperButtonTitle) {
                            isInstallingHelper = true
                            SMCHelper.shared.installHelperTool { success in
                                isInstallingHelper = false
                                isHelperInstalled = success && SMCHelper.shared.checkHelperInstalled()
                                isHelperPresent = SMCHelper.shared.isHelperToolPresent()
                                helperStatusText = isHelperInstalled
                                    ? L10n.string("Helper update successful!")
                                    : L10n.string("Helper update cancelled or failed.")
                                if isHelperInstalled {
                                    fanController.allowPolicyRetry()
                                }
                            }
                        }
                        .font(.system(size: 11))
                        .disabled(isInstallingHelper)
                    }

                    if !isHelperInstalled {
                        Text(isHelperPresent
                             ? L10n.string("A newer helper is required for this Mac and battery closed-lid operation.")
                             : L10n.string("macOS requires administrator permission once to control hardware fans on Apple Silicon."))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    if !helperStatusText.isEmpty {
                        Text(helperStatusText)
                            .font(.system(size: 10))
                            .foregroundColor(isHelperInstalled ? .green : .red)
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Live Fan Diagnostics & Manual Test
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Fan Speed Diagnostics & Test")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text(fanController.currentStatus.formattedRPM)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(fanController.currentStatus.isOverridden ? .orange : .primary)
                    }

                    HStack(spacing: 8) {
                        Button("Test 100% Spin") {
                            fanController.testFanSpeed(mode: .maximum)
                        }
                        .font(.system(size: 11))

                        Button("Test 75% Spin") {
                            fanController.testFanSpeed(mode: .aggressive)
                        }
                        .font(.system(size: 11))

                        Button("Restore Auto") {
                            fanController.testFanSpeed(mode: .auto)
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    }

                    if fanController.isTestModeActive {
                        Text("Fan test ends after 60 seconds and returns to the current cooling policy.")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }

                    if let error = fanController.controlError {
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(20)
        }
        .onAppear {
            isHelperInstalled = SMCHelper.shared.checkHelperInstalled()
            isHelperPresent = SMCHelper.shared.isHelperToolPresent()
            fanController.refreshFanStatus()
        }
    }

    private var helperButtonTitle: String {
        if isInstallingHelper { return L10n.string("Updating...") }
        if isHelperInstalled { return L10n.string("Reinstall Helper...") }
        return isHelperPresent ? L10n.string("Update Helper...") : L10n.string("Install Helper...")
    }
}
