//
//  SettingsWindowController.swift
//  Awake
//

import SwiftUI
import AppKit

public final class SettingsWindowController: NSObject, NSToolbarDelegate {
    public static let shared = SettingsWindowController()

    private var window: NSWindow?
    private let selection = SettingsTabSelection()

    public func showSettings(coordinator: AwakeCoordinator) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = SettingsView(coordinator: coordinator, selection: selection)
        let hostingController = NSHostingController(rootView: contentView)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.minSize = NSSize(width: 520, height: 520)
        newWindow.title = L10n.string("Awake Settings")
        // Preference style shows the title above an icon-and-label toolbar,
        // matching the system settings look.
        newWindow.toolbarStyle = .preference

        let toolbar = NSToolbar(identifier: "AwakeSettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.selectedItemIdentifier = selection.tab.toolbarIdentifier
        newWindow.toolbar = toolbar

        newWindow.contentViewController = hostingController
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = WindowDelegate.shared

        self.window = newWindow

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func closeSettings() {
        window?.close()
    }

    // MARK: - NSToolbarDelegate

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.toolbarIdentifier)
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.toolbarIdentifier)
    }

    public func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let tab = SettingsTab(toolbarIdentifier: itemIdentifier) else { return nil }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.title
        item.paletteLabel = tab.title
        item.toolTip = tab.title
        item.image = NSImage(systemSymbolName: tab.systemImage, accessibilityDescription: tab.title)
        item.target = self
        item.action = #selector(selectTab(_:))
        return item
    }

    @objc private func selectTab(_ sender: NSToolbarItem) {
        guard let tab = SettingsTab(toolbarIdentifier: sender.itemIdentifier) else { return }
        selection.tab = tab
        window?.toolbar?.selectedItemIdentifier = sender.itemIdentifier
    }
}

private final class WindowDelegate: NSObject, NSWindowDelegate {
    static let shared = WindowDelegate()

    func windowWillClose(_ notification: Notification) {
        // Window closed
    }
}
