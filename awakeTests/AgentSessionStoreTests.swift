import XCTest
@testable import awake

final class AgentSessionStoreTests: XCTestCase {
    private var directoryURL: URL!
    private var store: AgentSessionStore!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AwakeTests-\(UUID().uuidString)", isDirectory: true)
        store = AgentSessionStore(directoryURL: directoryURL)
        try store.prepareDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    func testOlderEventCannotReplaceNewerSessionState() throws {
        let now = Date()
        let newer = AgentHookEvent(
            provider: .codex,
            sessionID: "session-1",
            state: .idle,
            reason: "Stop",
            occurredAt: now
        )
        let older = AgentHookEvent(
            provider: .codex,
            sessionID: "session-1",
            state: .active,
            reason: "UserPromptSubmit",
            occurredAt: now.addingTimeInterval(-100)
        )

        try store.save(newer)
        try store.save(older)

        let events = store.loadValidEvents(cleaningInvalidFiles: false)
        XCTAssertEqual(events.map(\.sessionID), ["session-1"])
        XCTAssertEqual(events.map(\.state), [.idle])
        XCTAssertEqual(events.map(\.reason), ["Stop"])
    }

    func testMultipleSessionsAreAggregatedIndependently() {
        let now = Date()
        let events = [
            AgentHookEvent(provider: .codex, sessionID: "one", state: .active, reason: "start", occurredAt: now),
            AgentHookEvent(provider: .claude, sessionID: "two", state: .active, reason: "start", occurredAt: now),
            AgentHookEvent(provider: .codex, sessionID: "one", state: .idle, reason: "stop", occurredAt: now.addingTimeInterval(1)),
        ]

        let sessions = AgentEventMonitor.activeSessions(
            from: events,
            enabledProviders: Set(AgentProvider.allCases)
        )

        XCTAssertEqual(sessions.map(\.provider), [.claude])
        XCTAssertEqual(sessions.map(\.sessionID), ["two"])
    }

    func testDisabledProviderDoesNotBecomeActive() {
        let event = AgentHookEvent(provider: .openCode, sessionID: "one", state: .active, reason: "busy")
        let sessions = AgentEventMonitor.activeSessions(from: [event], enabledProviders: [.codex])
        XCTAssertTrue(sessions.isEmpty)
    }

    func testFilenameDoesNotContainRawSessionIdentifier() throws {
        let sessionID = "private-provider-session-id"
        let event = AgentHookEvent(provider: .antigravity, sessionID: sessionID, state: .active, reason: "PreInvocation")
        let url = try store.save(event)

        XCTAssertFalse(url.lastPathComponent.contains(sessionID))
        let persisted = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(persisted.contains("prompt"))
        XCTAssertFalse(persisted.contains("transcript"))
    }

    func testLegacyPresetMigratesToStableProviderIdentifier() throws {
        let legacy = """
        {
          "id": "41C1E0A9-ED22-486E-A923-DFD10F704348",
          "name": "Claude",
          "processNames": ["claude"],
          "isEnabled": false,
          "isPreset": true
        }
        """

        let agent = try JSONDecoder().decode(MonitoredAgent.self, from: Data(legacy.utf8))

        XCTAssertEqual(agent.id, AgentProvider.claude.rawValue)
        XCTAssertEqual(agent.provider, .claude)
        XCTAssertFalse(agent.isEnabled)
    }

    func testFreshActiveSessionWithoutPIDIsKept() throws {
        let event = AgentHookEvent(
            provider: .codex,
            sessionID: "fresh-no-pid",
            state: .active,
            reason: "UserPromptSubmit",
            occurredAt: Date()
        )
        try store.save(event)

        let events = store.loadValidEvents()
        XCTAssertEqual(events.map(\.sessionID), ["fresh-no-pid"])
        XCTAssertEqual(events.map(\.state), [.active])
    }

    func testExpiredActiveSessionWithoutPIDIsDropped() throws {
        let event = AgentHookEvent(
            provider: .codex,
            sessionID: "orphan-no-pid",
            state: .active,
            reason: "UserPromptSubmit",
            occurredAt: Date().addingTimeInterval(-(AgentSessionStore.orphanSessionTTL + 60))
        )
        try store.save(event)

        let events = store.loadValidEvents()
        XCTAssertTrue(events.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(provider: .codex, sessionID: "orphan-no-pid").path))
    }

    func testExpiredWaitingForInputIsDropped() throws {
        let event = AgentHookEvent(
            provider: .claude,
            sessionID: "orphan-waiting",
            state: .waitingForInput,
            reason: "idle_prompt",
            occurredAt: Date().addingTimeInterval(-(AgentSessionStore.orphanSessionTTL + 60))
        )
        try store.save(event)

        let events = store.loadValidEvents()
        XCTAssertTrue(events.isEmpty)
    }

    func testIntegrationTestTrafficNeverBecomesActive() {
        let active = AgentHookEvent(
            provider: .codex,
            sessionID: "\(AgentHookEvent.integrationTestSessionIDPrefix)test-123",
            state: .active,
            reason: "integration-test"
        )
        let sessions = AgentEventMonitor.activeSessions(
            from: [active],
            enabledProviders: Set(AgentProvider.allCases)
        )
        XCTAssertTrue(sessions.isEmpty)
    }

    func testRemoveByProviderAndSessionID() throws {
        let event = AgentHookEvent(provider: .claude, sessionID: "to-remove", state: .active, reason: "start")
        try store.save(event)
        XCTAssertEqual(store.loadValidEvents().count, 1)

        store.remove(provider: .claude, sessionID: "to-remove")
        XCTAssertTrue(store.loadValidEvents().isEmpty)
    }
}
