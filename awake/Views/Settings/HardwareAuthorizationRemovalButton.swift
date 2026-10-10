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
                    Text(L10n.string("Remove…"))
                }
            }
            .disabled(isBusy || coordinator.isRemovingHardwareAuthorization)
            if removalFailed {
                Label(
                    L10n.string("The helper wasn't removed. The removal was cancelled or failed."),
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.red)
            }
        }
        .alert(L10n.string("Remove the Helper?"), isPresented: $showingConfirmation) {
            Button(L10n.string("Cancel"), role: .cancel) {}
            Button(L10n.string("Remove Helper"), role: .destructive) {
                removalFailed = false
                Task { @MainActor in
                    removalFailed = !(await coordinator.removeHardwareAuthorization())
                    await refreshState()
                }
            }
        } message: {
            Text(L10n.string("This removes the helper used for closed-lid operation and fan control. Keep Awake stops, the fans return to automatic control, and both features turn off. An administrator password is required."))
        }
    }
}
