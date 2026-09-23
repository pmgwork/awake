//
//  SettingsWindowController.swift
//  Awake
//
//  AppKit owns the selectable toolbar items and their persistent highlight;
//  SwiftUI continues to provide each settings pane.
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

        // The tab controller survives closing, so reopen with the tab the user
        // was last viewing instead of always falling back to General.
        let initialTab = selectedTab()
        let initialSize = paneSizes[initialTab] ?? NSSize(width: SettingsTab.contentWidth, height: 480)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = initialTab.title
        window.toolbarStyle = .preference
        window.contentViewController = tabController
        window.isReleasedWhenClosed = false
        window.delegate = self

        self.window = window

        window.setContentSize(initialSize)
        window.contentMinSize = initialSize
        window.contentMaxSize = initialSize
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureTabs() {
        if tabController.tabViewItems.isEmpty {
            tabController.tabStyle = .toolbar
            tabController.onSelectionChange = { [weak self] tab in
                self?.applySize(for: tab)
            }

            for tab in SettingsTab.allCases {
                let pane = paneView(for: tab)
                let hostingController = NSHostingController(rootView: pane)
                hostingController.sizingOptions = []
                let item = NSTabViewItem(viewController: hostingController)
                item.label = tab.title
                item.image = tab.toolbarImage
                tabController.addTabViewItem(item)
            }
        }

        // Re-measure on every show so the fixed window follows state changes
        // (active sessions, legacy custom agents) instead of the first-open state.
        for tab in SettingsTab.allCases {
            paneSizes[tab] = measure(paneView(for: tab))
        }
    }

    private func measure(_ pane: some View) -> NSSize {
        let hostingView = NSHostingView(rootView: pane)
        hostingView.frame = NSRect(x: 0, y: 0, width: SettingsTab.contentWidth, height: 0)
        hostingView.layoutSubtreeIfNeeded()
        return NSSize(
            width: SettingsTab.contentWidth,
            height: ceil(hostingView.fittingSize.height)
        )
    }

    private func selectedTab() -> SettingsTab {
        let index = tabController.selectedTabViewItemIndex
        guard SettingsTab.allCases.indices.contains(index) else { return .general }
        return SettingsTab.allCases[index]
    }

    private func applySize(for tab: SettingsTab) {
        guard let window, let size = paneSizes[tab] else { return }
        window.title = tab.title
        window.setContentSize(size)
        window.contentMinSize = size
        window.contentMaxSize = size
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
                    screenBehaviorManager: AwakeCoordinator.shared.screenBehaviorManager,
                    closedDisplayModeManager: AwakeCoordinator.shared.closedDisplayModeManager
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
                    fanController: AwakeCoordinator.shared.fanController
                )
            }
        }
        .frame(width: SettingsTab.contentWidth)
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
    }

    public func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

@MainActor
private final class SettingsTabViewController: NSTabViewController {
    var onSelectionChange: ((SettingsTab) -> Void)?

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)

        guard let index = tabViewItems.firstIndex(where: { $0 === tabViewItem }),
              SettingsTab.allCases.indices.contains(index) else { return }
        onSelectionChange?(SettingsTab.allCases[index])
    }
}
