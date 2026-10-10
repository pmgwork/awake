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
    @ObservedObject private var settings = SettingsStore.shared

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L10n.string("Settings…", language: settings.language)) {
                    SettingsWindowController.shared.show()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

@MainActor
private final class AwakeAppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = AwakeCoordinator.shared
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private var popoverContentSizeObservation: NSKeyValueObservation?
    private var popoverAnchorWindow: NSWindow?
    private var iconOnlyButtonWidth: CGFloat?
    private var isShowingTimerInStatusItem = false
    private static let statusIconSize = NSSize(width: 21, height: 16.8)

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configurePopover()
        observeStatusChanges()
        updateStatusItem()

        // Touch the shared updater so Sparkle starts scheduled checks. The
        // schedule (and the user's preference) lives in AppUpdater.
        _ = AppUpdater.shared

        #if !DEBUG
        // Release builds only, so tests and development runs never replace
        // the bridge that the user's hooks call.
        HookIntegrationManager.shared.updateInstalledBridgeIfNeeded()
        #endif

        #if DEBUG
        // Opens a settings tab on launch so each pane can be captured.
        if let raw = UserDefaults.standard.string(forKey: "AwakeDebugSettingsTab"),
           let tab = SettingsTab(rawValue: raw) {
            DispatchQueue.main.async { SettingsWindowController.shared.show(tab: tab) }
        }
        #endif

        if !coordinator.settings.hasCompletedOnboarding {
            DispatchQueue.main.async { [weak self] in
                self?.showOnboardingIfNeeded()
            }
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

        let coordinator = self.coordinator
        let hostingController = NSHostingController(
            rootView: LocalizedView { MenuBarView(
                coordinator: coordinator,
                settings: coordinator.settings,
                popoverCloseAction: { [weak self] in
                    self?.popover.performClose(nil)
                }
            ) }
        )
        // SwiftUI only tracks its ideal size in `preferredContentSize` when
        // this option is set, and NSPopover does not follow that property on
        // its own. Observe it so rows that appear or disappear while the menu
        // is open (agent sessions, downloads) resize the popover
        // instead of clipping the controls below them.
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
        popoverContentSizeObservation = hostingController.observe(
            \.preferredContentSize,
            options: [.new]
        ) { [weak self] _, change in
            guard let self,
                  let size = change.newValue,
                  size.width > 0,
                  size.height > 0,
                  self.popover.isShown else { return }
            self.popover.contentSize = size
        }
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

        NotificationCenter.default.publisher(for: NSPopover.didCloseNotification, object: popover)
            .sink { [weak self] _ in
                self?.popoverAnchorWindow?.orderOut(nil)
                self?.statusItem.button?.highlight(false)
            }
            .store(in: &cancellables)
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            sender.highlight(false)
            coordinator.togglePrimaryAction()
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            resizePopoverToFitContent()
            showPopover(from: sender)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Shows the popover from a fixed, invisible window laid exactly over the
    /// icon. Anchoring to the status button itself makes AppKit misplace the
    /// popover when the item widens for the remaining time (it applies the
    /// button's new offset but not the window's new origin). The icon is drawn
    /// at the trailing edge (see `timerStatusImage`) and status items grow
    /// leftward, so this window keeps matching the icon.
    private func showPopover(from button: NSStatusBarButton) {
        guard let buttonWindow = button.window else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            return
        }
        if !isShowingTimerInStatusItem {
            iconOnlyButtonWidth = button.bounds.width
        }
        // Opened while the remaining time is already showing (e.g. right after
        // launch): estimate the icon-only width from the image plus padding.
        let estimatedIconWidth = Self.statusIconSize.width + 16
        let width = min(iconOnlyButtonWidth ?? estimatedIconWidth, button.bounds.width)
        let iconRect = NSRect(
            x: button.bounds.maxX - width,
            y: button.bounds.minY,
            width: width,
            height: button.bounds.height
        )
        let screenRect = buttonWindow.convertToScreen(button.convert(iconRect, to: nil))

        let anchorWindow = popoverAnchorWindow ?? {
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.isReleasedWhenClosed = false
            window.contentView = NSView()
            popoverAnchorWindow = window
            return window
        }()
        anchorWindow.setFrame(screenRect, display: false)
        anchorWindow.orderFrontRegardless()

        guard let anchorView = anchorWindow.contentView else { return }
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        button.highlight(true)
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

        let shouldShowTimer = coordinator.isActive &&
            coordinator.settings.selectedMode == .timer &&
            coordinator.settings.showTimerInMenuBar
        isShowingTimerInStatusItem = shouldShowTimer

        let icon = statusIcon()
        button.image = shouldShowTimer
            ? icon.map { timerStatusImage(icon: $0, text: coordinator.formattedRemainingTime) }
            : icon
        button.title = ""
        button.imagePosition = .imageOnly
        button.toolTip = settingsToolTip
        button.setAccessibilityValue(shouldShowTimer
            ? "\(accessibilityStatus), \(coordinator.formattedRemainingTime)"
            : accessibilityStatus)
    }

    /// Draws the remaining time and the icon into one template image. Keeping
    /// the button image-only gives the icon the same trailing padding as when
    /// no time is shown, so it does not shift when the time appears.
    private func timerStatusImage(icon: NSImage, text: String) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: NSColor.black
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let spacing: CGFloat = 4
        let size = NSSize(
            width: ceil(textSize.width) + spacing + icon.size.width,
            height: max(icon.size.height, ceil(textSize.height))
        )
        let image = NSImage(size: size, flipped: false) { rect in
            (text as NSString).draw(
                at: NSPoint(x: 0, y: (rect.height - textSize.height) / 2),
                withAttributes: attributes
            )
            icon.draw(in: NSRect(
                x: rect.maxX - icon.size.width,
                y: (rect.height - icon.size.height) / 2,
                width: icon.size.width,
                height: icon.size.height
            ))
            return true
        }
        image.isTemplate = icon.isTemplate
        return image
    }

    private func statusIcon() -> NSImage? {
        // Named images are cached; keep size and rendering changes local.
        guard let image = NSImage(named: NSImage.Name(iconName))?.copy() as? NSImage else {
            return nil
        }
        image.size = Self.statusIconSize
        image.isTemplate = true

        // Leave the status button's tint untouched so AppKit can adapt the
        // normal icon to the menu bar, independently of the app appearance.
        guard isAutomaticMonitoring else { return image }

        let tintedImage = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            NSColor.systemOrange.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        tintedImage.isTemplate = false
        return tintedImage
    }

    private var iconName: String {
        coordinator.isActive ? "MenuBarCupActive" : "MenuBarCup"
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
                ? L10n.string("Click to open the menu. Right-click to pause agent monitoring.")
                : L10n.string("Click to open the menu. Right-click to resume agent monitoring.")
        }
        if coordinator.settings.selectedMode == .whileDownloading {
            return coordinator.settings.downloadMonitoringEnabled
                ? L10n.string("Click to open the menu. Right-click to pause download monitoring.")
                : L10n.string("Click to open the menu. Right-click to resume download monitoring.")
        }
        return L10n.string("Click to open the menu. Right-click to start or stop Keep Awake.")
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
