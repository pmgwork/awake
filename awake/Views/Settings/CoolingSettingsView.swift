import SwiftUI

struct CoolingSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var fanController: FanController
    @ObservedObject var closedDisplayModeManager: ClosedDisplayModeManager
    @ObservedObject private var coordinator = AwakeCoordinator.shared

    var body: some View {
        Form {
            Section {
                Picker(L10n.string("Automatic Cooling"), selection: $settings.automaticCoolingFanMode) {
                    ForEach(FanMode.allCases.filter { $0 != .auto }) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Picker(L10n.string("Manual Cooling"), selection: $settings.manualCoolingFanMode) {
                    ForEach(FanMode.allCases.filter { $0 != .auto }) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            } header: {
                Text(L10n.string("Fans"))
            } footer: {
                if let error = fanController.controlError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                } else if canUseHelper {
                    Text(L10n.string("Automatic: While Keep Awake Is On. Manual: Indefinitely or For Duration."))
                } else {
                    PermissionsHintFooter(text: L10n.string("Allow the helper in Permissions to control the fans."))
                }
            }
            .disabled(!canUseHelper)

            Section {
                Toggle(
                    L10n.string("Only When Plugged In"),
                    isOn: $settings.onlyOnACPower
                )
            } header: {
                Text(L10n.string("While Keep Awake Is On"))
            } footer: {
                Text(L10n.string("Follows Keep Awake in every mode. Runs only with the lid closed."))
            }
            .disabled(!canUseHelper)
        }
        .formStyle(.grouped)
        .task { await closedDisplayModeManager.refreshHelperState() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await closedDisplayModeManager.refreshHelperState() }
        }
    }

    private var canUseHelper: Bool {
        closedDisplayModeManager.isHelperInstalled
            && !closedDisplayModeManager.isCheckingHelper
            && !coordinator.isRemovingHardwareAuthorization
    }
}
