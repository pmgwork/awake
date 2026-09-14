import XCTest
@testable import awake

final class SMCHelperTests: XCTestCase {
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
