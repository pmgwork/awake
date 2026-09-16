//
//  SettingsWindowController.swift
//  Awake
//
//  Presents the settings panes in an `NSTabViewController`. The AppKit tab
//  controller owns the window toolbar, so the system draws the standard
//  settings toolbar and keeps its background stable while the pointer moves
//  over the SwiftUI forms. SwiftUI's own `Settings` scene re-renders that
//  background on hover in this app, which is why the window is built here.
//
//  Every pane is measured at its natural height, and the window is sized to
//  the selected pane so forms never scroll.
//

import SwiftUI
import AppKit

@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowController()

    private var window: NSWindow?
    private let tabController = SettingsTabViewController()
    private var paneSizes: [SettingsTab: NSSize] = [:]

    public func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        configureTabs()

        let initialSize = paneSizes[.general] ?? NSSize(width: SettingsTab.contentWidth, height: 480)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = SettingsTab.general.title
        window.toolbarStyle = .preference
        window.contentViewController = tabController
        window.isReleasedWhenClosed = false
        window.delegate = self

        self.window = window

        // Assigning the content view controller resizes the window to the
        // controller's preferred size, so the measured size is applied after.
        window.setContentSize(initialSize)
        window.contentMinSize = initialSize
        window.contentMaxSize = initialSize

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func close() {
        window?.close()
    }

    private func configureTabs() {
        guard tabController.tabViewItems.isEmpty else { return }

        tabController.tabStyle = .toolbar
        tabController.onSelectionChange = { [weak self] tab in
            self?.applySize(for: tab)
        }

        for tab in SettingsTab.allCases {
            let pane = pane(for: tab)
            let hostingController = NSHostingController(rootView: pane)
            hostingController.sizingOptions = []
            let item = NSTabViewItem(viewController: hostingController)
            item.label = tab.title
            item.image = tab.toolbarImage
            tabController.addTabViewItem(item)
            paneSizes[tab] = measure(pane)
        }
    }

    /// Measures the pane at the shared content width so the window can match it.
    ///
    /// `NSHostingController.sizeThatFits(in:)` reports an infinite height for
    /// SwiftUI forms, but an `NSHostingView` laid out at the content width
    /// reports the height the form actually needs.
    private func measure(_ pane: some View) -> NSSize {
        let hostingView = NSHostingView(rootView: pane)
        hostingView.frame = NSRect(x: 0, y: 0, width: SettingsTab.contentWidth, height: 0)
        hostingView.layoutSubtreeIfNeeded()
        return NSSize(
            width: SettingsTab.contentWidth,
            height: ceil(hostingView.fittingSize.height)
        )
    }

    private func applySize(for tab: SettingsTab) {
        guard let window, let size = paneSizes[tab] else { return }
        window.title = tab.title
        window.setContentSize(size)
        window.contentMinSize = size
        window.contentMaxSize = size
    }

    private func pane(for tab: SettingsTab) -> some View {
        paneView(for: tab)
    }

    private func paneView(for tab: SettingsTab) -> some View {
        Group {
            switch tab {
            case .general:
                GeneralSettingsView(
                    settings: AwakeCoordinator.shared.settings,
                    notificationManager: NotificationManager.shared,
                    updater: AppUpdater.shared
                )
            case .sessions:
                SessionsSettingsView(
                    settings: AwakeCoordinator.shared.settings,
                    screenBehaviorManager: AwakeCoordinator.shared.screenBehaviorManager
                )
            case .agents:
                AgentSettingsView(
                    settings: AwakeCoordinator.shared.settings,
                    eventMonitor: AwakeCoordinator.shared.eventMonitor,
                    integrationManager: AwakeCoordinator.shared.hookIntegrationManager
                )
            case .cooling:
                CoolingSettingsView(
                    settings: AwakeCoordinator.shared.settings,
                    fanController: AwakeCoordinator.shared.fanController,
                    thermalMonitor: AwakeCoordinator.shared.thermalMonitor
                )
            }
        }
        .frame(width: SettingsTab.contentWidth)
        .contentSizedVerticalScrolling()
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

private extension View {
    /// Keeps a pane from bouncing or scrolling when its content already fits.
    @ViewBuilder
    func contentSizedVerticalScrolling() -> some View {
        if #available(macOS 13.3, *) {
            scrollBounceBehavior(.basedOnSize, axes: .vertical)
        } else {
            self
        }
    }
}

/// `NSTabViewController` is its own `NSTabView` delegate, so selecting a tab is
/// observed by overriding the delegate callback instead of replacing it.
@MainActor
private final class SettingsTabViewController: NSTabViewController {
    /// Called with the pane that became visible.
    var onSelectionChange: ((SettingsTab) -> Void)?

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)

        guard let index = tabViewItems.firstIndex(where: { $0 === tabViewItem }),
              SettingsTab.allCases.indices.contains(index) else { return }
        onSelectionChange?(SettingsTab.allCases[index])
    }
}
