import XCTest
@testable import awake

@MainActor
final class CoolingSettingsMigrationTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "pmgwork.awake.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func storedState() -> (mode: CoolingMode, armed: Bool) {
        SettingsStore.storedCoolingState(in: defaults)
    }

    func testSharedFanSpeedMigratesToBothCoolingSpeeds() {
        defaults.set(FanMode.aggressive.rawValue, forKey: "pmgwork.awake.coolingFanMode")
        let speeds = SettingsStore.storedCoolingFanModes(in: defaults, isExistingInstall: true)
        XCTAssertEqual(speeds.automatic, .aggressive)
        XCTAssertEqual(speeds.manual, .aggressive)
    }

    func testSeparateFanSpeedsPreserveChoicesOverLegacySpeed() {
        defaults.set(FanMode.aggressive.rawValue, forKey: "pmgwork.awake.coolingFanMode")
        defaults.set(FanMode.maximum.rawValue, forKey: "pmgwork.awake.automaticCoolingFanMode")
        defaults.set(FanMode.moderate.rawValue, forKey: "pmgwork.awake.manualCoolingFanMode")
        let speeds = SettingsStore.storedCoolingFanModes(in: defaults, isExistingInstall: true)
        XCTAssertEqual(speeds.automatic, .maximum)
        XCTAssertEqual(speeds.manual, .moderate)
    }

    func testCoolingSpeedDefaultsAndInvalidAutomaticSpeed() {
        let fresh = SettingsStore.storedCoolingFanModes(in: defaults, isExistingInstall: false)
        XCTAssertEqual(fresh.automatic, .maximum)
        XCTAssertEqual(fresh.manual, .maximum)
        defaults.set(FanMode.auto.rawValue, forKey: "pmgwork.awake.automaticCoolingFanMode")
        defaults.set(FanMode.maximum.rawValue, forKey: "pmgwork.awake.manualCoolingFanMode")
        let existing = SettingsStore.storedCoolingFanModes(in: defaults, isExistingInstall: true)
        XCTAssertEqual(existing.automatic, .aggressive)
        XCTAssertEqual(existing.manual, .maximum)
    }

    func testNewInstallDefaultsToArmedAgentMode() {
        let state = storedState()
        XCTAssertEqual(state.mode, .whileAgentRunning)
        XCTAssertTrue(state.armed)
    }

    func testAgentModeKeepsArmedStateAcrossRelaunch() {
        defaults.set("whileAgentRunning", forKey: "pmgwork.awake.coolingMode")
        defaults.set(true, forKey: "pmgwork.awake.coolingArmed")
        XCTAssertEqual(storedState().mode, .whileAgentRunning)
        XCTAssertTrue(storedState().armed)

        defaults.set(false, forKey: "pmgwork.awake.coolingArmed")
        XCTAssertFalse(storedState().armed)
    }

    func testIndefiniteAndTimedCoolingAreNotRearmedAfterRelaunch() {
        for mode in [CoolingMode.forced, .timed] {
            defaults.set(mode.rawValue, forKey: "pmgwork.awake.coolingMode")
            defaults.set(true, forKey: "pmgwork.awake.coolingArmed")
            let state = storedState()
            XCTAssertEqual(state.mode, mode)
            XCTAssertFalse(state.armed, "\(mode) should not survive a relaunch")
        }
    }

    func testRemovedSystemModeBecomesStoppedAgentMode() {
        defaults.set("system", forKey: "pmgwork.awake.coolingMode")
        defaults.set(true, forKey: "pmgwork.awake.coolingArmed")
        let state = storedState()
        XCTAssertEqual(state.mode, .whileAgentRunning)
        XCTAssertFalse(state.armed)
    }

    func testWhileLidClosedBecomesAgentMode() {
        defaults.set("whileLidClosed", forKey: "pmgwork.awake.coolingMode")
        defaults.set(true, forKey: "pmgwork.awake.coolingArmed")
        let state = storedState()
        XCTAssertEqual(state.mode, .whileAgentRunning)
        XCTAssertTrue(state.armed)
    }

    func testLegacyClosedLidCoolingSettingCarriesOver() {
        defaults.set(true, forKey: "pmgwork.awake.closedLidCoolingEnabled")
        XCTAssertEqual(storedState().mode, .whileAgentRunning)
        XCTAssertTrue(storedState().armed)

        defaults.set(false, forKey: "pmgwork.awake.closedLidCoolingEnabled")
        XCTAssertEqual(storedState().mode, .whileAgentRunning)
        XCTAssertFalse(storedState().armed)
    }
}
