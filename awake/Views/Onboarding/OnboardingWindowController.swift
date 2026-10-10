//
//  OnboardingWindowController.swift
//  Awake
//

import SwiftUI
import AppKit
import Combine

@MainActor
public final class OnboardingWindowController {
    public static let shared = OnboardingWindowController()
    static let contentSize = NSSize(width: 600, height: 540)

    private var window: NSWindow?
    private var languageSubscription: AnyCancellable?

    private init() {
        languageSubscription = SettingsStore.shared.$language
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.window?.title = L10n.string("Welcome to Awake") }
    }

    public func showOnboarding(coordinator: AwakeCoordinator) {
        if let existing = window {
            present(existing)
            return
        }

        let contentView = LocalizedView { OnboardingView(
            settings: coordinator.settings,
            notificationManager: NotificationManager.shared,
            eventMonitor: coordinator.eventMonitor,
            integrationManager: coordinator.hookIntegrationManager,
            closedDisplayModeManager: coordinator.closedDisplayModeManager,
            onFinished: { [weak self] in
                self?.closeOnboarding()
            }
        ) }
        let hostingController = NSHostingController(rootView: contentView)

        let newWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = L10n.string("Welcome to Awake")
        newWindow.contentViewController = hostingController
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = Delegate.shared
        Delegate.shared.owner = self

        self.window = newWindow

        present(newWindow)
    }

    private func present(_ window: NSWindow) {
        // Awake is an LSUIElement app, so it is not necessarily active during
        // its first launch. Activate before making the window key, and order it
        // forward explicitly in case another app still owns the active space.
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    public func closeOnboarding() {
        window?.close()
    }

    fileprivate func handleClosed() {
        window = nil
        // Closing the window counts as finishing, so the guide does not come
        // back on every launch. It stays available from Settings > General.
        SettingsStore.shared.completeOnboarding()
    }
}

private final class Delegate: NSObject, NSWindowDelegate {
    static let shared = Delegate()
    weak var owner: OnboardingWindowController?

    func windowWillClose(_ notification: Notification) {
        owner?.handleClosed()
    }
}
