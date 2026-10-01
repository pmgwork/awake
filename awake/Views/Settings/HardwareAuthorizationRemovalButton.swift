import SwiftUI

struct HardwareAuthorizationRemovalButton: View {
    @ObservedObject private var coordinator = AwakeCoordinator.shared
    @State private var showingConfirmation = false
    @State private var removalFailed = false

    var isBusy: Bool
    var refreshState: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(role: .destructive) {
                showingConfirmation = true
            } label: {
                HStack(spacing: 6) {
                    if coordinator.isRemovingHardwareAuthorization {
                        ProgressView().controlSize(.small)
                    }
                    Text(L10n.string("Remove..."))
                }
            }
            .disabled(isBusy || coordinator.isRemovingHardwareAuthorization)
            if removalFailed {
                Label(
                    L10n.string("Authorization removal was cancelled or failed. The helper has not been removed."),
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.red)
            }
        }
        .alert(L10n.string("Remove Hardware Authorization?"), isPresented: $showingConfirmation) {
            Button(L10n.string("Cancel"), role: .cancel) {}
            Button(L10n.string("Remove Authorization"), role: .destructive) {
                removalFailed = false
                Task { @MainActor in
                    removalFailed = !(await coordinator.removeHardwareAuthorization())
                    await refreshState()
                }
            }
        } message: {
            Text(L10n.string("This removes the shared helper for closed-lid operation and fan control. The current Awake session will stop, fans will return to automatic control, and both features will be turned off. Administrator permission is required."))
        }
    }
}
