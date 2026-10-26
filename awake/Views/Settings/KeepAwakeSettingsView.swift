import SwiftUI

/// Preferences that apply while Awake is keeping the Mac awake.
struct KeepAwakeSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var screenBehaviorManager: ScreenBehaviorManager
    @ObservedObject var closedDisplayModeManager: ClosedDisplayModeManager
    @ObservedObject var lowPowerModeManager: LowPowerModeManager
    @ObservedObject private var coordinator = AwakeCoordinator.shared

    var body: some View {
        Form {
            Section {
                Picker(L10n.string("Keep Awake After Agents Finish"), selection: $settings.completionGraceDuration) {
                    Text(L10n.string("Off")).tag(TimeInterval(0))
                    ForEach(graceDurations, id: \.self) { duration in
                        Text(L10n.format("%d min", Int(duration / 60))).tag(duration)
                    }
                }
            } header: {
                Text(L10n.string("While Agent Is Running"))
            }

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
                Toggle(L10n.string("Use Low Power Mode with the Lid Closed"), isOn: Binding(
                    get: { settings.lowPowerModeWhenLidClosed && isClosedDisplayModeOn },
                    set: { enabled in
                        if !enabled || isClosedDisplayModeOn {
                            settings.lowPowerModeWhenLidClosed = enabled
                        }
                    }
                ))
                .disabled(!isClosedDisplayModeOn)
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

                if let error = lowPowerModeManager.lastError {
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
                Text(L10n.string("On battery, Keep Awake and agent cooling stop when the charge falls to this level."))
            }
        }
        .formStyle(.grouped)
        .task { await closedDisplayModeManager.refreshHelperState() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await closedDisplayModeManager.refreshHelperState() }
        }
    }

    private var graceDurations: [TimeInterval] {
        var durations: Set<TimeInterval> = [60, 120, 180, 300, 600, 900, 1800]
        // Keep custom durations saved by earlier releases selectable.
        if settings.completionGraceDuration > 0 { durations.insert(settings.completionGraceDuration) }
        return durations.sorted()
    }

    /// Low Power Mode applies only while the Mac stays awake with the lid closed.
    private var isClosedDisplayModeOn: Bool {
        canEnableClosedDisplayMode && settings.closedDisplayModeEnabled
    }

    private var canEnableClosedDisplayMode: Bool {
        closedDisplayModeManager.isHelperInstalled
            && !closedDisplayModeManager.isCheckingHelper
            && !coordinator.isRemovingHardwareAuthorization
    }
}
