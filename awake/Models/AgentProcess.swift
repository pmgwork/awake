//
//  AgentProcess.swift
//  Awake
//

import Foundation

public nonisolated struct MonitoredAgent: Identifiable, Codable, Equatable, Hashable {
    public var id: String
    public var name: String
    public var processNames: [String]
    public var isEnabled: Bool
    public var isPreset: Bool
    public var provider: AgentProvider?

    public init(
        id: String = "custom:\(UUID().uuidString)",
        name: String,
        processNames: [String],
        isEnabled: Bool = true,
        isPreset: Bool = false,
        provider: AgentProvider? = nil
    ) {
        self.id = id
        self.name = name
        self.processNames = processNames
        self.isEnabled = isEnabled
        self.isPreset = isPreset
        self.provider = provider
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, processNames, isEnabled, isPreset, provider
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        processNames = try container.decode([String].self, forKey: .processNames)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        isPreset = try container.decode(Bool.self, forKey: .isPreset)
        provider = try container.decodeIfPresent(AgentProvider.self, forKey: .provider)
            ?? (isPreset ? AgentProvider.infer(name: name, processNames: processNames) : nil)
        let decodedID = try container.decodeIfPresent(String.self, forKey: .id)
        id = provider?.rawValue ?? decodedID ?? "custom:\(UUID().uuidString)"
    }

    public static let defaultPresets: [MonitoredAgent] = [
        MonitoredAgent(
            id: AgentProvider.codex.rawValue,
            name: "Codex",
            processNames: ["codex"],
            isEnabled: true,
            isPreset: true,
            provider: .codex
        ),
        MonitoredAgent(
            id: AgentProvider.claude.rawValue,
            name: "Claude Code",
            processNames: ["claude"],
            isEnabled: true,
            isPreset: true,
            provider: .claude
        ),
        MonitoredAgent(
            id: AgentProvider.openCode.rawValue,
            name: "OpenCode",
            processNames: ["opencode", "opencode2"],
            isEnabled: true,
            isPreset: true,
            provider: .openCode
        ),
        MonitoredAgent(
            id: AgentProvider.antigravity.rawValue,
            name: "Antigravity",
            processNames: ["antigravity", "agy"],
            isEnabled: true,
            isPreset: true,
            provider: .antigravity
        )
    ]
}
