import AppKit
import SwiftUI
import XCTest
@testable import awake

final class SettingsWindowControllerTests: XCTestCase {
    @MainActor
    func testCoolingSettingsHidesPermissionHintBeforeInitialCheck() {
        let manager = ClosedDisplayModeManager(
            helperURL: URL(fileURLWithPath: "/does-not-exist"),
            helperCheck: { false }
        )
        let view = LocalizedView {
            CoolingSettingsView(
                settings: AwakeCoordinator.shared.settings,
                fanController: AwakeCoordinator.shared.fanController,
                closedDisplayModeManager: manager
            )
        }
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: SettingsTab.contentWidth, height: 480)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertNil(findButton(titled: L10n.string("Open Permissions"), in: hostingView))
    }

    @MainActor
    func testTabSwitchLiveContentResizeAndReopen() throws {
        let settings = AwakeCoordinator.shared.settings
        let originalAgents = settings.monitoredAgents
        let controller = SettingsWindowController.shared

        defer {
            settings.monitoredAgents = originalAgents
            controller.window?.close()
        }

        controller.show(tab: .general)
        pumpRunLoop()

        let firstWindow = try XCTUnwrap(controller.window)
        let generalHeight = firstWindow.contentLayoutRect.height
        XCTAssertEqual(firstWindow.contentLayoutRect.width, SettingsTab.contentWidth, accuracy: 0.5)

        // Switch via toolbar tab selection path (simulates clicking Monitor in Settings toolbar).
        let tabVC = try XCTUnwrap(firstWindow.contentViewController as? NSTabViewController)
        let monitoringIndex = try XCTUnwrap(SettingsTab.allCases.firstIndex(of: .monitoring))
        tabVC.tabView.selectTabViewItem(at: monitoringIndex)
        pumpRunLoop()

        let baseMonitoringHeight = firstWindow.contentLayoutRect.height
        XCTAssertGreaterThan(baseMonitoringHeight, generalHeight + 20)

        if let scrollView: NSScrollView = findSubview(in: firstWindow.contentView),
           let scroller = scrollView.verticalScroller,
           !scroller.isHidden,
           scroller.isEnabled {
            XCTAssertGreaterThanOrEqual(scroller.knobProportion, 0.99)
        }

        // Adding and removing a custom agent while Monitoring is open must grow then shrink the window.
        let tempAgent = MonitoredAgent(
            id: "custom:test-\(UUID().uuidString)",
            name: "Temp Test Agent",
            processNames: ["temp-test-agent"],
            isEnabled: true,
            isPreset: false
        )
        settings.monitoredAgents.append(tempAgent)
        pumpRunLoop(duration: 0.15)

        let expandedHeight = firstWindow.contentLayoutRect.height
        XCTAssertGreaterThan(expandedHeight, baseMonitoringHeight + 20)

        settings.monitoredAgents.removeAll { $0.id == tempAgent.id }
        pumpRunLoop(duration: 0.15)

        let collapsedHeight = firstWindow.contentLayoutRect.height
        XCTAssertEqual(collapsedHeight, baseMonitoringHeight, accuracy: 2.0)

        // Closing and reopening must restore the last viewed tab with an accurate non-empty frame.
        firstWindow.close()
        pumpRunLoop()
        XCTAssertNil(controller.window)

        controller.show()
        pumpRunLoop()

        let reopenedWindow = try XCTUnwrap(controller.window)
        XCTAssertNotIdentical(reopenedWindow, firstWindow)
        let reopenedTabVC = try XCTUnwrap(reopenedWindow.contentViewController as? NSTabViewController)
        XCTAssertEqual(reopenedTabVC.selectedTabViewItemIndex, monitoringIndex)
        XCTAssertEqual(reopenedWindow.contentLayoutRect.width, SettingsTab.contentWidth, accuracy: 0.5)
        XCTAssertEqual(reopenedWindow.contentLayoutRect.height, baseMonitoringHeight, accuracy: 2.0)
    }

    @MainActor
    private func pumpRunLoop(duration: TimeInterval = 0.08) {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    private func findButton(titled title: String, in view: NSView?) -> NSButton? {
        findSubview(in: view) { ($0 as NSButton).title == title }
    }

    private func findSubview<T: NSView>(in view: NSView?, where predicate: (T) -> Bool = { _ in true }) -> T? {
        guard let view else { return nil }
        if let match = view as? T, predicate(match) {
            return match
        }
        for subview in view.subviews {
            if let found = findSubview(in: subview, where: predicate) {
                return found
            }
        }
        return nil
    }
}
