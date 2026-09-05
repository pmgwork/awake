//
//  AgentHookEvent.swift
//  Awake
//

import Foundation

public nonisolated struct AgentHookEvent: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    /// Session-ID prefix reserved for `HookIntegrationManager.test()` traffic.
    /// The monitor never treats these synthetic events as real agent activity,
    /// so tapping Test cannot auto-start Keep Awake.
    public static let integrationTestSessionIDPrefix = "awake-integration-test-"

    public let schemaVersion: Int
    public let provider: AgentProvider
    public let sessionID: String
    public let turnID: String?
    public let state: AgentSessionState
    public let reason: String
    public let occurredAt: Date
    public let sourcePID: Int32?
    public let sourceProcessStartTime: TimeInterval?

    public init(
        schemaVersion: Int = currentSchemaVersion,
        provider: AgentProvider,
        sessionID: String,
        turnID: String? = nil,
        state: AgentSessionState,
        reason: String,
        occurredAt: Date = Date(),
        sourcePID: Int32? = nil,
        sourceProcessStartTime: TimeInterval? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.provider = provider
        self.sessionID = sessionID
        self.turnID = turnID
        self.state = state
        self.reason = reason
        self.occurredAt = occurredAt
        self.sourcePID = sourcePID
        self.sourceProcessStartTime = sourceProcessStartTime
    }

    public var sessionKey: String { "\(provider.rawValue):\(sessionID)" }

    /// Synthetic verification traffic from the Test button. Never real activity.
    public var isIntegrationTest: Bool {
        sessionID.hasPrefix(Self.integrationTestSessionIDPrefix)
            || reason.hasPrefix("integration-test")
    }
}
