import SwiftUI

struct CoolingSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var fanController: FanController

    @State private var isInstallingHelper = false
    @State private var isHelperInstalled = false
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
            }

            Section {
                HStack(spacing: 12) {
                    Label(helperStateTitle, systemImage: helperStateIcon)
                        .foregroundStyle(helperStateColor)

                    Spacer(minLength: 12)

                    Button {
                        installHelper()
                    } label: {
                        HStack(spacing: 6) {
                            if isInstallingHelper {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(helperButtonTitle)
                        }
                    }
                    .disabled(isInstallingHelper)
                }

                HStack {
                    Button(L10n.string("Test 100% Spin")) {
                        fanController.testFanSpeed(mode: .maximum)
                    }
                    Button(L10n.string("Restore Auto")) {
                        fanController.testFanSpeed(mode: .auto)
                    }
                }
            } header: {
                Text(L10n.string("Fan Control Helper"))
            } footer: {
                Label(combinedFooterText, systemImage: combinedFooterIcon)
                    .foregroundStyle(combinedFooterColor)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshHelperState()
            fanController.refreshFanStatus()
        }
    }

    private func installHelper() {
        helperStatusText = ""
        isInstallingHelper = true
        SMCHelper.shared.installHelperTool { success in
            isInstallingHelper = false
            isHelperPresent = SMCHelper.shared.isHelperToolPresent()
            Task { @MainActor in
                let installed = await SMCHelper.shared.refreshHelperInstallState()
                isHelperInstalled = success && installed
                helperStatusText = isHelperInstalled
                    ? L10n.string("Helper update successful!")
                    : L10n.string("Helper update cancelled or failed.")
                if isHelperInstalled { fanController.allowPolicyRetry() }
            }
        }
    }

    /// The helper check launches a privileged binary, so it must stay off the
    /// main thread. `@State` initializers are re-evaluated on every view
    /// re-creation, which previously spawned a process during view updates.
    private func refreshHelperState() {
        isHelperPresent = SMCHelper.shared.isHelperToolPresent()
        Task { @MainActor in
            isHelperInstalled = await SMCHelper.shared.refreshHelperInstallState()
        }
    }

    private var combinedFooterText: String {
        if let error = fanController.controlError { return error }
        if fanController.isTestModeActive {
            return L10n.string("Fan test ends after 60 seconds and returns to the current cooling policy.")
        }
        return helperFooterText
    }

    private var combinedFooterIcon: String {
        if fanController.controlError != nil { return "exclamationmark.triangle" }
        if fanController.isTestModeActive { return "timer" }
        return isHelperInstalled ? "checkmark.circle" : "info.circle"
    }

    private var combinedFooterColor: Color {
        if fanController.controlError != nil { return .red }
        return .secondary
    }

    private var helperButtonTitle: String {
        if isInstallingHelper { return L10n.string("Updating...") }
        if isHelperInstalled { return L10n.string("Reinstall Helper...") }
        return isHelperPresent ? L10n.string("Update Helper...") : L10n.string("Install Helper...")
    }

    private var helperStateTitle: String {
        if !isHelperInstalled && !helperStatusText.isEmpty { return helperStatusText }
        return isHelperInstalled
            ? L10n.string("Fan Control Access Authorized")
            : L10n.string("Fan Control Authorization Required")
    }

    private var helperStateIcon: String {
        if !isHelperInstalled && !helperStatusText.isEmpty { return "exclamationmark.triangle" }
        return isHelperInstalled ? "checkmark.circle" : "lock.shield"
    }

    private var helperStateColor: Color {
        if !isHelperInstalled && !helperStatusText.isEmpty { return .red }
        return isHelperInstalled ? .green : .secondary
    }

    private var helperFooterText: String {
        if isHelperInstalled {
            return L10n.string("The current helper is installed and ready for fan control.")
        }
        return isHelperPresent
            ? L10n.string("A newer helper is required for this Mac and battery closed-lid operation.")
            : L10n.string("macOS requires administrator permission once to control hardware fans on Apple Silicon.")
    }
}
