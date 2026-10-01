import SwiftUI

struct CoolingSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var fanController: FanController
    @ObservedObject private var coordinator = AwakeCoordinator.shared

    @State private var isInstallingHelper = false
    @State private var isHelperInstalled = false
    @State private var isCheckingHelper = false
    @State private var isHelperPresent = SMCHelper.shared.isHelperToolPresent()
    @State private var helperStatusText = ""

    var body: some View {
        Form {
            Section {
                Toggle(L10n.string("Enable Closed-Lid Cooling"), isOn: Binding(
                    get: { settings.closedLidCoolingEnabled && isHelperInstalled },
                    set: { enabled in
                        if !enabled || canUseHelper {
                            settings.closedLidCoolingEnabled = enabled
                        }
                    }
                ))
                Toggle(
                    L10n.string("Use Automatic Fan Control with an External Display"),
                    isOn: $settings.excludeNormalClamshell
                )
                .disabled(!settings.closedLidCoolingEnabled || !isHelperInstalled)
                Toggle(
                    L10n.string("Closed-Lid Cooling only on AC Power"),
                    isOn: $settings.onlyOnACPower
                )
                .disabled(!settings.closedLidCoolingEnabled || !isHelperInstalled)

                Picker(L10n.string("Closed-Lid Fan Mode:"), selection: $settings.closedLidFanMode) {
                    ForEach(FanMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .disabled(!settings.closedLidCoolingEnabled || !isHelperInstalled)
            } header: {
                Text(L10n.string("Closed-Lid Cooling & Thermal Management"))
            }
            .disabled(!canUseHelper)

            Section {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
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
                    .disabled(isInstallingHelper || isCheckingHelper || coordinator.isRemovingHardwareAuthorization)
                    if isHelperPresent {
                        HardwareAuthorizationRemovalButton(isBusy: isInstallingHelper || isCheckingHelper) {
                            helperStatusText = ""
                            await refreshHelperState()
                        }
                    }
                }

                HStack {
                    Button(L10n.string("Test 100% Spin")) {
                        fanController.testFanSpeed(mode: .maximum)
                    }
                    .disabled(!canUseHelper)
                    Button(L10n.string("Restore Auto")) {
                        fanController.testFanSpeed(mode: .auto)
                    }
                }
                .disabled(coordinator.isRemovingHardwareAuthorization)
            } header: {
                Text(L10n.string("Fan Control Helper"))
            } footer: {
                if let text = combinedFooterText {
                    Label(text, systemImage: combinedFooterIcon)
                        .foregroundStyle(combinedFooterColor)
                }
            }
        }
        .formStyle(.grouped)
        .task { await refreshHelperState() }
        .onChange(of: fanController.activeMode) { _, _ in
            Task { await refreshHelperState() }
        }
        .onChange(of: fanController.controlError) { _, _ in
            Task { await refreshHelperState() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshHelperState() }
        }
    }

    private func installHelper() {
        helperStatusText = ""
        isInstallingHelper = true
        SMCHelper.shared.installHelperTool { success in
            Task { @MainActor in
                await refreshHelperState()
                isInstallingHelper = false
                helperStatusText = success && isHelperInstalled
                    ? ""
                    : L10n.string("Helper update cancelled or failed.")
                if success && isHelperInstalled && !coordinator.isRemovingHardwareAuthorization {
                    settings.closedLidCoolingEnabled = true
                    fanController.allowPolicyRetry()
                    coordinator.evaluateState()
                }
            }
        }
    }

    /// The helper check launches a privileged binary, so it must stay off the
    /// main thread. `@State` initializers are re-evaluated on every view
    /// re-creation, which previously spawned a process during view updates.
    private func refreshHelperState() async {
        while isCheckingHelper {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
        isCheckingHelper = true
        isHelperPresent = SMCHelper.shared.isHelperToolPresent()
        isHelperInstalled = await SMCHelper.shared.refreshHelperInstallState()
        isCheckingHelper = false
    }

    private var canUseHelper: Bool {
        isHelperInstalled && !isCheckingHelper && !isInstallingHelper && !coordinator.isRemovingHardwareAuthorization
    }

    private var combinedFooterText: String? {
        if let error = fanController.controlError { return error }
        if fanController.isTestModeActive {
            return L10n.string("Fan test ends after 60 seconds and returns to the current cooling policy.")
        }
        return helperFooterText
    }

    private var combinedFooterIcon: String {
        if fanController.controlError != nil { return "exclamationmark.triangle" }
        if fanController.isTestModeActive { return "timer" }
        return "info.circle"
    }

    private var combinedFooterColor: Color {
        if fanController.controlError != nil { return .red }
        return .secondary
    }

    private var helperButtonTitle: String {
        if isInstallingHelper { return L10n.string("Updating...") }
        if isHelperInstalled { return L10n.string("Reinstall...") }
        return isHelperPresent ? L10n.string("Update...") : L10n.string("Install...")
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

    private var helperFooterText: String? {
        if isHelperInstalled { return nil }
        return isHelperPresent
            ? L10n.string("A newer helper is required for this Mac and battery closed-lid operation.")
            : L10n.string("macOS requires administrator permission once to control hardware fans on Apple Silicon.")
    }
}
