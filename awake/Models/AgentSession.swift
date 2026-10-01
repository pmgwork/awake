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

    public var id: String { "\(provider.rawValue):\(sessionID)" }

    public init(event: AgentHookEvent) {
        provider = event.provider
        sessionID = event.sessionID
    }
}
