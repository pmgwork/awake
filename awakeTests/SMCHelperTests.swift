import XCTest
import IOKit.ps
@testable import awake

final class SMCHelperTests: XCTestCase {
    func testAutomaticCoolingFollowsKeepAwakeRatherThanAgentActivity() {
        let closed = DisplayBehaviorPolicy(lidClosed: true, hasExternalDisplay: false)
        // Timer, indefinite, download and agent sessions all use the same active state.
        XCTAssertTrue(closed.requestsAutomaticCooling(keepAwakeActive: true, onlyOnACPower: false, isOnACPower: false))
        XCTAssertFalse(closed.requestsAutomaticCooling(keepAwakeActive: false, onlyOnACPower: false, isOnACPower: true))
        XCTAssertFalse(closed.requestsAutomaticCooling(keepAwakeActive: true, onlyOnACPower: true, isOnACPower: false))
        XCTAssertTrue(closed.requestsAutomaticCooling(keepAwakeActive: true, onlyOnACPower: true, isOnACPower: true))
        for policy in [DisplayBehaviorPolicy(lidClosed: false, hasExternalDisplay: false),
                       DisplayBehaviorPolicy(lidClosed: true, hasExternalDisplay: true)] {
            XCTAssertFalse(policy.requestsAutomaticCooling(keepAwakeActive: true, onlyOnACPower: false, isOnACPower: true))
        }
    }

    func testNativeClamshellKeepsScreenPreventionWithoutOverridingLidSleep() {
        let policy = DisplayBehaviorPolicy(lidClosed: true, hasExternalDisplay: true)
        XCTAssertTrue(policy.allowsScreenPrevention)
        XCTAssertFalse(policy.needsClosedDisplayOverride)
        XCTAssertTrue(policy.allowsCooling(for: .forced))
        XCTAssertTrue(policy.allowsCooling(for: .timed))
        XCTAssertFalse(policy.allowsCooling(for: .whileKeepAwakeIsOn))
    }

    func testHeadlessClosedLidSuppressesScreenPreventionAndUsesOverride() {
        let policy = DisplayBehaviorPolicy(lidClosed: true, hasExternalDisplay: false)
        XCTAssertFalse(policy.allowsScreenPrevention)
        XCTAssertTrue(policy.needsClosedDisplayOverride)
        for mode in CoolingMode.allCases {
            XCTAssertTrue(policy.allowsCooling(for: mode))
        }
    }

    func testOpenLidAllowsScreenPreventionAndArmsOverrideOnlyWithoutExternalDisplay() {
        for hasExternal in [false, true] {
            let policy = DisplayBehaviorPolicy(lidClosed: false, hasExternalDisplay: hasExternal)
            XCTAssertTrue(policy.allowsScreenPrevention)
            XCTAssertEqual(policy.needsClosedDisplayOverride, !hasExternal)
            XCTAssertTrue(policy.allowsCooling(for: .forced))
            XCTAssertTrue(policy.allowsCooling(for: .timed))
            XCTAssertFalse(policy.allowsCooling(for: .whileKeepAwakeIsOn))
        }
    }

    func testClosedLidSleepPreventionRespectsOptInAndHelperAvailability() {
        let closedHeadless = DisplayBehaviorPolicy(lidClosed: true, hasExternalDisplay: false)
        XCTAssertTrue(closedHeadless.preventsClosedLidSleep(closedDisplayModeEnabled: true, helperAvailable: true))
        XCTAssertFalse(closedHeadless.preventsClosedLidSleep(closedDisplayModeEnabled: false, helperAvailable: true))
        XCTAssertFalse(closedHeadless.preventsClosedLidSleep(closedDisplayModeEnabled: true, helperAvailable: false))

        let openLid = DisplayBehaviorPolicy(lidClosed: false, hasExternalDisplay: false)
        XCTAssertFalse(openLid.preventsClosedLidSleep(closedDisplayModeEnabled: true, helperAvailable: true))

        let clamshell = DisplayBehaviorPolicy(lidClosed: true, hasExternalDisplay: true)
        XCTAssertFalse(clamshell.preventsClosedLidSleep(closedDisplayModeEnabled: true, helperAvailable: true))
    }

    func testPowerSourcesIgnoreUPSAndPreferInternalBattery() {
        let internalBattery: [String: Any] = [
            kIOPSTypeKey as String: kIOPSInternalBatteryType as String,
            kIOPSPowerSourceStateKey as String: kIOPSBatteryPowerValue as String,
            kIOPSCurrentCapacityKey as String: 42,
            kIOPSMaxCapacityKey as String: 100,
        ]
        let ups: [String: Any] = [
            kIOPSTypeKey as String: kIOPSUPSType as String,
            kIOPSPowerSourceStateKey as String: kIOPSACPowerValue as String,
            kIOPSCurrentCapacityKey as String: 100,
            kIOPSMaxCapacityKey as String: 100,
        ]
        let laptopWithUPS = PowerMonitor.parsePowerSources(
            providingSourceType: kIOPSBatteryPowerValue as String,
            descriptions: [internalBattery, ups]
        )
        XCTAssertFalse(laptopWithUPS.isOnACPower)
        XCTAssertEqual(laptopWithUPS.batteryLevel, 42)

        let desktopWithUPS = PowerMonitor.parsePowerSources(
            providingSourceType: kIOPSACPowerValue as String,
            descriptions: [ups]
        )
        XCTAssertTrue(desktopWithUPS.isOnACPower)
        XCTAssertNil(desktopWithUPS.batteryLevel)
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
        XCTAssertEqual(manager.lastError, L10n.string("Install or update the helper in Permissions to stay awake with the lid closed."))
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

    func testPermissionHintStaysHiddenBeforeFirstCheckAndDuringInstalledRecheck() async throws {
        let lock = NSLock()
        var pending: CheckedContinuation<Bool, Never>?
        func takePending() -> CheckedContinuation<Bool, Never>? {
            lock.withLock {
                defer { pending = nil }
                return pending
            }
        }

        let manager = ClosedDisplayModeManager(
            helperURL: URL(fileURLWithPath: "/does-not-exist"),
            helperCheck: {
                await withCheckedContinuation { continuation in
                    lock.withLock { pending = continuation }
                }
            }
        )
        defer { takePending()?.resume(returning: false) }

        XCTAssertFalse(manager.hasCheckedHelper)
        XCTAssertFalse(manager.needsHelperPermissionHint)

        let initialTask = Task { await manager.refreshHelperState() }
        while lock.withLock({ pending == nil }) { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(manager.isCheckingHelper)
        XCTAssertFalse(manager.needsHelperPermissionHint)

        takePending()?.resume(returning: true)
        await initialTask.value
        XCTAssertTrue(manager.hasCheckedHelper)
        XCTAssertTrue(manager.isHelperInstalled)
        XCTAssertFalse(manager.needsHelperPermissionHint)

        let recheckTask = Task { await manager.refreshHelperState() }
        while lock.withLock({ pending == nil }) { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(manager.isCheckingHelper)
        XCTAssertTrue(manager.isHelperInstalled)
        XCTAssertFalse(manager.needsHelperPermissionHint)

        takePending()?.resume(returning: false)
        await recheckTask.value
        XCTAssertFalse(manager.isHelperInstalled)
        XCTAssertTrue(manager.needsHelperPermissionHint)
    }

    func testRemovalRecoversStaleMarkerAndWaitOrderAvoidsStartupRace() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("helper")
        let marker = directory.appendingPathComponent("sleepdisabled")
        let log = directory.appendingPathComponent("events")
        try "99999\n".write(to: marker, atomically: true, encoding: .utf8)
        try """
        #!/bin/sh
        if [ "$1" = "recover-sleep" ]; then
            echo "recover-start" >> '\(log.path)'
            /bin/sleep 0.15
            rm -f '\(marker.path)'
            echo "recover-end" >> '\(log.path)'
            exit 0
        fi
        echo "hold-start" >> '\(log.path)'
        echo ready
        read line
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)

        // 1. Stale marker is recovered before allowing helper removal.
        let removalManager = ClosedDisplayModeManager(
            helperURL: script,
            helperCheck: { true },
            sleepMarkerPath: marker.path
        )
        let canRemove = await removalManager.prepareForHelperRemoval()
        XCTAssertTrue(canRemove)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))

        // 2. Startup recovery finishes before a newly requested clamshell lease starts.
        try "".write(to: log, atomically: true, encoding: .utf8)
        let raceManager = ClosedDisplayModeManager(
            helperURL: script,
            helperCheck: { true },
            sleepMarkerPath: marker.path
        )
        let recovery = Task { await raceManager.recoverSleepSettingIfNeeded() }
        try await Task.sleep(for: .milliseconds(30))
        raceManager.update(sessionActive: true, enabled: true)
        await raceManager.refreshHelperState()
        _ = await recovery.value
        for _ in 0..<100 {
            let lines = ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n")
            if lines.count >= 3 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let lines = ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        XCTAssertEqual(lines, ["recover-start", "recover-end", "hold-start"])
        raceManager.update(sessionActive: false, enabled: true)
    }
}
