import XCTest
@testable import awake

@MainActor
final class LegacyScreenLockRecoveryTests: XCTestCase {
    private final class FakeStore: LegacyScreenLockPreferenceStore {
        var delay: Int? = 2_147_483_647
        var writes = 0
        var writeSucceeds = true

        func setDelay(_ delay: Int?) -> Bool {
            writes += 1
            guard writeSucceeds else { return false }
            self.delay = delay
            return true
        }
    }

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

    private func markOverride(original: Int?) {
        defaults.set(true, forKey: "pmgwork.awake.lockGraceApplied")
        defaults.set(original != nil, forKey: "pmgwork.awake.lockGraceHadOriginal")
        defaults.set(original, forKey: "pmgwork.awake.lockGraceOriginalDelay")
    }

    func testRestoresSavedDelayAtLaunchWithoutReapplying() {
        let store = FakeStore()
        markOverride(original: 5)
        let recovery = LegacyScreenLockRecovery(store: store, defaults: defaults)
        recovery.restoreIfNeeded()
        XCTAssertEqual(store.delay, 5)
        XCTAssertEqual(store.writes, 1)
        XCTAssertNil(defaults.object(forKey: "pmgwork.awake.lockGraceApplied"))
        XCTAssertNil(defaults.object(forKey: "pmgwork.awake.lockGraceHadOriginal"))
        XCTAssertNil(defaults.object(forKey: "pmgwork.awake.lockGraceOriginalDelay"))
    }

    func testRestoresAbsenceOfOriginalPreference() {
        let store = FakeStore()
        markOverride(original: nil)
        _ = LegacyScreenLockRecovery(store: store, defaults: defaults)
        XCTAssertNil(store.delay)
        XCTAssertFalse(defaults.bool(forKey: "pmgwork.awake.lockGraceApplied"))
    }

    func testWithoutLegacyMarkerDoesNotTouchSystemPreference() {
        let store = FakeStore()
        store.delay = 5
        let recovery = LegacyScreenLockRecovery(store: store, defaults: defaults)
        recovery.restoreIfNeeded()
        XCTAssertEqual(store.writes, 0)
        XCTAssertEqual(store.delay, 5)
    }

    func testFailedRestorationKeepsMarkerUntilRetrySucceeds() {
        let store = FakeStore()
        store.writeSucceeds = false
        markOverride(original: 5)
        let recovery = LegacyScreenLockRecovery(store: store, defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: "pmgwork.awake.lockGraceApplied"))
        XCTAssertEqual(store.delay, 2_147_483_647)
        store.writeSucceeds = true
        recovery.restoreIfNeeded()
        XCTAssertEqual(store.delay, 5)
        XCTAssertFalse(defaults.bool(forKey: "pmgwork.awake.lockGraceApplied"))
    }

    func testMissingSavedDelayPreservesMarkerAndDoesNotGuess() {
        let store = FakeStore()
        markOverride(original: 5)
        defaults.removeObject(forKey: "pmgwork.awake.lockGraceOriginalDelay")
        _ = LegacyScreenLockRecovery(store: store, defaults: defaults)
        XCTAssertEqual(store.writes, 0)
        XCTAssertTrue(defaults.bool(forKey: "pmgwork.awake.lockGraceApplied"))
    }
}
