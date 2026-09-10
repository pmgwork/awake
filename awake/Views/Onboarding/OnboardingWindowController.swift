//
//  OnboardingWindowController.swift
//  Awake
//

import SwiftUI
import AppKit

@MainActor
public final class OnboardingWindowController {
    public static let shared = OnboardingWindowController()

    private var window: NSWindow?

    public func showOnboarding(coordinator: AwakeCoordinator) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = OnboardingView(
            settings: coordinator.settings,
            notificationManager: NotificationManager.shared,
            eventMonitor: coordinator.eventMonitor,
            integrationManager: coordinator.hookIntegrationManager,
            onFinished: { [weak self] in
                self?.closeOnboarding()
            }
        )
        let hostingController = NSHostingController(rootView: contentView)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.contentMinSize = NSSize(width: 560, height: 500)
        newWindow.title = L10n.string("Welcome to Awake")
        newWindow.contentViewController = hostingController
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = Delegate.shared
        Delegate.shared.owner = self

        self.window = newWindow

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func closeOnboarding() {
        window?.close()
    }

    fileprivate func handleClosed() {
        window = nil
    }
}

private final class Delegate: NSObject, NSWindowDelegate {
    static let shared = Delegate()
    weak var owner: OnboardingWindowController?

    func windowWillClose(_ notification: Notification) {
        owner?.handleClosed()
    }
}
