import XCTest
@testable import awake

@MainActor
final class ScreenLockGraceManagerTests: XCTestCase {
    private final class FakeStore: ScreenLockPreferenceStore {
        var delay: Int?
        var askForPassword: Bool? = true
        var writes = 0
        var honorWrites = true

        func copyDelay() -> Int? { delay }
        func copyAskForPassword() -> Bool? { askForPassword }

        @discardableResult
        func setDelay(_ delay: Int?) -> Bool {
            writes += 1
            if honorWrites { self.delay = delay }
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

    private func makeManager(_ store: FakeStore) -> ScreenLockGraceManager {
        ScreenLockGraceManager(store: store, defaults: defaults)
    }

    func testApplyCapturesOriginalOnceAndWritesAppliedDelay() {
        let store = FakeStore()
        store.delay = 5
        let manager = makeManager(store)

        manager.update(sessionActive: true, enabled: true)
        XCTAssertEqual(store.delay, ScreenLockGraceManager.appliedDelay)
        XCTAssertTrue(manager.isGraceActive)
        XCTAssertNil(manager.lastError)

        // A second heartbeat must not rewrite or re-capture.
        manager.update(sessionActive: true, enabled: true)
        XCTAssertEqual(store.writes, 1)
        XCTAssertEqual(store.delay, ScreenLockGraceManager.appliedDelay)
    }

    func testStopRestoresOriginalValue() {
        let store = FakeStore()
        store.delay = 5
        let manager = makeManager(store)

        manager.update(sessionActive: true, enabled: true)
        manager.update(sessionActive: false, enabled: true)

        XCTAssertEqual(store.delay, 5)
        XCTAssertFalse(manager.isGraceActive)
    }

    func testRestoreRemovesKeyWhenOriginallyAbsent() {
        let store = FakeStore()
        store.delay = nil
        let manager = makeManager(store)

        manager.update(sessionActive: true, enabled: true)
        XCTAssertEqual(store.delay, ScreenLockGraceManager.appliedDelay)
        manager.update(sessionActive: false, enabled: true)
        XCTAssertNil(store.delay)
    }

    func testStaleMarkerIsRecoveredAtLaunch() {
        let store = FakeStore()
        store.delay = ScreenLockGraceManager.appliedDelay
        defaults.set(true, forKey: "pmgwork.awake.lockGraceApplied")
        defaults.set(5, forKey: "pmgwork.awake.lockGraceOriginalDelay")
        defaults.set(true, forKey: "pmgwork.awake.lockGraceHadOriginal")

        _ = makeManager(store)
        XCTAssertEqual(store.delay, 5)
    }

    func testReadBackMismatchReportsUnsupported() {
        let store = FakeStore()
        store.delay = 5
        store.honorWrites = false
        let manager = makeManager(store)

        manager.update(sessionActive: true, enabled: true)

        XCTAssertFalse(manager.isGraceActive)
        XCTAssertNotNil(manager.lastError)
    }

    func testDisabledOrInactiveDoesNothing() {
        let store = FakeStore()
        store.delay = 5
        let manager = makeManager(store)

        manager.update(sessionActive: true, enabled: false)
        manager.update(sessionActive: false, enabled: true)

        XCTAssertEqual(store.writes, 0)
        XCTAssertFalse(manager.isGraceActive)
    }

    func testNoPasswordRequirementIsNoOp() {
        let store = FakeStore()
        store.delay = 5
        store.askForPassword = false
        let manager = makeManager(store)

        manager.update(sessionActive: true, enabled: true)

        XCTAssertEqual(store.writes, 0)
        XCTAssertFalse(manager.isGraceActive)
    }
}
