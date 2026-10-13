import SwiftUI

struct CoolingSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var fanController: FanController
    @ObservedObject var closedDisplayModeManager: ClosedDisplayModeManager
    @ObservedObject private var coordinator = AwakeCoordinator.shared

    var body: some View {
        Form {
            Section {
                Picker(L10n.string("Fan Speed"), selection: $settings.coolingFanMode) {
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
                    Text(L10n.string("Every cooling mode except System runs the fans at this speed. Cooling is unavailable below the battery stop level. Only While Agent Is Running stays on after a restart."))
                } else {
                    PermissionsHintFooter(text: L10n.string("Allow the helper in Permissions to control the fans."))
                }
            }
            .disabled(!canUseHelper)

            Section {
                Toggle(
                    L10n.string("Only While the Lid Is Closed"),
                    isOn: $settings.agentCoolingRequiresLidClosed
                )
                Toggle(
                    L10n.string("Leave Fans to macOS with an External Display"),
                    isOn: $settings.excludeNormalClamshell
                )
                .disabled(!settings.agentCoolingRequiresLidClosed)
                Toggle(
                    L10n.string("Only When Plugged In"),
                    isOn: $settings.onlyOnACPower
                )
            } header: {
                Text(L10n.string("While Agent Is Running"))
            } footer: {
                Text(L10n.string("Runs the fans while a monitored agent is working. It starts as soon as you select it in the menu, and you can pause it there."))
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
