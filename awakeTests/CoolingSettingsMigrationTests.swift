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

    func testLegacyAutomaticSelectionDoesNotEnableOtherCondition() {
        for mode in KeepAwakeModeType.allCases {
            for enabled in [false, true] {
                defaults.set(mode.rawValue, forKey: "pmgwork.awake.selectedMode")
                defaults.set(enabled, forKey: "pmgwork.awake.agentMonitoringEnabled")
                defaults.set(enabled, forKey: "pmgwork.awake.downloadMonitoringEnabled")
                let state = SettingsStore.storedKeepAwakeState(in: defaults, isExistingInstall: true)
                XCTAssertEqual(state.agent, mode == .whileAgentRunning && enabled)
                XCTAssertEqual(state.download, mode == .whileDownloading && enabled)
                XCTAssertEqual(state.mode, mode == .timer ? .timer : .indefinitely)
            }
        }
    }

    func testIndependentMonitoringMigrationDefaultsAndRelaunch() {
        let fresh = SettingsStore.storedKeepAwakeState(in: defaults, isExistingInstall: false)
        XCTAssertTrue(fresh.agent)
        XCTAssertFalse(fresh.download)
        let existing = SettingsStore.storedKeepAwakeState(in: defaults, isExistingInstall: true)
        XCTAssertFalse(existing.agent)
        XCTAssertFalse(existing.download)
        defaults.set(true, forKey: "pmgwork.awake.independentMonitoring")
        defaults.set(true, forKey: "pmgwork.awake.agentMonitoringEnabled")
        defaults.set(true, forKey: "pmgwork.awake.downloadMonitoringEnabled")
        defaults.set("timer", forKey: "pmgwork.awake.selectedMode")
        let restored = SettingsStore.storedKeepAwakeState(in: defaults, isExistingInstall: true)
        XCTAssertTrue(restored.agent)
        XCTAssertTrue(restored.download)
        XCTAssertEqual(restored.mode, .timer)
    }

    func testIndependentKeepAwakeReasonsAndBatteryCutoff() {
        // Exhaust every combination, including finishing one condition while
        // another remains active and turning either condition off during a run.
        for bits in 0..<128 {
            let flags = (0..<7).map { bits & (1 << $0) != 0 }
            let policy = KeepAwakeActivity(manual: flags[0], agentEnabled: flags[1],
                agentRunning: flags[2], graceActive: flags[3], downloadEnabled: flags[4],
                downloading: flags[5], batteryBlocked: flags[6])
            var reasons = [String]()
            if flags[0] { reasons.append("manual") }
            if flags[1] && flags[2] { reasons.append("agent") }
            if flags[1] && flags[3] { reasons.append("grace") }
            if flags[4] && flags[5] { reasons.append("download") }
            XCTAssertEqual(policy.active, !flags[6] && !reasons.isEmpty, "flags: \(bits)")
            XCTAssertEqual(policy.agent, !flags[6] && (reasons.contains("agent") || reasons.contains("grace")))
            XCTAssertEqual(policy.download, !flags[6] && reasons.contains("download"))
        }
    }

    func testIndependentCoolingPreservesLegacyAutomaticChoice() {
        for mode in ["whileKeepAwakeIsOn", "whileLidClosed", "whileAgentRunning", "forced", "timed", "system"] {
            for armed in [false, true] {
                defaults.set(mode, forKey: "pmgwork.awake.coolingMode")
                defaults.set(armed, forKey: "pmgwork.awake.coolingArmed")
                let state = SettingsStore.storedIndependentCoolingState(in: defaults)
                XCTAssertEqual(state.mode, mode == "timed" ? .timed : .forced)
                XCTAssertEqual(state.automatic,
                    ["whileKeepAwakeIsOn", "whileLidClosed", "whileAgentRunning"].contains(mode) && armed)
            }
        }
    }

    func testIndependentCoolingRestoresBothChoicesWithoutRearmingManual() {
        XCTAssertTrue(SettingsStore.storedIndependentCoolingState(in: defaults).automatic)
        for automatic in [false, true] {
            defaults.set(automatic, forKey: "pmgwork.awake.automaticCoolingEnabled")
            for mode in [CoolingMode.forced, .timed] {
                defaults.set(mode.rawValue, forKey: "pmgwork.awake.coolingMode")
                defaults.set(true, forKey: "pmgwork.awake.coolingArmed")
                let state = SettingsStore.storedIndependentCoolingState(in: defaults)
                XCTAssertEqual(state.automatic, automatic)
                XCTAssertEqual(state.mode, mode)
                // Legacy restoration is also used by the independent migration
                // and never restores a manual fan override after a relaunch.
                XCTAssertFalse(SettingsStore.storedCoolingState(in: defaults).armed)
            }
        }
    }

    func testManualCoolingEndsWithoutCancellingAutomaticCooling() {
        for mode in [CoolingMode.forced, .timed] {
            let both = CoolingActivity(manualArmed: true, manualMode: mode,
                automaticEnabled: true, automaticRequested: true, batteryBlocked: false, helperAvailable: true)
            XCTAssertTrue(both.manual)
            XCTAssertTrue(both.automatic)
            XCTAssertEqual(both.effectiveMode, mode)
            let afterManual = CoolingActivity(manualArmed: false, manualMode: mode,
                automaticEnabled: true, automaticRequested: true, batteryBlocked: false, helperAvailable: true)
            XCTAssertTrue(afterManual.active)
            XCTAssertEqual(afterManual.effectiveMode, .whileKeepAwakeIsOn)
        }
    }

    func testIndependentCoolingConditionsAndFailSafes() {
        for bits in 0..<32 {
            let flags = (0..<5).map { bits & (1 << $0) != 0 }
            let activity = CoolingActivity(manualArmed: flags[0], manualMode: .timed,
                automaticEnabled: flags[1], automaticRequested: flags[2],
                batteryBlocked: flags[3], helperAvailable: flags[4])
            let manualExpected = flags[0] && flags[4]
            let automaticExpected = flags[1] && flags[2] && !flags[3] && flags[4]
            XCTAssertEqual(activity.manual, manualExpected)
            XCTAssertEqual(activity.automatic, automaticExpected)
            XCTAssertEqual(activity.active, manualExpected || automaticExpected)
            XCTAssertEqual(activity.effectiveMode,
                manualExpected ? .timed : automaticExpected ? .whileKeepAwakeIsOn : nil)
        }
    }

    private func storedState() -> (mode: CoolingMode, armed: Bool) {
        SettingsStore.storedCoolingState(in: defaults)
    }

    func testKeepScreenOnDefaultsToOnForNewInstalls() {
        XCTAssertTrue(SettingsStore.storedKeepScreenOn(in: defaults))
    }

    func testEitherLegacyScreenSettingKeepsTheScreenOn() {
        for (displaySleep, screenSaver, expected) in [
            (false, false, false), (true, false, true), (false, true, true), (true, true, true)
        ] {
            defaults.set(displaySleep, forKey: "pmgwork.awake.preventDisplaySleep")
            defaults.set(screenSaver, forKey: "pmgwork.awake.preventScreenSaver")
            XCTAssertEqual(SettingsStore.storedKeepScreenOn(in: defaults), expected)
        }
    }

    func testSavedKeepScreenOnWinsOverLegacySettings() {
        defaults.set(true, forKey: "pmgwork.awake.preventScreenSaver")
        defaults.set(false, forKey: "pmgwork.awake.keepScreenOn")
        XCTAssertFalse(SettingsStore.storedKeepScreenOn(in: defaults))
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

    func testNewInstallDefaultsToArmedKeepAwakeMode() {
        let state = storedState()
        XCTAssertEqual(state.mode, .whileKeepAwakeIsOn)
        XCTAssertTrue(state.armed)
    }

    func testLegacyAgentModeMigratesAndKeepsArmedStateAcrossRelaunch() {
        defaults.set("whileAgentRunning", forKey: "pmgwork.awake.coolingMode")
        defaults.set(true, forKey: "pmgwork.awake.coolingArmed")
        XCTAssertEqual(storedState().mode, .whileKeepAwakeIsOn)
        XCTAssertTrue(storedState().armed)

        defaults.set(false, forKey: "pmgwork.awake.coolingArmed")
        XCTAssertFalse(storedState().armed)
    }

    func testKeepAwakeModeKeepsPausedAndArmedChoices() {
        defaults.set("whileKeepAwakeIsOn", forKey: "pmgwork.awake.coolingMode")
        for armed in [false, true] {
            defaults.set(armed, forKey: "pmgwork.awake.coolingArmed")
            XCTAssertEqual(storedState().mode, .whileKeepAwakeIsOn)
            XCTAssertEqual(storedState().armed, armed)
        }
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

    func testRemovedSystemModeBecomesStoppedKeepAwakeMode() {
        defaults.set("system", forKey: "pmgwork.awake.coolingMode")
        defaults.set(true, forKey: "pmgwork.awake.coolingArmed")
        let state = storedState()
        XCTAssertEqual(state.mode, .whileKeepAwakeIsOn)
        XCTAssertFalse(state.armed)
    }

    func testWhileLidClosedBecomesKeepAwakeMode() {
        defaults.set("whileLidClosed", forKey: "pmgwork.awake.coolingMode")
        defaults.set(true, forKey: "pmgwork.awake.coolingArmed")
        let state = storedState()
        XCTAssertEqual(state.mode, .whileKeepAwakeIsOn)
        XCTAssertTrue(state.armed)
    }

    func testLegacyClosedLidCoolingSettingCarriesOver() {
        defaults.set(true, forKey: "pmgwork.awake.closedLidCoolingEnabled")
        XCTAssertEqual(storedState().mode, .whileKeepAwakeIsOn)
        XCTAssertTrue(storedState().armed)

        defaults.set(false, forKey: "pmgwork.awake.closedLidCoolingEnabled")
        XCTAssertEqual(storedState().mode, .whileKeepAwakeIsOn)
        XCTAssertFalse(storedState().armed)
    }
}
