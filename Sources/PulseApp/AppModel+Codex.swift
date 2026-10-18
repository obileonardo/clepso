import CodexAdapter
import Foundation
import UsageEngine

/// Increment 3.4: Codex's limits from its own session files. Off until the user turns it on;
/// then read on every tick (the newest files' tails only, about 50 ms) and stored under Codex's own connection.
extension AppModel {
    /// Whether Codex has ever written a session on this Mac, for Settings ("Codex found" / "not found").
    public var codexInstalled: Bool { CodexReader.isInstalled(home: environment.home) }

    public func setCodexEnabled(_ on: Bool) async {
        codexEnabled = on
        try? await store?.setPreference(Pref.readCodex, on, now: environment.clock.now())
        if on { await pollCodex() } else { codexLatest = nil; codexUsage = nil; codexDays = nil; codexAgentTasks = nil }
        await refresh()
    }

    /// Reads Codex's latest limits and stores them; a reading Pulse already has is a no-op (same dedupe keys).
    /// Returns the engine's events for the alerts.
    @discardableResult
    func pollCodex() async -> [EngineEvent] {
        guard codexEnabled, !demo, let store else { return [] }
        scanCodexUsage()
        let now = environment.clock.now()
        guard let reading = CodexReader.latest(home: environment.home, now: now) else { return [] }
        codexLatest = reading
        do {
            let connection: UUID
            if let codexConnection { connection = codexConnection } else {
                connection = try await store.connection(adapterID: CodexMapper.adapterID, providerID: CodexMapper.providerID,
                                                        label: "Codex", now: now)
                codexConnection = connection
            }
            return try await store.ingest(CodexMapper.observations(reading, connectionID: connection, receivedAt: now),
                                       session: nil, connection: connection).events
        } catch {
            problem = .storage("\(error)")
            return []
        }
    }

    /// Tokens per day and agents per task: the first read of every session file takes seconds, so it runs off the main actor; later reads
    /// take only what Codex appended. One read at a time; a tick that finds one running skips.
    func scanCodexUsage() {
        guard !codexScanning else { return }
        codexScanning = true
        let home = environment.home
        let usage = codexUsage ?? CodexUsage(zone: environment.timeZone)
        Task {
            let scanned = await Task.detached(priority: .utility) { () -> CodexUsage in
                var copy = usage
                copy.scan(home: home)
                return copy
            }.value
            codexScanning = false
            guard codexEnabled else { return }                     // turned off while reading: keep nothing
            codexUsage = scanned
            codexDays = scanned.days
            let tasks = scanned.agents.tasks
            guard tasks != codexAgentTasks else { return }
            codexAgentTasks = tasks
            await refresh()                                        // the Session page's Codex agents
        }
    }
}
