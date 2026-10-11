import XCTest
@testable import awake

final class UpdateChannelTests: XCTestCase {
    func testExistingAndNewUsersDefaultToStable() {
        let name = "pmgwork.awake.update-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "pmgwork.awake.automaticallyCheckForUpdates")
        XCTAssertEqual(UpdateChannel.stored(in: defaults), .stable)
        XCTAssertFalse(defaults.bool(forKey: "pmgwork.awake.automaticallyCheckForUpdates"))
    }

    func testOptInAndOptOutPersistWithoutChangingAutomaticChecks() {
        let name = "pmgwork.awake.update-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "SUEnableAutomaticChecks")
        UpdateChannel.beta.save(in: defaults)
        XCTAssertEqual(UpdateChannel.stored(in: UserDefaults(suiteName: name)!), .beta)
        XCTAssertTrue(UpdateChannel.beta.feedURL.hasSuffix("/beta.xml"))
        UpdateChannel.stable.save(in: defaults)
        XCTAssertEqual(UpdateChannel.stored(in: UserDefaults(suiteName: name)!), .stable)
        XCTAssertTrue(UpdateChannel.stable.feedURL.hasSuffix("/stable.xml"))
        XCTAssertFalse(defaults.bool(forKey: "SUEnableAutomaticChecks"))
    }
}
