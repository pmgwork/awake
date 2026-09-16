import SwiftUI
import AppKit

/// Preferences that apply while Awake is keeping the Mac awake.
struct SessionsSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var screenBehaviorManager: ScreenBehaviorManager

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
                Text(L10n.string("Keep Awake After Completion applies to agents and downloads."))
            }

            Section {
                Toggle(L10n.string("Prevent Display Sleep"), isOn: $settings.preventDisplaySleep)
                Toggle(
                    L10n.string("Prevent Screen Saver & Automatic Lock"),
                    isOn: $settings.preventScreenSaver
                )
            } header: {
                Text(L10n.string("Display During Sessions"))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("These preferences apply only while Awake is actively preventing system sleep."))
                    if let error = screenBehaviorManager.lastError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
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
        }
        .formStyle(.grouped)
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
