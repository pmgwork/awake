import SwiftUI

/// Preferences that apply while Awake is keeping the Mac awake.
struct KeepAwakeSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var screenBehaviorManager: ScreenBehaviorManager
    @ObservedObject var closedDisplayModeManager: ClosedDisplayModeManager
    @ObservedObject private var coordinator = AwakeCoordinator.shared

    var body: some View {
        Form {
            Section {
                Toggle(L10n.string("Stay Awake with the Lid Closed"), isOn: Binding(
                    get: { settings.closedDisplayModeEnabled && closedDisplayModeManager.isHelperInstalled },
                    set: { enabled in
                        if !enabled || canEnableClosedDisplayMode {
                            settings.closedDisplayModeEnabled = enabled
                        }
                    }
                ))
                .disabled(!canEnableClosedDisplayMode)
                Toggle(L10n.string("Prevent Display Sleep"), isOn: $settings.preventDisplaySleep)
                Toggle(
                    L10n.string("Prevent Screen Saver and Auto-Lock"),
                    isOn: $settings.preventScreenSaver
                )

                if let error = screenBehaviorManager.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }

                if let error = closedDisplayModeManager.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            } header: {
                Text(L10n.string("While Keep Awake Is On"))
            } footer: {
                if closedDisplayModeManager.isHelperInstalled || closedDisplayModeManager.isCheckingHelper {
                    Text(L10n.string("These settings apply only while Keep Awake is on."))
                } else {
                    PermissionsHintFooter(text: L10n.string("Allow the helper in Permissions to stay awake with the lid closed."))
                }
            }

            Section {
                Picker(L10n.string("Stop at Battery Level"), selection: $settings.lowBatteryThreshold) {
                    Text(L10n.string("Off")).tag(0)
                    ForEach([5, 10, 15, 20, 25], id: \.self) { threshold in
                        Text("\(threshold)%").tag(threshold)
                    }
                }
            } header: {
                Text(L10n.string("Battery"))
            } footer: {
                Text(L10n.string("On battery, Keep Awake and Cooling stop when the charge falls to this level."))
            }
        }
        .formStyle(.grouped)
        .task { await closedDisplayModeManager.refreshHelperState() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await closedDisplayModeManager.refreshHelperState() }
        }
    }

    private var canEnableClosedDisplayMode: Bool {
        closedDisplayModeManager.isHelperInstalled
            && !closedDisplayModeManager.isCheckingHelper
            && !coordinator.isRemovingHardwareAuthorization
    }
}
