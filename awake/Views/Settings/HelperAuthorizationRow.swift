import SwiftUI

/// Status and install controls for the privileged helper shared by
/// closed-lid operation and fan control. Used by Settings and the welcome guide.
struct HelperAuthorizationRow: View {
    @ObservedObject var closedDisplayModeManager: ClosedDisplayModeManager
    var allowsRemoval = true
    var onInstalled: () -> Void = {}

    @ObservedObject private var coordinator = AwakeCoordinator.shared
    @State private var isInstallingHelper = false
    @State private var helperStatusText = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(helperStateTitle, systemImage: helperStateIcon)
                .foregroundStyle(helperStateColor)
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
            if allowsRemoval && SMCHelper.shared.isHelperToolPresent() {
                HardwareAuthorizationRemovalButton(isBusy: isInstallingHelper || closedDisplayModeManager.isCheckingHelper) {
                    helperStatusText = ""
                    await closedDisplayModeManager.refreshHelperState()
                }
            }
        }
        .task { await closedDisplayModeManager.refreshHelperState() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await closedDisplayModeManager.refreshHelperState() }
        }
    }

    private var isHelperInstalled: Bool { closedDisplayModeManager.isHelperInstalled }

    private var helperButtonTitle: String {
        if isInstallingHelper { return L10n.string("Updating…") }
        if isHelperInstalled { return L10n.string("Reinstall…") }
        return SMCHelper.shared.isHelperToolPresent()
            ? L10n.string("Update…") : L10n.string("Install…")
    }

    private var helperStateTitle: String {
        if !isHelperInstalled && !helperStatusText.isEmpty { return helperStatusText }
        return isHelperInstalled
            ? L10n.string("Helper Authorized")
            : L10n.string("Helper Authorization Required")
    }

    private var helperStateIcon: String {
        if !isHelperInstalled && !helperStatusText.isEmpty { return "exclamationmark.triangle" }
        return isHelperInstalled ? "checkmark.circle" : "lock.shield"
    }

    private var helperStateColor: Color {
        if !isHelperInstalled && !helperStatusText.isEmpty { return .red }
        return isHelperInstalled ? .green : .secondary
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
                    : L10n.string("Helper installation was cancelled or failed.")
                if success && closedDisplayModeManager.isHelperInstalled && !coordinator.isRemovingHardwareAuthorization {
                    coordinator.fanController.allowPolicyRetry()
                    coordinator.evaluateState()
                    onInstalled()
                }
            }
        }
    }
}

/// Footer text with a link that opens the Permissions tab.
struct PermissionsHintFooter: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
            Button(L10n.string("Open Permissions")) {
                SettingsWindowController.shared.show(tab: .permissions)
            }
            .buttonStyle(.link)
        }
    }
}
