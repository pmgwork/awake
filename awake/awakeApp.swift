//
//  awakeApp.swift
//  Awake
//

import SwiftUI
import AppKit
import Combine

@main
struct awakeApp: App {
    @NSApplicationDelegateAdaptor(AwakeAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
private final class AwakeAppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = AwakeCoordinator.shared
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configurePopover()
        observeStatusChanges()
        updateStatusItem()
        if !coordinator.settings.hasCompletedOnboarding {
            DispatchQueue.main.async { [weak self] in
                self?.showOnboardingIfNeeded()
            }
        } else {
            scheduleAutomaticUpdateCheck()
        }
    }

    private func scheduleAutomaticUpdateCheck() {
        guard coordinator.settings.automaticallyCheckForUpdates else { return }
        // Avoid hammering the API on every restart: at most once per 24h.
        if let last = coordinator.settings.lastUpdateCheckAt,
           Date().timeIntervalSince(last) < 24 * 60 * 60 {
            return
        }
        // Small delay so menu-bar startup stays snappy.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            AppUpdateService.shared.checkForUpdates(userInitiated: false)
        }
    }

    private func showOnboardingIfNeeded() {
        guard !coordinator.settings.hasCompletedOnboarding else { return }
        OnboardingWindowController.shared.showOnboarding(coordinator: coordinator)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.setAccessibilityLabel("Awake")
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                coordinator: coordinator,
                settings: coordinator.settings
            ) { [weak self] in
                self?.popover.performClose(nil)
                SettingsWindowController.shared.showSettings(coordinator: AwakeCoordinator.shared)
            }
        )
    }

    private func observeStatusChanges() {
        coordinator.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItem()
                }
            }
            .store(in: &cancellables)

        coordinator.settings.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItem()
                }
            }
            .store(in: &cancellables)
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            coordinator.togglePrimaryAction()
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            resizePopoverToFitContent()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func resizePopoverToFitContent() {
        guard let contentView = popover.contentViewController?.view else { return }
        contentView.layoutSubtreeIfNeeded()
        let fittingSize = contentView.fittingSize
        if fittingSize.width > 0, fittingSize.height > 0 {
            popover.contentSize = fittingSize
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }

        let image = NSImage(named: NSImage.Name(iconName))
        image?.size = NSSize(width: 21, height: 16.8)
        // Keep the cup as a template image so the system renders it with the
        // menu bar material. The monitoring state is expressed through the
        // button's content tint instead of drawing a pre-colored copy, which
        // keeps the icon correct across menu bar appearances on macOS 26/27.
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = isAutomaticMonitoring ? .systemOrange : nil
        button.toolTip = settingsToolTip

        let shouldShowTimer = coordinator.isActive &&
            coordinator.settings.selectedMode == .timer &&
            coordinator.settings.showTimerInMenuBar
        button.title = shouldShowTimer ? coordinator.formattedRemainingTime : ""
        button.imagePosition = shouldShowTimer ? .imageLeading : .imageOnly
        button.setAccessibilityValue(accessibilityStatus)
    }

    private var iconName: String {
        guard coordinator.isActive else {
            return "MenuBarCup"
        }

        switch coordinator.currentExecutionState {
        case .idle:
            return "MenuBarCupActive"
        case .awakeLidOpen:
            return "MenuBarCupActive"
        case .awakeClosedLidCooling:
            return "MenuBarCupActive"
        case .normalClamshell:
            return "MenuBarCupActive"
        }
    }

    private var isAutomaticMonitoring: Bool {
        switch coordinator.settings.selectedMode {
        case .whileAgentRunning:
            return coordinator.settings.agentMonitoringEnabled
        case .whileDownloading:
            return coordinator.settings.downloadMonitoringEnabled
        case .indefinitely, .timer:
            return false
        }
    }

    private var settingsToolTip: String {
        if coordinator.settings.selectedMode == .whileAgentRunning {
            return coordinator.settings.agentMonitoringEnabled
                ? L10n.string("Left-click for menu, right-click to pause agent monitoring")
                : L10n.string("Left-click for menu, right-click to resume agent monitoring")
        }
        if coordinator.settings.selectedMode == .whileDownloading {
            return coordinator.settings.downloadMonitoringEnabled
                ? L10n.string("Left-click for menu, right-click to pause download monitoring")
                : L10n.string("Left-click for menu, right-click to resume download monitoring")
        }
        return L10n.string("Left-click for menu, right-click to toggle Awake")
    }

    private var accessibilityStatus: String {
        if coordinator.settings.selectedMode == .whileAgentRunning && !coordinator.isActive {
            return coordinator.settings.agentMonitoringEnabled
                ? L10n.string("Monitoring")
                : L10n.string("Monitoring Paused")
        }
        if coordinator.settings.selectedMode == .whileDownloading && !coordinator.isActive {
            return coordinator.settings.downloadMonitoringEnabled
                ? L10n.string("Monitoring")
                : L10n.string("Monitoring Paused")
        }
        return coordinator.isActive ? L10n.string("On") : L10n.string("Off")
    }
}
