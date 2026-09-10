import SwiftUI

struct CoolingSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var fanController: FanController
    @ObservedObject var thermalMonitor: ThermalMonitor

    @State private var isInstallingHelper = false
    @State private var isHelperInstalled = SMCHelper.shared.checkHelperInstalled()
    @State private var isHelperPresent = SMCHelper.shared.isHelperToolPresent()
    @State private var helperStatusText = ""

    var body: some View {
        Form {
            Section {
                Toggle(L10n.string("Enable Closed-Lid Cooling"), isOn: $settings.closedLidCoolingEnabled)
                Toggle(
                    L10n.string("Exclude Normal Clamshell (Recommended)"),
                    isOn: $settings.excludeNormalClamshell
                )
                .disabled(!settings.closedLidCoolingEnabled)
                Toggle(
                    L10n.string("Closed-Lid Cooling only on AC Power"),
                    isOn: $settings.onlyOnACPower
                )
                .disabled(!settings.closedLidCoolingEnabled)

                Picker(L10n.string("Closed-Lid Fan Mode:"), selection: $settings.closedLidFanMode) {
                    ForEach(FanMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .disabled(!settings.closedLidCoolingEnabled)
            } header: {
                Text(L10n.string("Closed-Lid Cooling & Thermal Management"))
            } footer: {
                Text(L10n.string("Controls fan speed when MacBook lid is closed during unattended AI Agent workloads."))
            }

            Section {
                LabeledContent {
                    Label(
                        isHelperInstalled
                            ? L10n.string("Fan Control Access Authorized")
                            : L10n.string("Fan Control Authorization Required"),
                        systemImage: isHelperInstalled ? "checkmark.circle" : "lock.shield"
                    )
                    .foregroundStyle(isHelperInstalled ? .green : .secondary)
                } label: {
                    Text(L10n.string("Status"))
                }

                Button(helperButtonTitle) {
                    installHelper()
                }
                .disabled(isInstallingHelper)

                if isInstallingHelper {
                    ProgressView()
                        .controlSize(.small)
                }

                if !isHelperInstalled {
                    Text(isHelperPresent
                         ? L10n.string("A newer helper is required for this Mac and battery closed-lid operation.")
                         : L10n.string("macOS requires administrator permission once to control hardware fans on Apple Silicon."))
                        .foregroundStyle(.secondary)
                }

                if !helperStatusText.isEmpty {
                    Text(helperStatusText)
                        .foregroundStyle(isHelperInstalled ? .green : .red)
                }
            } header: {
                Text(L10n.string("Fan Control Helper"))
            }

            Section {
                LabeledContent(
                    L10n.string("Fan"),
                    value: fanController.currentStatus.formattedRPM
                )
                LabeledContent(
                    L10n.string("Temperature"),
                    value: thermalMonitor.thermalReading.formattedTemperature
                )

                HStack {
                    Button(L10n.string("Test 100% Spin")) {
                        fanController.testFanSpeed(mode: .maximum)
                    }
                    Button(L10n.string("Test 75% Spin")) {
                        fanController.testFanSpeed(mode: .aggressive)
                    }
                    Button(L10n.string("Restore Auto")) {
                        fanController.testFanSpeed(mode: .auto)
                    }
                }

                if fanController.isTestModeActive {
                    Label(
                        L10n.string("Fan test ends after 60 seconds and returns to the current cooling policy."),
                        systemImage: "timer"
                    )
                    .foregroundStyle(.secondary)
                }

                if let error = fanController.controlError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            } header: {
                Text(L10n.string("Fan Speed Diagnostics & Test"))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            isHelperInstalled = SMCHelper.shared.checkHelperInstalled()
            isHelperPresent = SMCHelper.shared.isHelperToolPresent()
            fanController.refreshFanStatus()
        }
    }

    private func installHelper() {
        isInstallingHelper = true
        SMCHelper.shared.installHelperTool { success in
            isInstallingHelper = false
            isHelperInstalled = success && SMCHelper.shared.checkHelperInstalled()
            isHelperPresent = SMCHelper.shared.isHelperToolPresent()
            helperStatusText = isHelperInstalled
                ? L10n.string("Helper update successful!")
                : L10n.string("Helper update cancelled or failed.")
            if isHelperInstalled { fanController.allowPolicyRetry() }
        }
    }

    private var helperButtonTitle: String {
        if isInstallingHelper { return L10n.string("Updating...") }
        if isHelperInstalled { return L10n.string("Reinstall Helper...") }
        return isHelperPresent ? L10n.string("Update Helper...") : L10n.string("Install Helper...")
    }
}
