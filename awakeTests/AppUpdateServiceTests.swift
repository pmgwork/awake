import XCTest
@testable import awake

final class AppUpdateServiceTests: XCTestCase {
    func testNormalizedVersionStripsVPrefix() {
        XCTAssertEqual(AppUpdateService.normalizedVersion(from: "v1.2.3"), "1.2.3")
        XCTAssertEqual(AppUpdateService.normalizedVersion(from: "V2.0"), "2.0")
        XCTAssertEqual(AppUpdateService.normalizedVersion(from: "1.0"), "1.0")
        XCTAssertEqual(AppUpdateService.normalizedVersion(from: "  v1.0.1  "), "1.0.1")
    }

    func testIsNewerComparesSemver() {
        XCTAssertTrue(AppUpdateService.isNewer(latest: "1.10", current: "1.9"))
        XCTAssertFalse(AppUpdateService.isNewer(latest: "1.9", current: "1.10"))
        XCTAssertTrue(AppUpdateService.isNewer(latest: "v1.0.1", current: "1.0"))
        XCTAssertTrue(AppUpdateService.isNewer(latest: "2.0.0", current: "1.9.9"))
        XCTAssertFalse(AppUpdateService.isNewer(latest: "1.0", current: "1.0"))
        XCTAssertFalse(AppUpdateService.isNewer(latest: "1.0.0", current: "1.0"))
    }

    func testStatusCodeMappingDistinguishesMissingReleaseFeed() {
        XCTAssertNil(AppUpdateService.error(forStatusCode: 200))
        XCTAssertNil(AppUpdateService.error(forStatusCode: 204))
        XCTAssertEqual(AppUpdateService.error(forStatusCode: 404), .noStableRelease)
        XCTAssertEqual(AppUpdateService.error(forStatusCode: 403), .badResponse)
        XCTAssertEqual(AppUpdateService.error(forStatusCode: 500), .badResponse)
    }
}
