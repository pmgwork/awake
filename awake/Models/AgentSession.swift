//
//  AgentSession.swift
//  Awake
//

import Foundation

public nonisolated enum AgentSessionState: String, Codable, Sendable {
    case active
    case waitingForInput
    case idle
    case stale
}

public nonisolated struct AgentSession: Identifiable, Equatable, Sendable {
    public let provider: AgentProvider
    public let sessionID: String
    public let turnID: String?
    public let state: AgentSessionState
    public let reason: String
    public let occurredAt: Date
    public let sourcePID: Int32?

    public var id: String { "\(provider.rawValue):\(sessionID)" }

    public init(event: AgentHookEvent) {
        provider = event.provider
        sessionID = event.sessionID
        turnID = event.turnID
        state = event.state
        reason = event.reason
        occurredAt = event.occurredAt
        sourcePID = event.sourcePID
    }
}
