import XCTest
@testable import awake

final class DownloadMonitorTests: XCTestCase {
    @MainActor
    func testNestedDownloadChangesAndMonitoringRestart() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = folder.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let monitor = DownloadMonitor(folderURL: folder, startsAutomatically: false)
        monitor.startMonitoring()
        // Let the initial scan complete before making a nested change.
        try await Task.sleep(for: .milliseconds(300))
        let partial = nested.appendingPathComponent("file.part")
        try Data().write(to: partial)
        await waitUntil { monitor.isDownloading }
        XCTAssertEqual(monitor.activeFileNames, ["file.part"])
        try FileManager.default.removeItem(at: partial)
        await waitUntil { !monitor.isDownloading }

        monitor.stopMonitoring()
        try Data().write(to: partial)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertFalse(monitor.isDownloading)
        monitor.startMonitoring()
        await waitUntil { monitor.isDownloading }
        monitor.stopMonitoring()
    }

    @MainActor
    func testFolderSwitchAndStopDiscardInFlightScan() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: first.appendingPathComponent("old.part"))
        try Data().write(to: second.appendingPathComponent("new.part"))
        let monitor = DownloadMonitor(folderURL: first, startsAutomatically: false)
        monitor.startMonitoring()
        monitor.updateFolder(path: second.path)
        await waitUntil { monitor.activeFileNames == ["new.part"] }
        monitor.reloadNow()
        monitor.stopMonitoring()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(monitor.isDownloading)
        XCTAssertTrue(monitor.activeFileNames.isEmpty)
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(condition())
    }
}
