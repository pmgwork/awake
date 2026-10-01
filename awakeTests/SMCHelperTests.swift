import XCTest
@testable import awake

final class SMCHelperTests: XCTestCase {
    func testNativeClamshellKeepsScreenPreventionWithoutOverridingLidSleep() {
        let policy = DisplayBehaviorPolicy(lidClosed: true, hasExternalDisplay: true)
        XCTAssertTrue(policy.allowsScreenPrevention)
        XCTAssertFalse(policy.needsClosedDisplayOverride)
    }

    func testHeadlessClosedLidSuppressesScreenPreventionAndUsesOverride() {
        let policy = DisplayBehaviorPolicy(lidClosed: true, hasExternalDisplay: false)
        XCTAssertFalse(policy.allowsScreenPrevention)
        XCTAssertTrue(policy.needsClosedDisplayOverride)
    }

    func testOpenLidAllowsScreenPreventionAndArmsOverrideOnlyWithoutExternalDisplay() {
        for hasExternal in [false, true] {
            let policy = DisplayBehaviorPolicy(lidClosed: false, hasExternalDisplay: hasExternal)
            XCTAssertTrue(policy.allowsScreenPrevention)
            XCTAssertEqual(policy.needsClosedDisplayOverride, !hasExternal)
        }
    }

    /// The main thread must never launch the privileged helper: `waitUntilExit()`
    /// pumps the run loop and can re-enter AppKit/SwiftUI from a view update.
    @MainActor
    func testHelperCheckOnMainThreadDoesNotBlock() {
        let start = Date()
        _ = SMCHelper.shared.checkHelperInstalled()
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.2)
    }

    @MainActor
    func testBackgroundRefreshMatchesCachedCheck() async {
        let refreshed = await SMCHelper.shared.refreshHelperInstallState()
        XCTAssertEqual(SMCHelper.shared.checkHelperInstalled(), refreshed)
    }
}


@MainActor
final class ClosedDisplayModeManagerTests: XCTestCase {
    func testMissingAuthorizationDoesNotLaunchHelper() async throws {
        let manager = ClosedDisplayModeManager(
            helperURL: URL(fileURLWithPath: "/does-not-exist"),
            helperCheck: { false }
        )
        manager.update(sessionActive: true, enabled: true)
        await manager.refreshHelperState()
        XCTAssertFalse(manager.isHelperInstalled)
        XCTAssertEqual(manager.lastError, L10n.string("Install or update the helper to keep your Mac awake with the lid closed."))
        manager.update(sessionActive: false, enabled: true)
        XCTAssertNil(manager.lastError)
    }

    func testAuthorizationRefreshRetriesRequestedSessionAndStopClosesLease() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("helper")
        let started = directory.appendingPathComponent("started")
        let stopped = directory.appendingPathComponent("stopped")
        try """
        #!/bin/sh
        test "$1" = "hold-clamshell" || exit 64
        touch '\(started.path)'
        echo ready
        read line
        touch '\(stopped.path)'
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        var authorized = false
        let manager = ClosedDisplayModeManager(helperURL: script, helperCheck: { authorized })
        manager.update(sessionActive: true, enabled: true)
        await manager.refreshHelperState()
        XCTAssertNotNil(manager.lastError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: started.path))
        authorized = true
        await manager.refreshHelperState()
        XCTAssertTrue(manager.isHelperInstalled)
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: started.path) && manager.lastError == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: started.path))
        XCTAssertNil(manager.lastError)
        manager.update(sessionActive: false, enabled: true)
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: stopped.path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: stopped.path))
    }

    func testRemovalWaitsForRestorationAndRefusesFailedRestoration() async throws {
        for exitStatus in [0, 9] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let script = directory.appendingPathComponent("helper")
            let started = directory.appendingPathComponent("started")
            let restored = directory.appendingPathComponent("restored")
            try """
            #!/bin/sh
            touch '\(started.path)'
            echo ready
            read line
            /bin/sleep 0.15
            touch '\(restored.path)'
            exit \(exitStatus)
            """.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            let manager = ClosedDisplayModeManager(helperURL: script, helperCheck: { true })
            manager.update(sessionActive: true, enabled: true)
            await manager.refreshHelperState()
            for _ in 0..<100 {
                if FileManager.default.fileExists(atPath: started.path) { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: started.path))
            let safeToRemove = await manager.prepareForHelperRemoval()
            XCTAssertTrue(FileManager.default.fileExists(atPath: restored.path))
            XCTAssertEqual(safeToRemove, exitStatus == 0)
            if exitStatus != 0 {
                // Failure remains meaningful after the termination callback
                // has cleared the process reference.
                try await Task.sleep(for: .milliseconds(100))
                let retrySafe = await manager.prepareForHelperRemoval()
                XCTAssertFalse(retrySafe)
            }
        }
    }

    func testStoppingDuringAuthorizationCheckDoesNotStartLease() async {
        var continuation: CheckedContinuation<Bool, Never>?
        let manager = ClosedDisplayModeManager(
            helperURL: URL(fileURLWithPath: "/does-not-exist"),
            helperCheck: { await withCheckedContinuation { continuation = $0 } }
        )
        manager.update(sessionActive: true, enabled: true)
        while continuation == nil { await Task.yield() }
        manager.update(sessionActive: false, enabled: true)
        continuation?.resume(returning: true)
        while manager.isCheckingHelper { await Task.yield() }
        XCTAssertTrue(manager.isHelperInstalled)
        XCTAssertNil(manager.lastError)
    }
}
