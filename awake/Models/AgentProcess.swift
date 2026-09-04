//
//  AgentProcess.swift
//  Awake
//

import Foundation

public struct MonitoredAgent: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var processNames: [String]
    public var isEnabled: Bool
    public var isPreset: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        processNames: [String],
        isEnabled: Bool = true,
        isPreset: Bool = false
    ) {
        self.id = id
        self.name = name
        self.processNames = processNames
        self.isEnabled = isEnabled
        self.isPreset = isPreset
    }

    public static let defaultPresets: [MonitoredAgent] = [
        MonitoredAgent(
            name: "Codex",
            processNames: ["codex"],
            isEnabled: true,
            isPreset: true
        ),
        MonitoredAgent(
            name: "Claude",
            processNames: ["claude"],
            isEnabled: true,
            isPreset: true
        ),
        MonitoredAgent(
            name: "OpenCode",
            processNames: ["opencode", "opencode2"],
            isEnabled: true,
            isPreset: true
        ),
        MonitoredAgent(
            name: "Antigravity",
            processNames: ["antigravity", "agy"],
            isEnabled: true,
            isPreset: true
        )
    ]
}
