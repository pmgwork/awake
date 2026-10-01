import XCTest
@testable import awake

final class AgentSessionStoreTests: XCTestCase {
    private var directoryURL: URL!
    private var store: AgentSessionStore!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AwakeTests-\(UUID().uuidString)", isDirectory: true)
        store = AgentSessionStore(directoryURL: directoryURL)
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

    @MainActor
    func testConsumedTerminalEventRejectsDelayedActivityAndAllowsNewTurn() async throws {
        let now = Date()
        try store.save(AgentHookEvent(
            provider: .codex, sessionID: "finished", state: .idle,
            reason: "Stop", occurredAt: now
        ))
        let monitor = AgentEventMonitor(store: store, startsAutomatically: false)
        // A second poll also drains any cleanup queued by the first poll.
        await reload(monitor)
        await reload(monitor)
        XCTAssertFalse(monitor.hasActiveSession)
        XCTAssertEqual(store.loadValidEvents().map(\.state), [.idle])

        // A new store instance proves ordering survives app restarts.
        let reopened = AgentSessionStore(directoryURL: directoryURL)
        try reopened.save(AgentHookEvent(
            provider: .codex, sessionID: "finished", state: .active,
            reason: "delayed PreToolUse", occurredAt: now.addingTimeInterval(-1)
        ))
        await reload(monitor)
        XCTAssertFalse(monitor.hasActiveSession)
        XCTAssertEqual(reopened.loadValidEvents().map(\.state), [.idle])

        try reopened.save(AgentHookEvent(
            provider: .codex, sessionID: "finished", state: .active,
            reason: "UserPromptSubmit", occurredAt: now.addingTimeInterval(1)
        ))
        await reload(monitor)
        XCTAssertTrue(monitor.hasActiveSession)
        XCTAssertEqual(monitor.activeSessionCount, 1)
        XCTAssertEqual(monitor.activeSessionCountByProvider, [.codex: 1])
    }

    @MainActor
    private func reload(_ monitor: AgentEventMonitor) async {
        let applied = expectation(description: "Monitor applied snapshot")
        let subscription = monitor.$activeSessionCount.dropFirst().sink { _ in applied.fulfill() }
        monitor.reloadNow()
        await fulfillment(of: [applied], timeout: 2)
        subscription.cancel()
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

    func testOnlyEnabledNonTestSessionsBecomeActive() {
        let events = [
            AgentHookEvent(provider: .codex, sessionID: "enabled", state: .active, reason: "busy"),
            AgentHookEvent(provider: .openCode, sessionID: "disabled", state: .active, reason: "busy"),
            AgentHookEvent(
                provider: .codex,
                sessionID: "\(AgentHookEvent.integrationTestSessionIDPrefix)test-123",
                state: .active,
                reason: "integration-test"
            ),
        ]

        let sessions = AgentEventMonitor.activeSessions(from: events, enabledProviders: [.codex])
        XCTAssertEqual(sessions.map(\.sessionID), ["enabled"])
    }

    func testFilenameDoesNotContainRawSessionIdentifier() throws {
        let sessionID = "private-provider-session-id"
        let event = AgentHookEvent(provider: .antigravity, sessionID: sessionID, state: .active, reason: "PreInvocation")
        let url = try store.save(event)

        XCTAssertFalse(url.lastPathComponent.contains(sessionID))
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

    func testExpiredSessionsWithoutPIDAreDroppedWhileFreshSessionIsKept() throws {
        let now = Date()
        let fresh = AgentHookEvent(
            provider: .codex,
            sessionID: "fresh-no-pid",
            state: .active,
            reason: "UserPromptSubmit",
            occurredAt: now
        )
        let expiredActive = AgentHookEvent(
            provider: .codex,
            sessionID: "orphan-no-pid",
            state: .active,
            reason: "UserPromptSubmit",
            occurredAt: now.addingTimeInterval(-(AgentSessionStore.orphanSessionTTL + 60))
        )
        let expiredWaiting = AgentHookEvent(
            provider: .claude,
            sessionID: "orphan-waiting",
            state: .waitingForInput,
            reason: "idle_prompt",
            occurredAt: now.addingTimeInterval(-(AgentSessionStore.orphanSessionTTL + 60))
        )

        try store.save(fresh)
        try store.save(expiredActive)
        try store.save(expiredWaiting)

        let events = store.loadValidEvents(now: now)
        XCTAssertEqual(events.map(\.sessionID), ["fresh-no-pid"])
        XCTAssertEqual(events.map(\.state), [.active])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(provider: .codex, sessionID: "orphan-no-pid").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(provider: .claude, sessionID: "orphan-waiting").path))
    }

    func testRemoveByProviderAndSessionID() throws {
        let event = AgentHookEvent(provider: .claude, sessionID: "to-remove", state: .active, reason: "start")
        try store.save(event)
        XCTAssertEqual(store.loadValidEvents().count, 1)

        store.remove(provider: .claude, sessionID: "to-remove")
        XCTAssertTrue(store.loadValidEvents().isEmpty)
    }
}
