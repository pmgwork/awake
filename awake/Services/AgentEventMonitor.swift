//
//  AgentEventMonitor.swift
//  Awake
//

import Foundation
import Combine

@MainActor
public final class AgentEventMonitor: ObservableObject {
    public static let shared = AgentEventMonitor(startsAutomatically: false)

    @Published public private(set) var hasActiveSession = false
    @Published public private(set) var activeSessionCount = 0
    @Published public private(set) var activeSessionCountByProvider: [AgentProvider: Int] = [:]

    private let store: AgentSessionStore
    private let queue = DispatchQueue(label: "pmgwork.awake.agent-event-monitor", qos: .utility)
    private var timer: Timer?
    private var enabledProviders = Set(AgentProvider.allCases)
    private var reloadInProgress = false
    private var generation = 0
    private var observer: FileTreeObserver?
    private var filesChanged = true
    private var lastFileReload = Date.distantPast

    public init(store: AgentSessionStore = .shared, startsAutomatically: Bool = true) {
        self.store = store
        try? store.prepareDirectory()
        if startsAutomatically { startMonitoring() }
    }

    deinit { timer?.invalidate() }

    public func updateEnabledProviders(_ providers: Set<AgentProvider>) {
        enabledProviders = providers
        if timer != nil { reloadNow() }
    }

    public func startMonitoring() {
        guard timer == nil else { return }
        observer = FileTreeObserver(url: store.directoryURL) { [weak self] in self?.reloadNow() }
        reloadNow()
        // The heartbeat checks process liveness/expiry using cached snapshots;
        // FSEvents handles atomic cross-process writes and renames.
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reloadNow(reloadingFiles: false) }
        }
    }

    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        observer = nil
        generation += 1
        apply([])
    }

    public func reloadNow(reloadingFiles: Bool = true) {
        if reloadingFiles { filesChanged = true }
        guard !reloadInProgress else { return }
        reloadInProgress = true
        let reloadFiles = filesChanged || Date().timeIntervalSince(lastFileReload) >= 30
        filesChanged = false
        if reloadFiles { lastFileReload = Date() }
        let generation = self.generation
        let store = self.store
        queue.async { [weak self] in
            // Recheck source PID/expiry every tick, but read files only after a
            // directory change (plus a recovery scan for missed notifications).
            let events = store.loadValidEvents(reloadingFiles: reloadFiles)
            guard let self else { return }
            Task { @MainActor in
                self.reloadInProgress = false
                guard self.generation == generation else {
                    if self.timer != nil { self.reloadNow() }
                    return
                }
                self.apply(events)
            }
        }
    }

    private func apply(_ events: [AgentHookEvent]) {
        let sessions = Self.activeSessions(from: events, enabledProviders: enabledProviders)
        activeSessionCount = sessions.count
        if hasActiveSession != !sessions.isEmpty { hasActiveSession = !sessions.isEmpty }
        let counts = Dictionary(grouping: sessions, by: \.provider).mapValues(\.count)
        if activeSessionCountByProvider != counts { activeSessionCountByProvider = counts }

        // Retain the latest terminal event to reject delayed older activity,
        // including after app restarts. A newer turn replaces the same file.
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
