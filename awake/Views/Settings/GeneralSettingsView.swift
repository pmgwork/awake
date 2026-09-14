import SwiftUI
import UserNotifications
import AppKit
import Carbon.HIToolbox

struct GeneralSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var notificationManager: NotificationManager
    @ObservedObject var screenBehaviorManager: ScreenBehaviorManager
    @ObservedObject var updateService: AppUpdateService
    @ObservedObject var shortcutManager: GlobalShortcutManager

    var body: some View {
        Form {
            Section {
                Toggle(L10n.string("Launch Awake at Login"), isOn: $settings.launchAtLogin)
                Toggle(L10n.string("Enable Notifications"), isOn: $settings.notificationsEnabled)
                if settings.notificationsEnabled && notificationManager.authorizationStatus == .denied {
                    Label(
                        L10n.string("Notifications are disabled in System Settings."),
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.secondary)
                }
                Toggle(L10n.string("Show Remaining Time in Menu Bar"), isOn: $settings.showTimerInMenuBar)
                Picker(L10n.string("Battery Cutoff When Unplugged"), selection: $settings.lowBatteryThreshold) {
                    Text(L10n.string("Off")).tag(0)
                    ForEach([5, 10, 15, 20, 25], id: \.self) { threshold in
                        Text("\(threshold)%").tag(threshold)
                    }
                }
            } header: {
                Text(L10n.string("General Preferences"))
            }

            Section {
                LabeledContent(L10n.string("Toggle Awake")) {
                    ShortcutRecorderView(shortcut: $settings.toggleShortcut)
                }

                if let error = shortcutManager.registrationError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text(L10n.string("Global Shortcut"))
            }

            Section {
                Picker(L10n.string("Keep Awake After Completion"), selection: $settings.completionGraceDuration) {
                    Text(L10n.string("No Grace Period")).tag(TimeInterval(0))
                    Text(L10n.string("1 minute")).tag(TimeInterval(60))
                    Text(L10n.string("3 minutes")).tag(TimeInterval(180))
                    Text(L10n.string("5 minutes")).tag(TimeInterval(300))
                }
            } header: {
                Text(L10n.string("Completion Grace Period"))
            } footer: {
                Text(L10n.string("Applies to agents and downloads."))
            }

            Section {
                Toggle(L10n.string("Prevent Display Sleep"), isOn: $settings.preventDisplaySleep)
                Toggle(
                    L10n.string("Prevent Screen Saver & Automatic Lock"),
                    isOn: $settings.preventScreenSaver
                )
                if let error = screenBehaviorManager.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            } header: {
                Text(L10n.string("Display During Sessions"))
            } footer: {
                Text(L10n.string("These preferences apply only while Awake is actively preventing system sleep."))
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
                Text(L10n.string("Detects unfinished downloads in this folder."))
            }

            Section {
                Toggle(
                    L10n.string("Automatically check for updates"),
                    isOn: $settings.automaticallyCheckForUpdates
                )

                LabeledContent {
                    HStack {
                        updateStatusView
                        Button(L10n.string("Check Now")) {
                            updateService.checkForUpdates(userInitiated: true)
                        }
                        .disabled(updateService.state == .checking)
                    }
                } label: {
                    Text(L10n.string("Software Updates"))
                }

                if case .available(_, let release) = updateService.state {
                    LabeledContent {
                        Button(L10n.string("Download...")) {
                            updateService.openRelease(release)
                        }
                    } label: {
                        Text(L10n.format("Awake %@", release.version))
                    }
                }
            } footer: {
                Text(L10n.string("Checks GitHub Releases on launch. No account or signing required."))
            }

            Section {
                LabeledContent(L10n.string("Version"), value: appVersion)
                Button(L10n.string("Show Welcome Guide...")) {
                    OnboardingWindowController.shared.showOnboarding(coordinator: AwakeCoordinator.shared)
                }
                Button(L10n.string("View All Releases")) {
                    updateService.openReleasesPage()
                }
            } header: {
                Text(L10n.string("About"))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            notificationManager.refreshAuthorizationStatus()
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
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

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateService.state {
        case .idle:
            if let lastChecked = settings.lastUpdateCheckAt {
                Text(L10n.format("Last checked %@", lastChecked.formatted(date: .abbreviated, time: .shortened)))
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.string("Not Checked"))
                    .foregroundStyle(.secondary)
            }
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .upToDate:
            Label(L10n.string("Up to Date"), systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .available(_, let release):
            Label(L10n.format("Version %@ Available", release.version), systemImage: "arrow.down.circle")
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }
}

private struct ShortcutRecorderView: View {
    @Binding var shortcut: KeyboardShortcut?

    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggleRecording) {
                Text(buttonTitle)
                    .font(.system(size: 12, weight: .medium))
                    .frame(minWidth: 140)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)

            Button(L10n.string("Clear")) {
                shortcut = nil
            }
            .disabled(shortcut == nil || isRecording)
        }
        .onDisappear(perform: stopRecording)
    }

    private var buttonTitle: String {
        if isRecording {
            return L10n.string("Press shortcut…")
        }
        if let shortcut {
            return shortcut.displayString
        }
        return L10n.string("Record Shortcut")
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard eventMonitor == nil else { return }
        isRecording = true
        // A local monitor runs before the event reaches the responder chain, so
        // every key pressed while recording is consumed.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            capture(event)
            return nil
        }
    }

    private func stopRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isRecording = false
    }

    private func capture(_ event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape:
            stopRecording()
            return
        case kVK_Delete, kVK_ForwardDelete:
            shortcut = nil
            stopRecording()
            return
        default:
            break
        }

        let modifiers = event.modifierFlags.intersection(KeyboardShortcut.supportedModifiers)
        let candidate = KeyboardShortcut(keyCode: event.keyCode, modifiers: modifiers)
        guard candidate.isValid else {
            NSSound.beep()
            return
        }

        shortcut = candidate
        stopRecording()
    }
}
