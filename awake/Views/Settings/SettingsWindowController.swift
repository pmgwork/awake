//
//  SettingsWindowController.swift
//  Awake
//
//  AppKit owns the selectable toolbar items and their persistent highlight;
//  SwiftUI continues to provide each settings pane.
//

import SwiftUI
import AppKit
import Combine

@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowController()

    private(set) var window: NSWindow?
    private var tabController: SettingsTabViewController?
    private var paneControllers: [SettingsTab: SettingsPaneHostingController] = [:]
    private var paneSizes: [SettingsTab: NSSize] = [:]
    private var lastSelectedTab: SettingsTab = .general
    private var languageSubscription: AnyCancellable?

    private override init() {
        super.init()
        languageSubscription = SettingsStore.shared.$language
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshLanguage() }
    }

    private func refreshLanguage() {
        guard let tabController else { return }
        for (tab, item) in zip(SettingsTab.allCases, tabController.tabViewItems) {
            item.label = tab.title
            item.image = tab.toolbarImage
        }
        // NSTabViewController creates native toolbar items whose labels also
        // need updating after the SwiftUI panes have changed language.
        if let toolbar = window?.toolbar {
            for (item, tab) in zip(toolbar.items.filter { $0.itemIdentifier != .flexibleSpace }, SettingsTab.allCases) {
                item.label = tab.title
                item.paletteLabel = tab.title
                item.toolTip = tab.title
            }
        }
        for tab in SettingsTab.allCases {
            updateMeasuredSize(for: tab)
        }
        applySize(for: selectedTab())
    }

    /// Opens the window on `tab`, or on the last viewed tab when nil.
    func show(tab: SettingsTab? = nil) {
        if let window, let tabController {
            if let tab, let index = SettingsTab.allCases.firstIndex(of: tab) {
                lastSelectedTab = tab
                tabController.selectedTabViewItemIndex = index
            }
            let currentTab = selectedTab()
            updateMeasuredSize(for: currentTab)
            applySize(for: currentTab)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let targetTab = tab ?? lastSelectedTab
        lastSelectedTab = targetTab

        let controller = makeTabController(selecting: targetTab)
        self.tabController = controller

        let initialSize = paneSizes[targetTab] ?? NSSize(width: SettingsTab.contentWidth, height: 480)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = targetTab.title
        window.toolbarStyle = .preference
        window.contentViewController = controller
        window.isReleasedWhenClosed = false
        window.delegate = self

        self.window = window

        applySize(for: targetTab, anchorTopEdge: false)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeTabController(selecting initialTab: SettingsTab) -> SettingsTabViewController {
        let controller = SettingsTabViewController()
        controller.tabStyle = .toolbar
        controller.onWillSelect = { [weak self] tab in
            self?.handleTabSelection(tab)
        }
        controller.onDidSelect = { [weak self] tab in
            self?.handleTabSelection(tab)
        }

        paneControllers.removeAll()
        paneSizes.removeAll()

        for tab in SettingsTab.allCases {
            let hostingController = SettingsPaneHostingController(rootView: AnyView(paneView(for: tab)))
            hostingController.sizingOptions = []
            hostingController.view.frame = NSRect(x: 0, y: 0, width: SettingsTab.contentWidth, height: 0)
            hostingController.onPreferredHeightChange = { [weak self] height in
                self?.handlePreferredHeightChange(height, for: tab)
            }
            paneControllers[tab] = hostingController
            paneSizes[tab] = size(forHeight: measureHeight(for: tab, controller: hostingController))

            let item = NSTabViewItem(viewController: hostingController)
            item.label = tab.title
            item.image = tab.toolbarImage
            controller.addTabViewItem(item)
        }

        if let index = SettingsTab.allCases.firstIndex(of: initialTab) {
            controller.selectedTabViewItemIndex = index
        }
        return controller
    }

    private func handleTabSelection(_ tab: SettingsTab) {
        lastSelectedTab = tab
        updateMeasuredSize(for: tab)
        applySize(for: tab)
    }

    private func handlePreferredHeightChange(_ height: CGFloat, for tab: SettingsTab) {
        let newSize = size(forHeight: height)
        let previousSize = paneSizes[tab]
        paneSizes[tab] = newSize

        guard tab == selectedTab(),
              let window,
              previousSize == nil || abs((previousSize?.height ?? 0) - newSize.height) > 0.5 || abs(window.contentLayoutRect.height - newSize.height) > 0.5 else {
            return
        }

        // Defer window resizing out of viewDidLayout so AppKit does not re-enter
        // layout synchronously while updating constraints.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.selectedTab() == tab else { return }
            self.applySize(for: tab)
        }
    }

    private func updateMeasuredSize(for tab: SettingsTab) {
        let height = measureHeight(for: tab, controller: paneControllers[tab])
        paneSizes[tab] = size(forHeight: height)
    }

    private func measureHeight(for tab: SettingsTab, controller: SettingsPaneHostingController?) -> CGFloat {
        if let controller {
            let controllerHeight = controller.measureHeight()
            if controllerHeight > 0 {
                return controllerHeight
            }
        }
        let hostingView = NSHostingView(rootView: paneView(for: tab))
        hostingView.frame = NSRect(x: 0, y: 0, width: SettingsTab.contentWidth, height: 0)
        hostingView.layoutSubtreeIfNeeded()
        return ceil(hostingView.fittingSize.height)
    }

    private func size(forHeight height: CGFloat) -> NSSize {
        let maxHeight = maxContentHeight()
        let resolvedHeight = max(1, min(ceil(height), maxHeight))
        return NSSize(width: SettingsTab.contentWidth, height: resolvedHeight)
    }

    private func maxContentHeight() -> CGFloat {
        guard let visibleHeight = (window?.screen ?? NSScreen.main)?.visibleFrame.height else {
            return .greatestFiniteMagnitude
        }
        let chromeHeight = window.map { max(0, $0.frame.height - $0.contentLayoutRect.height) } ?? 88
        return max(320, floor(visibleHeight - chromeHeight - 24))
    }

    private func selectedTab() -> SettingsTab {
        guard let tabController else { return lastSelectedTab }
        let index = tabController.selectedTabViewItemIndex
        guard SettingsTab.allCases.indices.contains(index) else { return lastSelectedTab }
        return SettingsTab.allCases[index]
    }

    private func applySize(for tab: SettingsTab, anchorTopEdge: Bool = true) {
        guard let window, let size = paneSizes[tab] else { return }
        window.title = tab.title
        let topY = window.frame.maxY
        window.contentMinSize = size
        window.contentMaxSize = size
        window.setContentSize(size)
        if anchorTopEdge, abs(window.frame.maxY - topY) > 0.5 {
            window.setFrameOrigin(NSPoint(x: window.frame.origin.x, y: topY - window.frame.height))
        }
    }

    private func paneView(for tab: SettingsTab) -> some View {
        LocalizedView {
            switch tab {
            case .general:
                GeneralSettingsView(
                    settings: AwakeCoordinator.shared.settings,
                    notificationManager: NotificationManager.shared,
                    updater: AppUpdater.shared
                )
            case .keepAwake:
                KeepAwakeSettingsView(
                    settings: AwakeCoordinator.shared.settings,
                    screenBehaviorManager: AwakeCoordinator.shared.screenBehaviorManager,
                    closedDisplayModeManager: AwakeCoordinator.shared.closedDisplayModeManager,
                    lowPowerModeManager: AwakeCoordinator.shared.lowPowerModeManager
                )
            case .monitoring:
                MonitoringSettingsView(
                    settings: AwakeCoordinator.shared.settings,
                    integrationManager: AwakeCoordinator.shared.hookIntegrationManager
                )
            case .cooling:
                CoolingSettingsView(
                    settings: AwakeCoordinator.shared.settings,
                    fanController: AwakeCoordinator.shared.fanController,
                    closedDisplayModeManager: AwakeCoordinator.shared.closedDisplayModeManager
                )
            case .permissions:
                PermissionsSettingsView(
                    closedDisplayModeManager: AwakeCoordinator.shared.closedDisplayModeManager
                )
            }
        }
        .frame(width: SettingsTab.contentWidth)
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
    }

    public func windowWillClose(_ notification: Notification) {
        lastSelectedTab = selectedTab()
        (notification.object as? NSWindow)?.contentViewController = nil
        tabController = nil
        paneControllers.removeAll()
        paneSizes.removeAll()
        window = nil
    }
}

@MainActor
private final class SettingsPaneHostingController: NSHostingController<AnyView> {
    var onPreferredHeightChange: ((CGFloat) -> Void)?
    private var lastReportedHeight: CGFloat = 0
    private weak var observedDocumentView: NSView?
    private var documentFrameObserver: NSObjectProtocol?

    deinit {
        if let documentFrameObserver {
            NotificationCenter.default.removeObserver(documentFrameObserver)
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        attachDocumentObserverIfNeeded()
        reportCurrentHeightIfNeeded()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        attachDocumentObserverIfNeeded()
        reportCurrentHeightIfNeeded()
    }

    private func attachDocumentObserverIfNeeded() {
        guard let documentView = findScrollView(in: view)?.documentView,
              documentView !== observedDocumentView else {
            return
        }
        if let documentFrameObserver {
            NotificationCenter.default.removeObserver(documentFrameObserver)
        }
        observedDocumentView = documentView
        documentView.postsFrameChangedNotifications = true
        documentFrameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: documentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reportCurrentHeightIfNeeded()
            }
        }
    }

    func measureHeight() -> CGFloat {
        view.layoutSubtreeIfNeeded()
        let fittingHeight = ceil(view.fittingSize.height)
        if fittingHeight > 0 {
            return fittingHeight
        }
        attachDocumentObserverIfNeeded()
        return observedDocumentView.map { ceil($0.frame.height) } ?? 0
    }

    private func reportCurrentHeightIfNeeded() {
        let measured = measureHeight()
        guard measured > 0, abs(measured - lastReportedHeight) > 0.5 else { return }
        lastReportedHeight = measured
        onPreferredHeightChange?(measured)
    }

    private func findScrollView(in root: NSView) -> NSScrollView? {
        if let scrollView = root as? NSScrollView {
            return scrollView
        }
        for subview in root.subviews {
            if let found = findScrollView(in: subview) {
                return found
            }
        }
        return nil
    }
}

@MainActor
private final class SettingsTabViewController: NSTabViewController {
    var onWillSelect: ((SettingsTab) -> Void)?
    var onDidSelect: ((SettingsTab) -> Void)?

    override func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, willSelect: tabViewItem)

        guard let index = tabViewItems.firstIndex(where: { $0 === tabViewItem }),
              SettingsTab.allCases.indices.contains(index) else { return }
        onWillSelect?(SettingsTab.allCases[index])
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)

        guard let index = tabViewItems.firstIndex(where: { $0 === tabViewItem }),
              SettingsTab.allCases.indices.contains(index) else { return }
        onDidSelect?(SettingsTab.allCases[index])
    }
}
