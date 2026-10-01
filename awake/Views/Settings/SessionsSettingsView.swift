import SwiftUI
import AppKit

/// Preferences that apply while Awake is keeping the Mac awake.
struct SessionsSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var screenBehaviorManager: ScreenBehaviorManager
    @ObservedObject var closedDisplayModeManager: ClosedDisplayModeManager
    @ObservedObject private var coordinator = AwakeCoordinator.shared
    @State private var isInstallingHelper = false
    @State private var helperStatusText = ""

    var body: some View {
        Form {
            Section {
                Picker(L10n.string("Keep Awake After Completion"), selection: $settings.completionGraceDuration) {
                    Text(L10n.string("No Grace Period")).tag(TimeInterval(0))
                    Text(L10n.string("1 minute")).tag(TimeInterval(60))
                    Text(L10n.string("3 minutes")).tag(TimeInterval(180))
                    Text(L10n.string("5 minutes")).tag(TimeInterval(300))
                }
                Toggle(L10n.string("Show Remaining Time in Menu Bar"), isOn: $settings.showTimerInMenuBar)
            } header: {
                Text(L10n.string("Session Behavior"))
            } footer: {
                Text(L10n.string("The completion delay applies after agent activity or downloads finish."))
            }

            Section {
                Toggle(L10n.string("Prevent Display Sleep"), isOn: $settings.preventDisplaySleep)
                Toggle(
                    L10n.string("Prevent Screen Saver & Idle Lock (Lid Open)"),
                    isOn: $settings.preventScreenSaver
                )
                Toggle(L10n.string("Keep Mac Awake with Lid Closed"), isOn: Binding(
                    get: { settings.closedDisplayModeEnabled && closedDisplayModeManager.isHelperInstalled },
                    set: { enabled in
                        if !enabled || canEnableClosedDisplayMode {
                            settings.closedDisplayModeEnabled = enabled
                        }
                    }
                ))
                .disabled(!canEnableClosedDisplayMode)

                if let error = screenBehaviorManager.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }

                if let error = closedDisplayModeManager.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            } header: {
                Text(L10n.string("Display & Lid During Sessions"))
            } footer: {
                Text(L10n.string("These preferences apply only while Awake is actively preventing system sleep."))
            }

            Section {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(
                        L10n.string(closedDisplayModeManager.isHelperInstalled
                            ? "Closed-Lid Access Authorized"
                            : "Closed-Lid Authorization Required"),
                        systemImage: closedDisplayModeManager.isHelperInstalled ? "checkmark.circle" : "lock.shield"
                    )
                    .foregroundStyle(closedDisplayModeManager.isHelperInstalled ? Color.green : Color.secondary)
                    Spacer(minLength: 12)
                    Button {
                        installHelper()
                    } label: {
                        HStack(spacing: 6) {
                            if isInstallingHelper || closedDisplayModeManager.isCheckingHelper {
                                ProgressView().controlSize(.small)
                            }
                            Text(helperButtonTitle)
                        }
                    }
                    .disabled(isInstallingHelper || closedDisplayModeManager.isCheckingHelper || coordinator.isRemovingHardwareAuthorization)
                    if SMCHelper.shared.isHelperToolPresent() {
                        HardwareAuthorizationRemovalButton(isBusy: isInstallingHelper || closedDisplayModeManager.isCheckingHelper) {
                            helperStatusText = ""
                            await closedDisplayModeManager.refreshHelperState()
                        }
                    }
                }
                if !helperStatusText.isEmpty {
                    Text(helperStatusText)
                        .foregroundStyle(closedDisplayModeManager.isHelperInstalled ? Color.secondary : Color.red)
                }
            } header: {
                Text(L10n.string("Closed-Lid Helper"))
            } footer: {
                Text(L10n.string("Closed-lid operation requires administrator permission once. This helper is shared with fan control."))
            }

            Section {
                LabeledContent {
                    HStack {
                        Text(settings.downloadFolderPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button(L10n.string("Choose...")) {
                            chooseDownloadFolder()
                        }
                    }
                } label: {
                    Text(L10n.string("Monitored Folder"))
                }
            } header: {
                Text(L10n.string("Download Monitoring"))
            } footer: {
                Text(L10n.string("Detects unfinished downloads from temporary files in the monitored folder."))
            }
        }
        .formStyle(.grouped)
        .task { await closedDisplayModeManager.refreshHelperState() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await closedDisplayModeManager.refreshHelperState() }
        }
    }

    private var helperButtonTitle: String {
        if isInstallingHelper { return L10n.string("Updating...") }
        if closedDisplayModeManager.isHelperInstalled { return L10n.string("Reinstall...") }
        return SMCHelper.shared.isHelperToolPresent()
            ? L10n.string("Update...") : L10n.string("Install...")
    }

    private var canEnableClosedDisplayMode: Bool {
        closedDisplayModeManager.isHelperInstalled
            && !closedDisplayModeManager.isCheckingHelper
            && !isInstallingHelper
            && !coordinator.isRemovingHardwareAuthorization
    }

    private func installHelper() {
        helperStatusText = ""
        isInstallingHelper = true
        SMCHelper.shared.installHelperTool { success in
            Task { @MainActor in
                await closedDisplayModeManager.refreshHelperState()
                isInstallingHelper = false
                helperStatusText = success && closedDisplayModeManager.isHelperInstalled
                    ? ""
                    : L10n.string("Helper update cancelled or failed.")
                if success && closedDisplayModeManager.isHelperInstalled && !coordinator.isRemovingHardwareAuthorization {
                    settings.closedDisplayModeEnabled = true
                    AwakeCoordinator.shared.fanController.allowPolicyRetry()
                    AwakeCoordinator.shared.evaluateState()
                }
            }
        }
    }

    private func chooseDownloadFolder() {
        let panel = NSOpenPanel()
        panel.title = L10n.string("Choose Download Folder")
        panel.prompt = L10n.string("Choose")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: settings.downloadFolderPath, isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url {
            settings.downloadFolderPath = url.path
        }
    }
}
