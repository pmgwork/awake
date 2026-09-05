//
//  AgentEventMonitor.swift
//  Awake
//

import Foundation
import Combine

@MainActor
public final class AgentEventMonitor: ObservableObject {
    public static let shared = AgentEventMonitor()

    @Published public private(set) var sessions: [AgentSession] = []
    @Published public private(set) var hasActiveSession = false
    @Published public private(set) var activeSessionCount = 0
    @Published public private(set) var activeProviderNames: Set<String> = []
    @Published public private(set) var activeSessionCountByProvider: [AgentProvider: Int] = [:]
    @Published public private(set) var lastEventAtByProvider: [AgentProvider: Date] = [:]

    private let store: AgentSessionStore
    private let queue = DispatchQueue(label: "pmgwork.awake.agent-event-monitor", qos: .utility)
    private var timer: Timer?
    private var enabledProviders = Set(AgentProvider.allCases)
    private var reloadInProgress = false

    public init(store: AgentSessionStore = .shared, startsAutomatically: Bool = true) {
        self.store = store
        try? store.prepareDirectory()
        if startsAutomatically { startMonitoring() }
    }

    deinit { timer?.invalidate() }

    public func updateEnabledProviders(_ providers: Set<AgentProvider>) {
        enabledProviders = providers
        reloadNow()
    }

    public func startMonitoring() {
        guard timer == nil else { return }
        reloadNow()
        // A short file poll is reliable for atomic cross-process renames and keeps
        // the first/last event latency below the one-second product requirement.
        let monitor = self
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            Task { @MainActor in monitor.reloadNow() }
        }
    }

    public func reloadNow() {
        guard !reloadInProgress else { return }
        reloadInProgress = true
        let store = self.store
        queue.async {
            let events = store.loadValidEvents()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.apply(events)
                self.reloadInProgress = false
            }
        }
    }

    private func apply(_ events: [AgentHookEvent]) {
        for event in events {
            if let current = lastEventAtByProvider[event.provider] {
                lastEventAtByProvider[event.provider] = max(current, event.occurredAt)
            } else {
                lastEventAtByProvider[event.provider] = event.occurredAt
            }
        }

        sessions = Self.activeSessions(from: events, enabledProviders: enabledProviders)
        activeSessionCount = sessions.count
        hasActiveSession = !sessions.isEmpty
        activeProviderNames = Set(sessions.map { $0.provider.displayName })
        activeSessionCountByProvider = Dictionary(grouping: sessions, by: \.provider)
            .mapValues(\.count)

        // Terminal events are kept long enough for this monitor to consume them,
        // then removed. This also lets an idle event clear a state left while Awake
        // was not running.
        let terminalEvents = events.filter { $0.state == .idle || $0.state == .stale }
        if !terminalEvents.isEmpty {
            let store = self.store
            queue.async { terminalEvents.forEach(store.remove) }
        }
    }

    nonisolated public static func activeSessions(
        from events: [AgentHookEvent],
        enabledProviders: Set<AgentProvider>
    ) -> [AgentSession] {
        var newestBySession: [String: AgentHookEvent] = [:]
        for event in events where enabledProviders.contains(event.provider) {
            // Synthetic Test-button traffic must never drive sleep prevention.
            guard !event.isIntegrationTest else { continue }
            if let current = newestBySession[event.sessionKey], current.occurredAt > event.occurredAt {
                continue
            }
            newestBySession[event.sessionKey] = event
        }
        return newestBySession.values
            .filter { $0.state == .active }
            .map(AgentSession.init(event:))
            .sorted { $0.id < $1.id }
    }
}
