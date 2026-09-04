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
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = L10n.string("Left-click for menu, right-click to toggle Awake")
        button.setAccessibilityLabel("Awake")
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(coordinator: coordinator) { [weak self] in
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
            coordinator.toggleKeepAwake()
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            resizePopoverToFitContent()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
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
        image?.isTemplate = true
        image?.size = NSSize(width: 19.5, height: 15.5)
        button.image = image

        let shouldShowTimer = coordinator.isActive &&
            coordinator.settings.selectedMode == .timer &&
            coordinator.settings.showTimerInMenuBar
        button.title = shouldShowTimer ? coordinator.formattedRemainingTime : ""
        button.imagePosition = shouldShowTimer ? .imageLeading : .imageOnly
        button.setAccessibilityValue(coordinator.isActive ? L10n.string("On") : L10n.string("Off"))
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
}
