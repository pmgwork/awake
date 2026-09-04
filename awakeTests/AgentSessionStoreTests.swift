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
        let newer = AgentHookEvent(
            provider: .codex,
            sessionID: "session-1",
            state: .idle,
            reason: "Stop",
            occurredAt: Date(timeIntervalSince1970: 200)
        )
        let older = AgentHookEvent(
            provider: .codex,
            sessionID: "session-1",
            state: .active,
            reason: "UserPromptSubmit",
            occurredAt: Date(timeIntervalSince1970: 100)
        )

        try store.save(newer)
        try store.save(older)

        let events = store.loadValidEvents(cleaningInvalidFiles: false)
        XCTAssertEqual(events, [newer])
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
}
