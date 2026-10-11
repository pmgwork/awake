import SwiftUI

/// The privileged helper shared by closed-lid operation and fan control.
struct PermissionsSettingsView: View {
    @ObservedObject var closedDisplayModeManager: ClosedDisplayModeManager

    var body: some View {
        Form {
            Section {
                HelperAuthorizationRow(closedDisplayModeManager: closedDisplayModeManager)
            } header: {
                Text(L10n.string("Hardware Helper"))
            } footer: {
                Text(helperFooterText)
            }

            Section {
                LabeledContent(L10n.string("Stay Awake with the Lid Closed")) {
                    Text(L10n.string(isHelperInstalled ? "Available" : "Unavailable"))
                        .foregroundStyle(.secondary)
                }
                LabeledContent(L10n.string("Low Power Mode with the Lid Closed")) {
                    Text(L10n.string(isHelperInstalled ? "Available" : "Unavailable"))
                        .foregroundStyle(.secondary)
                }
                LabeledContent(L10n.string("Fan Control")) {
                    Text(L10n.string(isHelperInstalled ? "Available" : "Unavailable"))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(L10n.string("Features That Use the Helper"))
            }
        }
        .formStyle(.grouped)
    }

    private var isHelperInstalled: Bool { closedDisplayModeManager.isHelperInstalled }

    private var helperFooterText: String {
        if !isHelperInstalled && SMCHelper.shared.isHelperToolPresent() {
            return L10n.string("Update the helper to use it on this Mac, including closed-lid operation on battery.")
        }
        return L10n.string("Closed-lid operation and fan control use this helper. macOS asks for an administrator password the first time.")
    }
}
