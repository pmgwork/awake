import XCTest
@testable import awake

final class CompletionGracePeriodTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testRepeatedIdleUpdatesDoNotExtendDeadline() {
        var grace = CompletionGracePeriod()
        grace.update(isRunning: false, now: start)
        grace.update(isRunning: false, now: start.addingTimeInterval(120))
        XCTAssertEqual(grace.remainingSeconds(duration: 180, now: start.addingTimeInterval(120)), 60)
        XCTAssertEqual(grace.remainingSeconds(duration: 180, now: start.addingTimeInterval(180)), 0)
        XCTAssertEqual(grace.remainingSeconds(duration: 180, now: start.addingTimeInterval(600)), 0)
    }

    func testResumedActivityCancelsDeadlineAndNextCompletionGetsFullGrace() {
        var grace = CompletionGracePeriod()
        grace.update(isRunning: false, now: start)
        grace.update(isRunning: true, now: start.addingTimeInterval(60))
        XCTAssertNil(grace.endDate(duration: 180))
        grace.update(isRunning: false, now: start.addingTimeInterval(120))
        XCTAssertEqual(grace.remainingSeconds(duration: 180, now: start.addingTimeInterval(120)), 180)
    }

    func testDisabledGraceAndSettingsChangesApplyImmediately() {
        var grace = CompletionGracePeriod()
        grace.update(isRunning: false, now: start)
        XCTAssertEqual(grace.remainingSeconds(duration: 0, now: start), 0)
        XCTAssertEqual(grace.remainingSeconds(duration: 60, now: start.addingTimeInterval(90)), 0)
        XCTAssertEqual(grace.remainingSeconds(duration: 300, now: start.addingTimeInterval(90)), 210)
    }

    func testManualResetClearsPendingDeadline() {
        var grace = CompletionGracePeriod()
        grace.update(isRunning: false, now: start)
        grace.reset()
        XCTAssertNil(grace.endDate(duration: 180))
        XCTAssertEqual(grace.remainingSeconds(duration: 180, now: start), 0)
    }
}
