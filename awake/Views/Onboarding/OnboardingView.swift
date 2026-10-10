import SwiftUI
import UserNotifications

struct OnboardingView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var notificationManager: NotificationManager
    @ObservedObject var eventMonitor: AgentEventMonitor
    @ObservedObject var integrationManager: HookIntegrationManager
    @ObservedObject var closedDisplayModeManager: ClosedDisplayModeManager
    var onFinished: () -> Void

    @State private var step: Step = Step.initial
    @State private var pendingProvider: AgentProvider?

    enum Step: Int, CaseIterable {
        case welcome
        case agents
        case permissions
        case preferences
        case completion

        static var initial: Step {
            #if DEBUG
            // Lets screenshots of each page be taken without clicking through.
            if UserDefaults.standard.object(forKey: "AwakeDebugOnboardingStep") != nil,
               let step = Step(rawValue: UserDefaults.standard.integer(forKey: "AwakeDebugOnboardingStep")) {
                return step
            }
            #endif
            return .welcome
        }

        var symbol: String {
            switch self {
            case .welcome: return "cup.and.saucer"
            case .agents: return "cpu"
            case .permissions: return "lock.shield"
            case .preferences: return "gearshape"
            case .completion: return "checkmark.circle"
            }
        }

        var title: String {
            switch self {
            case .welcome: return "Welcome to Awake"
            case .agents: return "Link Your Agents"
            case .permissions: return "Closed Lid & Fans"
            case .preferences: return "Preferences"
            case .completion: return "You're Ready"
            }
        }

        var subtitle: String {
            switch self {
            case .welcome, .completion: return ""
            case .agents: return "Awake keeps your Mac awake while a linked agent is working and lets it sleep when the work is done."
            case .permissions: return "Optional. You need this only to keep working with the lid closed or to control the fans."
            case .preferences: return "You can change these later in Settings."
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: welcomePage
                case .completion: completionPage
                default: formPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
        }
        .frame(width: OnboardingWindowController.contentSize.width,
               height: OnboardingWindowController.contentSize.height)
        .onAppear {
            notificationManager.refreshAuthorizationStatus()
            integrationManager.refreshStatuses()
        }
        .confirmationDialog(
            L10n.string("Hook Integration"),
            isPresented: Binding(
                get: { pendingProvider != nil },
                set: { if !$0 { pendingProvider = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let provider = pendingProvider {
                Button(L10n.string("Update Configuration")) {
                    integrationManager.install(provider)
                    pendingProvider = nil
                }
            }
            Button(L10n.string("Cancel"), role: .cancel) {
                pendingProvider = nil
            }
        } message: {
            if let provider = pendingProvider {
                Text(L10n.format(
                    "Awake backs up your configuration and changes only its own %@ entry.",
                    provider.integrationKind
                ))
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            stepIndicator

            Spacer()

            if step != .welcome {
                Button(L10n.string("Back")) { move(by: -1) }
            }
            if step != .completion {
                Button(L10n.string("Set Up Later")) { finish() }
            }
            Button(L10n.string(primaryButtonTitle)) {
                if step == .completion { finish() } else { move(by: 1) }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var primaryButtonTitle: String {
        switch step {
        case .welcome: return "Get Started"
        case .completion: return "Done"
        default: return "Continue"
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { item in
                Circle()
                    .fill(item == step ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(L10n.format("Step %d of %d", step.rawValue + 1, Step.allCases.count))
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                if let appIcon = AppIcon.image(size: 88) {
                    Image(nsImage: appIcon)
                        .accessibilityHidden(true)
                }
                Text(L10n.string("Welcome to Awake"))
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .accessibilityAddTraits(.isHeader)
                Text(L10n.string("Awake keeps your Mac awake while AI coding agents work, even with the lid closed. This short guide sets up the essentials."))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                feature(symbol: "cpu", title: "While Agent Is Running",
                        description: "Stay awake while your linked agents are working.")
                feature(symbol: "timer", title: "For Duration",
                        description: "Stay awake for a set time, then sleep as usual.")
                feature(symbol: "arrow.down.circle", title: "While Downloading",
                        description: "Stay awake until the downloads in a folder finish.")
                feature(symbol: "fanblades", title: "Cooling",
                        description: "Run the fans faster while an agent works with the lid closed.")
            }
            .frame(maxWidth: 420, alignment: .leading)
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 28)
    }

    private var formPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: step.symbol)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string(step.title))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .accessibilityAddTraits(.isHeader)
                    Text(L10n.string(step.subtitle))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 4)

            Form {
                switch step {
                case .agents: agentsContent
                case .permissions: permissionsContent
                case .preferences: preferencesContent
                case .welcome, .completion: EmptyView()
                }
            }
            .formStyle(.grouped)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    @ViewBuilder
    private var agentsContent: some View {
        Section {
            ForEach(AgentProvider.allCases) { provider in
                providerRow(provider)
            }
        } footer: {
            HStack {
                Button {
                    eventMonitor.reloadNow()
                    integrationManager.refreshStatuses()
                } label: {
                    Label(L10n.string("Refresh"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.link)
                Spacer(minLength: 12)
                if let error = integrationManager.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private var permissionsContent: some View {
        Section {
            HelperAuthorizationRow(
                closedDisplayModeManager: closedDisplayModeManager,
                allowsRemoval: false,
                onInstalled: { settings.closedDisplayModeEnabled = true }
            )
            Toggle(L10n.string("Stay Awake with the Lid Closed"), isOn: Binding(
                get: { settings.closedDisplayModeEnabled && closedDisplayModeManager.isHelperInstalled },
                set: { settings.closedDisplayModeEnabled = $0 }
            ))
            .disabled(!closedDisplayModeManager.isHelperInstalled)
        } footer: {
            Text(L10n.string("Closed-lid operation and fan control use this helper. macOS asks for an administrator password the first time."))
        }
    }

    @ViewBuilder
    private var preferencesContent: some View {
        Section {
            Toggle(L10n.string("Launch Awake at Login"), isOn: $settings.launchAtLogin)
            Toggle(L10n.string("Enable Notifications"), isOn: $settings.notificationsEnabled)
            if settings.notificationsEnabled && notificationManager.authorizationStatus == .denied {
                Label(
                    L10n.string("Notifications are turned off in System Settings."),
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.red)
            }
            Toggle(L10n.string("Show Remaining Time in Menu Bar"), isOn: $settings.showTimerInMenuBar)
        }

        Section {
            Toggle(L10n.string("Prevent Display Sleep"), isOn: $settings.preventDisplaySleep)
            Toggle(
                L10n.string("Prevent Screen Saver and Auto-Lock"),
                isOn: $settings.preventScreenSaver
            )
        } footer: {
            Text(L10n.string("These settings apply only while Keep Awake is on."))
        }
    }

    private var completionPage: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(L10n.string("You're Ready"))
                .font(.largeTitle)
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 14) {
                feature(symbol: "cursorarrow.click", title: "Left-Click the Cup",
                        description: "Choose a mode and start Keep Awake or Cooling.")
                feature(symbol: "cursorarrow.click.2", title: "Right-Click the Cup",
                        description: "Start or stop Keep Awake, or pause monitoring, with one click.")
                feature(symbol: "gearshape", title: "Settings",
                        description: "Open Settings from the menu at any time. You can reopen this guide from General.")
            }
            .frame(maxWidth: 420, alignment: .leading)
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 28)
    }

    private func feature(symbol: String, title: String, description: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string(title))
                    .fontWeight(.semibold)
                Text(L10n.string(description))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
        }
    }

    private func providerRow(_ provider: AgentProvider) -> some View {
        let agent = settings.monitoredAgents.first { $0.provider == provider }
        let status = integrationManager.status(for: provider)
        let isInstalled = integrationManager.isToolInstalled(provider)
        let canMonitor = isInstalled && (status == .linked || status == .unverified)

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .fontWeight(.medium)
                Text(isInstalled ? status.label : L10n.string("CLI not installed"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            switch status {
            case .unlinked, .needsRepair:
                Button(status == .needsRepair ? L10n.string("Repair") : L10n.string("Link")) {
                    pendingProvider = provider
                }
                .disabled(!isInstalled)
            case .unverified, .linked:
                Toggle(
                    L10n.format("Monitor %@", provider.displayName),
                    isOn: Binding(
                        get: { canMonitor && (agent?.isEnabled ?? false) },
                        set: { enabled in
                            if let agent, canMonitor, enabled != agent.isEnabled {
                                settings.toggleAgent(id: agent.id)
                            }
                        }
                    )
                )
                .labelsHidden()
                .disabled(!canMonitor)
            }
        }
    }

    // MARK: - Navigation

    private func move(by offset: Int) {
        guard let next = Step(rawValue: step.rawValue + offset) else { return }
        step = next
        switch next {
        case .agents: integrationManager.refreshStatuses()
        case .permissions: Task { await closedDisplayModeManager.refreshHelperState() }
        default: break
        }
    }

    private func finish() {
        settings.completeOnboarding()
        onFinished()
    }
}
