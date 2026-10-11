import XCTest
@testable import awake

final class LowPowerModeStateTests: XCTestCase {
    func testParsesBatteryAndACSections() {
        let output = """
        Battery Power:
         lowpowermode         1
         standby              1
         Sleep On Power Button 1
         displaysleep         2
        AC Power:
         lowpowermode         0
         displaysleep         10
        """
        XCTAssertEqual(
            LowPowerModeState.parse(pmsetCustomOutput: output),
            LowPowerModeState(key: "lowpowermode", battery: 1, ac: 0)
        )
    }

    func testParsesPowerModeOnMacsWithHighPowerMode() {
        let output = """
        Battery Power:
         powermode            0
        AC Power:
         powermode            2
        """
        XCTAssertEqual(
            LowPowerModeState.parse(pmsetCustomOutput: output),
            LowPowerModeState(key: "powermode", battery: 0, ac: 2)
        )
    }

    func testMissingSettingIsUnavailable() {
        XCTAssertNil(LowPowerModeState.parse(pmsetCustomOutput: "AC Power:\n displaysleep 10\n"))
        XCTAssertNil(LowPowerModeState.parse(pmsetCustomOutput: ""))
    }

    func testHelperArgumentsLeaveMissingSourcesUnchanged() {
        XCTAssertEqual(
            LowPowerModeState(key: "lowpowermode", battery: nil, ac: 0).helperArguments,
            ["lowpowermode", "-", "0"]
        )
    }

    func testRestorationKeepsChangesTheUserMade() {
        let saved = LowPowerModeState(key: "lowpowermode", battery: 0, ac: 0)
        XCTAssertEqual(
            saved.restoration(from: LowPowerModeState(key: "lowpowermode", battery: 1, ac: 1)),
            saved
        )
        // The user turned AC off again themselves: only battery is restored.
        XCTAssertEqual(
            saved.restoration(from: LowPowerModeState(key: "lowpowermode", battery: 1, ac: 0)),
            LowPowerModeState(key: "lowpowermode", battery: 0, ac: nil)
        )
        XCTAssertNil(saved.restoration(from: saved))
        // A source that was already in Low Power Mode needs nothing.
        XCTAssertNil(
            LowPowerModeState(key: "lowpowermode", battery: 1, ac: nil)
                .restoration(from: LowPowerModeState(key: "lowpowermode", battery: 1, ac: nil))
        )
    }
}

@MainActor
final class LowPowerModeManagerTests: XCTestCase {
    private var directory: URL!
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "pmgwork.awake.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private var invocations: URL { directory.appendingPathComponent("invocations") }
    private var stopped: URL { directory.appendingPathComponent("stopped") }

    /// A helper that records each invocation and holds until stdin closes.
    private func makeHelper() throws -> URL {
        let script = directory.appendingPathComponent("helper")
        try """
        #!/bin/sh
        echo "$*" >> '\(invocations.path)'
        test "$1" = "hold-lowpower" || exit 0
        echo ready
        read line
        touch '\(stopped.path)'
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        return script
    }

    private func recordedInvocations() -> [String] {
        ((try? String(contentsOf: invocations, encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testHoldsLowPowerModeAndRestoresOnStop() async throws {
        let manager = LowPowerModeManager(
            helperURL: try makeHelper(),
            helperCheck: { true },
            readState: { LowPowerModeState(key: "lowpowermode", battery: 0, ac: 0) },
            defaults: defaults
        )
        manager.update(requested: true)
        try await waitUntil { recordedInvocations().count == 1 }
        XCTAssertEqual(recordedInvocations(), ["hold-lowpower lowpowermode 0 0"])

        manager.update(requested: false)
        try await waitUntil { FileManager.default.fileExists(atPath: stopped.path) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: stopped.path))
        let safeToRemove = await manager.prepareForHelperRemoval()
        XCTAssertTrue(safeToRemove)
        XCTAssertNil(manager.lastError)
    }

    func testAlreadyInLowPowerModeDoesNotLaunchHelper() async throws {
        let manager = LowPowerModeManager(
            helperURL: try makeHelper(),
            helperCheck: { true },
            readState: { LowPowerModeState(key: "lowpowermode", battery: 1, ac: 1) },
            defaults: defaults
        )
        manager.update(requested: true)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(recordedInvocations(), [])
        XCTAssertNil(manager.lastError)
    }

    func testMissingHelperReportsError() async throws {
        let manager = LowPowerModeManager(
            helperURL: URL(fileURLWithPath: "/does-not-exist"),
            helperCheck: { false },
            readState: { LowPowerModeState(key: "lowpowermode", battery: 0, ac: 0) },
            defaults: defaults
        )
        manager.update(requested: true)
        try await waitUntil { manager.lastError != nil }
        XCTAssertEqual(
            manager.lastError,
            L10n.string("Install or update the helper in Permissions to use Low Power Mode with the lid closed.")
        )
        manager.update(requested: false)
        XCTAssertNil(manager.lastError)
    }

    func testRestoresSavedSettingLeftByAnEarlierSession() async throws {
        let saved = LowPowerModeState(key: "lowpowermode", battery: 0, ac: 0)
        defaults.set(try JSONEncoder().encode(saved), forKey: "pmgwork.awake.lowPowerModeSavedState")
        let manager = LowPowerModeManager(
            helperURL: try makeHelper(),
            helperCheck: { true },
            readState: { LowPowerModeState(key: "lowpowermode", battery: 1, ac: 0) },
            defaults: defaults
        )
        await manager.restoreSavedStateIfNeeded()
        XCTAssertEqual(recordedInvocations(), ["set-lowpower lowpowermode 0 -"])
        XCTAssertNil(defaults.data(forKey: "pmgwork.awake.lowPowerModeSavedState"))
    }

    func testSavedSettingIsDroppedWhenAlreadyRestored() async throws {
        let saved = LowPowerModeState(key: "lowpowermode", battery: 0, ac: 0)
        defaults.set(try JSONEncoder().encode(saved), forKey: "pmgwork.awake.lowPowerModeSavedState")
        let manager = LowPowerModeManager(
            helperURL: try makeHelper(),
            helperCheck: { true },
            readState: { saved },
            defaults: defaults
        )
        await manager.restoreSavedStateIfNeeded()
        XCTAssertEqual(recordedInvocations(), [])
        XCTAssertNil(defaults.data(forKey: "pmgwork.awake.lowPowerModeSavedState"))
    }
}
