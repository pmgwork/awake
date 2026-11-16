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
final class AwakeAppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = AwakeCoordinator.shared
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private var popoverContentSizeObservation: NSKeyValueObservation?
    private var statusButtonAppearanceObservation: NSKeyValueObservation?
    private static let statusIconSize = NSSize(width: 21, height: 16.8)

    func applicationWillTerminate(_ notification: Notification) {
        AfterEffectsRenderIntegration.shared.setEnabled(false)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        CLIService.shared.start()
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
        if ProcessInfo.processInfo.arguments.contains("--show-menu") {
            DispatchQueue.main.async { [weak self] in
                guard let self, let button = self.statusItem.button else { return }
                self.showPopover(from: button)
            }
        }
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

        if let button = statusItem.button {
            statusButtonAppearanceObservation = button.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.updateStatusItem()
                }
            }
        }
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
            showPopover(from: sender)
        }
    }

    private func showPopover(from button: NSStatusBarButton) {
        NSApp.activate(ignoringOtherApps: true)
        resizePopoverToFitContent()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
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

        button.image = Self.statusIcon(
            keepAwakeState: keepAwakeIconState,
            isCoolingActive: coordinator.isForcedCoolingActive,
            appearance: button.effectiveAppearance
        )
        button.toolTip = settingsToolTip
        button.setAccessibilityValue(accessibilityStatus)
    }

    enum KeepAwakeIconState {
        case inactive
        case manual
        case automatic
    }

    static func statusIcon(
        keepAwakeState: KeepAwakeIconState,
        isCoolingActive: Bool,
        appearance: NSAppearance
    ) -> NSImage? {
        // Named images are cached; keep size and rendering changes local.
        guard let image = NSImage(named: NSImage.Name("MenuBarCup"))?.copy() as? NSImage else {
            return nil
        }
        image.size = statusIconSize
        image.isTemplate = true

        // When inactive or monochrome automatic Keep Awake (without cooling),
        // return a template image so AppKit handles menu bar tinting natively.
        if keepAwakeState == .inactive && !isCoolingActive {
            return image
        }

        let isTemplateOnly = keepAwakeState != .manual && !isCoolingActive
        var labelColor = NSColor.labelColor
        var coffeeColor = NSColor.systemOrange
        var coolingColor = NSColor.systemBlue
        if !isTemplateOnly {
            appearance.performAsCurrentDrawingAppearance {
                labelColor = NSColor.labelColor.usingColorSpace(.sRGB) ?? .labelColor
                let rawCoffee: NSColor = switch keepAwakeState {
                case .manual: .systemOrange
                case .automatic: .labelColor
                case .inactive: .clear
                }
                coffeeColor = rawCoffee.usingColorSpace(.sRGB) ?? rawCoffee
                coolingColor = NSColor.systemBlue.usingColorSpace(.sRGB) ?? .systemBlue
            }
        }

        // Source SVG viewBox is 20x16; scale coordinates into `statusIconSize`.
        let scale = statusIconSize.width / 20.0
        let composed = NSImage(size: statusIconSize, flipped: true) { rect in
            image.draw(in: rect)
            if !isTemplateOnly {
                labelColor.setFill()
                rect.fill(using: .sourceAtop)
            }

            if keepAwakeState != .inactive {
                let coffeeRect = NSRect(
                    x: (8.2 - 4.55) * scale,
                    y: (5.1 - 1.9) * scale,
                    width: 9.1 * scale,
                    height: 3.8 * scale
                )
                (isTemplateOnly ? NSColor.black : coffeeColor).setFill()
                NSBezierPath(ovalIn: coffeeRect).fill()
            }

            if isCoolingActive {
                let radius: CGFloat = 1.65 * scale
                let dotRect = NSRect(
                    x: 17.8 * scale - radius,
                    y: 2.6 * scale - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                coolingColor.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }

            return true
        }
        composed.isTemplate = isTemplateOnly
        return composed
    }

    private var keepAwakeIconState: KeepAwakeIconState {
        guard coordinator.isActive else { return .inactive }
        return coordinator.isManualKeepAwakeActive ? .manual : .automatic
    }

    private var isAutomaticMonitoring: Bool {
        coordinator.settings.agentMonitoringEnabled
            || coordinator.settings.downloadMonitoringEnabled
            || coordinator.settings.renderKeepAwakeEnabled
    }

    private var settingsToolTip: String {
        L10n.string("Click to open the menu. Right-click to start or stop manual Keep Awake.")
    }

    private var accessibilityStatus: String {
        if coordinator.isActive { return L10n.string("On") }
        return isAutomaticMonitoring ? L10n.string("Waiting for Activity") : L10n.string("Off")
    }
}
