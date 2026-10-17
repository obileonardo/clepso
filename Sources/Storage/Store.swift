import Domain
import Foundation
import GRDB
import UsageEngine

/// The single writer (ARCHITECTURE §4): ledger insert, reduce and snapshot in one transaction per batch
/// (ARCHITECTURE §4), snapshot rebuild from the ledger (DATA_MODEL §9), and time ticks.
public actor Store {
    public struct SessionMeta: Sendable {
        public let sessionRef: String
        public let modelID: String?
        public let modelDisplayName: String?
        public init(sessionRef: String, modelID: String?, modelDisplayName: String?) {
            self.sessionRef = sessionRef
            self.modelID = modelID
            self.modelDisplayName = modelDisplayName
        }
    }

    public struct IngestResult: Sendable, Equatable {
        public let inserted: Int
        public let duplicates: Int
        public let events: [EngineEvent]
        /// Readings not stored because nothing changed (see `LedgerPolicy`).
        public var unchanged = 0
    }

    /// Which readings the ledger keeps (DATA_MODEL §6.4, increment 1.7c). Claude Code refreshes its status line several
    /// times a minute and most values repeat; storing every repeat grew the database by about 4 MB an hour. A limit is
    /// stored when its used % or reset time changes, else every `poolHeartbeat`; a session metric when it changes and
    /// `sessionMinInterval` has passed, else every `sessionHeartbeat`. The reducers only ever see stored rows, so live
    /// state and a rebuild from the ledger still agree.
    public struct LedgerPolicy: Sendable, Equatable {
        public var poolHeartbeat: TimeInterval = 120
        public var sessionMinInterval: TimeInterval = 60
        public var sessionHeartbeat: TimeInterval = 120
        public init() {}
        /// Store every reading (tests that need each frame in the ledger).
        public static let everyReading: LedgerPolicy = {
            var p = LedgerPolicy(); p.poolHeartbeat = 0; p.sessionMinInterval = 0; p.sessionHeartbeat = 0; return p
        }()
    }

    let writer: any DatabaseWriter
    let config: EngineConfig
    public nonisolated let policy: LedgerPolicy
    public nonisolated let accountID: UUID
    public nonisolated let connectionID: UUID

    /// Opens the store on a migrated database and ensures the Stage A account and connection exist:
    /// one labelled account, one Claude Code status-line connection (founder decision).
    public init(writer: any DatabaseWriter, config: EngineConfig = EngineConfig(), policy: LedgerPolicy = LedgerPolicy(), now: Date) throws {
        try Migrations.migrator().migrate(writer)
        self.writer = writer
        self.config = config
        self.policy = policy
        let ids = try writer.write { db -> (UUID, UUID) in
            if let row = try Row.fetchOne(db, sql: "SELECT id, account_id FROM connections WHERE adapter_id = 'claude-code.statusline' LIMIT 1"),
               let connection = UUID(uuidString: row["id"]), let account = UUID(uuidString: row["account_id"]) {
                return (account, connection)
            }
            let account = UUID(), connection = UUID()
            try db.execute(sql: "INSERT INTO accounts (id, provider_id, kind, label, created_at) VALUES (?, 'anthropic', 'personalSubscription', 'This Mac', ?)",
                           arguments: [account.uuidString, ms(now)])
            try db.execute(sql: "INSERT INTO connections (id, account_id, adapter_id, state) VALUES (?, ?, 'claude-code.statusline', 'connected')",
                           arguments: [connection.uuidString, account.uuidString])
            return (account, connection)
        }
        accountID = ids.0
        connectionID = ids.1
    }

    /// The connection for another agent's adapter (increment 3.4), created with its own account on first use.
    /// Claude Code's is `connectionID`.
    public func connection(adapterID: String, providerID: String, label: String, now: Date) throws -> UUID {
        try writer.write { db in
            if let id = try String.fetchOne(db, sql: "SELECT id FROM connections WHERE adapter_id = ? LIMIT 1", arguments: [adapterID]),
               let uuid = UUID(uuidString: id) { return uuid }
            let account = UUID(), connection = UUID()
            try db.execute(sql: "INSERT INTO accounts (id, provider_id, kind, label, created_at) VALUES (?, ?, 'personalSubscription', ?, ?)",
                           arguments: [account.uuidString, providerID, label, ms(now)])
            try db.execute(sql: "INSERT INTO connections (id, account_id, adapter_id, state) VALUES (?, ?, ?, 'connected')",
                           arguments: [connection.uuidString, account.uuidString, adapterID])
            return connection
        }
    }

    /// A store on a private in-memory database, for tests and previews.
    public static func inMemory(now: Date, config: EngineConfig = EngineConfig(), policy: LedgerPolicy = LedgerPolicy()) throws -> Store {
        try Store(writer: DatabaseQueue(), config: config, policy: policy, now: now)
    }

    // MARK: - Ingest

    /// The clock is the batch's own arrival time (`receivedAt`), the same value the ledger records, so live
    /// processing and a rebuild can never disagree about time or order.
    public func ingest(_ observations: [IncomingObservation], session: SessionMeta?, connection: UUID? = nil) throws -> IngestResult {
        guard let now = observations.map(\.receivedAt).max() else { return IngestResult(inserted: 0, duplicates: 0, events: []) }
        return try writer.write { db in
            let owner = try self.owner(db, connection: connection ?? connectionID)
            var sessionID: String?
            if let session, let first = observations.first {
                sessionID = try upsertSession(db, session, seenAt: first.observedAt)
            }
            var inserted: [IncomingObservation] = []
            var duplicates = 0, unchanged = 0
            let keep = try worthKeeping(db, observations, sessionID: sessionID, at: now)
            for (index, observation) in observations.enumerated() {
                let poolID: String?
                switch observation.subject {
                case .pool(let key): poolID = try poolRow(db, key: key, owner: owner, createdAt: now).id
                case .session: poolID = nil
                }
                if case .session = observation.subject, sessionID == nil { continue }
                guard keep.contains(index) else { unchanged += 1; continue }
                try insert(db, observation, poolID: poolID, sessionID: sessionID, owner: owner)
                if db.changesCount == 1 { inserted.append(observation) } else { duplicates += 1 }
            }
            var events: [EngineEvent] = []
            for (key, update) in Self.poolUpdates(inserted) {
                events += try reducePool(db, key: key, update: update, owner: owner, now: now)
            }
            if let sessionID, let ref = session?.sessionRef {
                try reduceSession(db, sessionID: sessionID, ref: ref, observations: inserted)
            }
            try db.execute(sql: "UPDATE connections SET last_event_at = ? WHERE id = ?", arguments: [ms(now), owner.connection])
            return IngestResult(inserted: inserted.count, duplicates: duplicates, events: events, unchanged: unchanged)
        }
    }

    /// Indexes of `observations` the `LedgerPolicy` keeps. A pool's used % and reset time are kept or skipped
    /// together, so the reducer always sees the pair from one frame.
    func worthKeeping(_ db: Database, _ observations: [IncomingObservation], sessionID: String?, at now: Date) throws -> Set<Int> {
        var keep = Set<Int>()
        var poolMembers: [String: [Int]] = [:]
        for (index, o) in observations.enumerated() {
            switch o.subject {
            case .pool(let key): poolMembers[key, default: []].append(index)
            case .session:
                guard let sessionID else { continue }
                let last = try lastStored(db, column: "session_id", id: sessionID, kind: o.kind)
                if Self.shouldStore(o, last: last, minInterval: policy.sessionMinInterval, heartbeat: policy.sessionHeartbeat) { keep.insert(index) }
            }
        }
        for (key, members) in poolMembers {
            let poolID = try String.fetchOne(db, sql: "SELECT id FROM allowance_pools WHERE provider_pool_key = ?", arguments: [key])
            var store = poolID == nil
            if let poolID {
                for index in members where !store {
                    let last = try lastStored(db, column: "pool_id", id: poolID, kind: observations[index].kind)
                    store = Self.shouldStore(observations[index], last: last, minInterval: 0, heartbeat: policy.poolHeartbeat)
                }
            }
            if store { keep.formUnion(members) }
        }
        return keep
    }

    /// The newest stored reading of one metric for one subject: its canonical value and time.
    func lastStored(_ db: Database, column: String, id: String, kind: MetricKind) throws -> (value: String, observedAt: Date)? {
        try Row.fetchOne(db, sql: """
            SELECT value_kind, value_text, absence_reason, observed_at FROM observations
            WHERE \(column) = ? AND metric_kind = ? ORDER BY observed_at DESC LIMIT 1
            """, arguments: [id, kind.rawValue]).map { row in
            ("\(row["value_kind"] as String)|\(row["value_text"] as String? ?? "-")|\(row["absence_reason"] as String? ?? "-")", date(row["observed_at"]))
        }
    }

    /// Keep it when nothing is stored yet, when it is older than what is stored (history), when the value changed and
    /// `minInterval` has passed, or when `heartbeat` has passed. A zero heartbeat keeps everything.
    static func shouldStore(_ o: IncomingObservation, last: (value: String, observedAt: Date)?, minInterval: TimeInterval, heartbeat: TimeInterval) -> Bool {
        guard let last else { return true }
        let elapsed = o.observedAt.timeIntervalSince(last.observedAt)
        if elapsed < 0 || heartbeat == 0 { return true }
        if elapsed == 0 { return storageText(o.value) != last.value }
        if elapsed >= heartbeat { return true }
        return storageText(o.value) != last.value && elapsed >= minInterval
    }

    /// The same text `lastStored` reads back, for comparing a new value with the stored one.
    static func storageText(_ value: MetricValue) -> String {
        switch value {
        case .percent(let d): "percent|\(d)|-"
        case .tokens(let n): "tokens|\(n)|-"
        case .usd(let d): "usd|\(d)|-"
        case .instant(let date): "instant|\(ms(date))|-"
        case .count(let n): "count|\(n)|-"
        case .duration(let milliseconds): "duration|\(milliseconds)|-"
        case .flag(let b): "flag|\(b ? "1" : "0")|-"
        case .absent(let reason): "absent|-|\(reason.rawValue)"
        }
    }

    /// Time passing with no new readings: reset expectation (G9) and staleness (G13).
    public func tick(now: Date) throws -> [EngineEvent] {
        try writer.write { db in
            var events: [EngineEvent] = []
            for pool in try pools(db) {
                guard let state = try loadPoolState(db, poolID: pool.id) else { continue }
                let (next, newEvents) = PoolReducer.tick(state, now: now, config: config)
                guard next != state else { continue }
                try save(db, pool: pool, state: next, closed: [], events: newEvents)
                events += newEvents
            }
            return events
        }
    }

    // MARK: - Rebuild (DATA_MODEL §9): projections from the ledger, arrival order, historical clock

    public func rebuild(now: Date) throws {
        try writer.write { db in
            for table in ["pool_snapshots", "session_snapshots", "derived_events", "pool_windows"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
            for pool in try pools(db) {
                var state = PoolState(poolKey: pool.key)
                for group in try observationGroups(db, column: "pool_id", id: pool.id) {
                    let update = PoolUpdate(used: group.first { $0.kind == .quotaUsedPct }, reset: group.first { $0.kind == .resetAt })
                    let reduction = PoolReducer.reduce(state, update, now: group[0].receivedAt,
                                                       overageEvidence: pool.overageEvidence, config: config)
                    state = reduction.state
                    try save(db, pool: pool, state: state, closed: reduction.closedWindows, events: reduction.events)
                }
                let (final, events) = PoolReducer.tick(state, now: now, config: config)
                try save(db, pool: pool, state: final, closed: [], events: events)
            }
            for row in try Row.fetchAll(db, sql: "SELECT id, provider_session_key FROM sessions ORDER BY id") {
                let sessionID: String = row["id"], ref: String = row["provider_session_key"]
                for group in try observationGroups(db, column: "session_id", id: sessionID, subjectKind: "session") {
                    try reduceSession(db, sessionID: sessionID, ref: ref, observations: group)
                }
            }
        }
    }

    // MARK: - Reading

    public func poolStates() throws -> [PoolState] {
        try writer.read { db in
            try String.fetchAll(db, sql: "SELECT snapshot_json FROM pool_snapshots").compactMap { Self.decodePool($0) }
                .sorted { $0.poolKey < $1.poolKey }
        }
    }

    public func sessionStates() throws -> [SessionState] {
        try writer.read { db in
            try String.fetchAll(db, sql: "SELECT snapshot_json FROM session_snapshots").compactMap {
                try? JSONDecoder().decode(SessionState.self, from: Data($0.utf8))
            }.sorted { $0.sessionRef < $1.sessionRef }
        }
    }

    public func events() throws -> [EngineEvent] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT payload_json FROM derived_events ORDER BY occurred_at, id").compactMap {
                try? JSONDecoder().decode(EngineEvent.self, from: Data(($0["payload_json"] as String).utf8))
            }
        }
    }

    /// Every projection row as text, in a fixed order: the byte-level evidence for "rebuild equals live".
    public func projectionDump() throws -> String {
        try writer.read { db in
            let pools = try String.fetchAll(db, sql: "SELECT pool_id || '|' || IFNULL(window_id,'-') || '|' || state || '|' || version || '|' || snapshot_json FROM pool_snapshots ORDER BY pool_id")
            let windows = try String.fetchAll(db, sql: "SELECT id || '|' || pool_id || '|' || opened_at || '|' || IFNULL(resets_at,'-') || '|' || IFNULL(closed_at,'-') || '|' || version FROM pool_windows ORDER BY id")
            let sessions = try String.fetchAll(db, sql: "SELECT session_id || '|' || version || '|' || snapshot_json FROM session_snapshots ORDER BY session_id")
            return (pools + ["--"] + windows + ["--"] + sessions).joined(separator: "\n")
        }
    }

    // MARK: - Pools and sessions

    struct PoolRow { let id: String; let key: String; let overageEvidence: Bool; let accountID: String }
    /// The account and connection a batch arrived through (increment 3.4: one per agent).
    struct Owner { let account: String; let connection: String }

    func owner(_ db: Database, connection: UUID) throws -> Owner {
        guard let account = try String.fetchOne(db, sql: "SELECT account_id FROM connections WHERE id = ?", arguments: [connection.uuidString]) else {
            throw StoreError.unknownConnection
        }
        return Owner(account: account, connection: connection.uuidString)
    }

    func pools(_ db: Database) throws -> [PoolRow] {
        try Row.fetchAll(db, sql: "SELECT id, provider_pool_key, overage_evidence, account_id FROM allowance_pools ORDER BY provider_pool_key")
            .map { PoolRow(id: $0["id"], key: $0["provider_pool_key"], overageEvidence: ($0["overage_evidence"] as String?) != nil, accountID: $0["account_id"]) }
    }

    func poolRow(_ db: Database, key: String, owner: Owner, createdAt: Date) throws -> PoolRow {
        if let row = try Row.fetchOne(db, sql: "SELECT id, overage_evidence, account_id FROM allowance_pools WHERE provider_pool_key = ?", arguments: [key]) {
            return PoolRow(id: row["id"], key: key, overageEvidence: (row["overage_evidence"] as String?) != nil, accountID: row["account_id"])
        }
        let id = UUID().uuidString
        let (name, funding): (String, PoolFunding) = switch key {
        case "claude-code.rate_limits.five_hour": ("5-hour", .includedSubscription)
        case "claude-code.rate_limits.seven_day": ("7-day", .includedSubscription)
        case "claude-code.rate_limits.spend_limit": ("Spend limit", .apiPayAsYouGo)
        case "codex.rate_limits.five_hour": ("5-hour", .includedSubscription)
        case "codex.rate_limits.seven_day": ("Weekly", .includedSubscription)
        default: (key, .unknown)
        }
        let product = key.split(separator: ".").first.map(String.init) ?? "unknown"
        try db.execute(sql: """
            INSERT INTO allowance_pools (id, account_id, provider_pool_key, name, funding, window_type, eligible_products, created_at)
            VALUES (?, ?, ?, ?, ?, 'unknown', ?, ?)
            """, arguments: [id, owner.account, key, name, funding.rawValue, Self.encode([product]), ms(createdAt)])
        return PoolRow(id: id, key: key, overageEvidence: false, accountID: owner.account)
    }

    func upsertSession(_ db: Database, _ meta: SessionMeta, seenAt: Date) throws -> String {
        if let id = try String.fetchOne(db, sql: "SELECT id FROM sessions WHERE connection_id = ? AND provider_session_key = ?",
                                        arguments: [connectionID.uuidString, meta.sessionRef]) {
            try db.execute(sql: """
                UPDATE sessions SET model_id = COALESCE(?, model_id), model_display_name = COALESCE(?, model_display_name),
                  last_seen_at = MAX(last_seen_at, ?) WHERE id = ?
                """, arguments: [meta.modelID, meta.modelDisplayName, ms(seenAt), id])
            return id
        }
        let id = UUID().uuidString
        try db.execute(sql: """
            INSERT INTO sessions (id, account_id, connection_id, provider_session_key, model_id, model_display_name, first_seen_at, last_seen_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [id, accountID.uuidString, connectionID.uuidString, meta.sessionRef, meta.modelID, meta.modelDisplayName,
                             ms(seenAt), ms(seenAt)])
        return id
    }

    // MARK: - Ledger rows

    func insert(_ db: Database, _ o: IncomingObservation, poolID: String?, sessionID: String?, owner: Owner) throws {
        let (kind, text, absence): (String, String?, String?) = switch o.value {
        case .percent(let d): ("percent", "\(d)", nil)
        case .tokens(let n): ("tokens", String(n), nil)
        case .usd(let d): ("usd", "\(d)", nil)
        case .instant(let date): ("instant", String(ms(date)), nil)
        case .count(let n): ("count", String(n), nil)
        case .duration(let milliseconds): ("duration", String(milliseconds), nil)
        case .flag(let b): ("flag", b ? "1" : "0", nil)
        case .absent(let reason): ("absent", nil, reason.rawValue)
        }
        let subjectKind = if case .pool = o.subject { "pool" } else { "session" }
        try db.execute(sql: """
            INSERT OR IGNORE INTO observations (id, account_id, connection_id, pool_id, session_id, subject_kind, model_id, metric_kind,
              value_kind, value_text, absence_reason, observed_at, received_at, evidence, quality, source_version, dedupe_key)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [UUID().uuidString, owner.account, owner.connection, poolID, sessionID, subjectKind, o.modelID,
                             o.kind.rawValue, kind, text, absence, ms(o.observedAt), ms(o.receivedAt), o.evidence.rawValue,
                             o.quality.rawValue, o.sourceVersion, o.dedupeKey])
    }

    /// Ledger rows for one subject in arrival order, grouped per frame (same observed and received time).
    func observationGroups(_ db: Database, column: String, id: String, subjectKind: String = "pool") throws -> [[IncomingObservation]] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT o.*, a.provider_pool_key, s.provider_session_key FROM observations o
            LEFT JOIN allowance_pools a ON a.id = o.pool_id LEFT JOIN sessions s ON s.id = o.session_id
            WHERE o.\(column) = ? AND o.subject_kind = ? ORDER BY o.received_at, o.rowid
            """, arguments: [id, subjectKind])
        var groups: [[IncomingObservation]] = []
        var lastKey: (Int64, Int64)?
        for row in rows {
            guard let observation = Self.decode(row) else { continue }
            let key: (Int64, Int64) = (row["observed_at"], row["received_at"])
            if let lastKey, lastKey == key { groups[groups.count - 1].append(observation) } else { groups.append([observation]) }
            lastKey = key
        }
        return groups
    }

    static func decode(_ row: Row) -> IncomingObservation? {
        let text: String? = row["value_text"]
        let value: MetricValue
        switch row["value_kind"] as String {
        case "percent": guard let d = text.flatMap({ Decimal(string: $0) }) else { return nil }; value = .percent(d)
        case "usd": guard let d = text.flatMap({ Decimal(string: $0) }) else { return nil }; value = .usd(d)
        case "tokens": guard let n = text.flatMap({ Int64($0) }) else { return nil }; value = .tokens(n)
        case "instant": guard let n = text.flatMap({ Int64($0) }) else { return nil }; value = .instant(date(n))
        case "count": guard let n = text.flatMap({ Int64($0) }) else { return nil }; value = .count(n)
        case "duration": guard let n = text.flatMap({ Int64($0) }) else { return nil }; value = .duration(milliseconds: n)
        case "flag": guard let t = text, t == "0" || t == "1" else { return nil }; value = .flag(t == "1")
        default: guard let r = (row["absence_reason"] as String?).flatMap(AbsenceReason.init(rawValue:)) else { return nil }; value = .absent(r)
        }
        let subject: SubjectKey = (row["subject_kind"] as String) == "pool"
            ? .pool(providerPoolKey: row["provider_pool_key"]) : .session(sessionRef: row["provider_session_key"])
        guard let kind = MetricKind(rawValue: row["metric_kind"]), let evidence = EvidenceKind(rawValue: row["evidence"]),
              let quality = Quality(rawValue: row["quality"]) else { return nil }
        return IncomingObservation(subject: subject, sessionRef: row["provider_session_key"], modelID: row["model_id"], kind: kind,
                                   value: value, observedAt: date(row["observed_at"]), receivedAt: date(row["received_at"]),
                                   evidence: evidence, quality: quality, sourceVersion: row["source_version"], dedupeKey: row["dedupe_key"])
    }

    // MARK: - Projections

    static func poolUpdates(_ observations: [IncomingObservation]) -> [(String, PoolUpdate)] {
        var keys: [String] = []
        var used: [String: IncomingObservation] = [:], reset: [String: IncomingObservation] = [:]
        for o in observations {
            guard case .pool(let key) = o.subject else { continue }
            if !keys.contains(key) { keys.append(key) }
            if o.kind == .quotaUsedPct { used[key] = o } else if o.kind == .resetAt { reset[key] = o }
        }
        return keys.sorted().map { ($0, PoolUpdate(used: used[$0], reset: reset[$0])) }
    }

    func reducePool(_ db: Database, key: String, update: PoolUpdate, owner: Owner, now: Date) throws -> [EngineEvent] {
        let pool = try poolRow(db, key: key, owner: owner, createdAt: now)
        let state = try loadPoolState(db, poolID: pool.id) ?? PoolState(poolKey: key)
        let reduction = PoolReducer.reduce(state, update, now: now, overageEvidence: pool.overageEvidence, config: config)
        try save(db, pool: pool, state: reduction.state, closed: reduction.closedWindows, events: reduction.events)
        return reduction.events
    }

    func reduceSession(_ db: Database, sessionID: String, ref: String, observations: [IncomingObservation]) throws {
        let current = try String.fetchOne(db, sql: "SELECT snapshot_json FROM session_snapshots WHERE session_id = ?", arguments: [sessionID])
            .flatMap { try? JSONDecoder().decode(SessionState.self, from: Data($0.utf8)) } ?? SessionState(sessionRef: ref)
        let next = SessionReducer.reduce(current, observations)
        guard next != current || current.version == 0 else { return }
        try db.execute(sql: "INSERT OR REPLACE INTO session_snapshots (session_id, snapshot_json, last_seen, version) VALUES (?, ?, ?, ?)",
                       arguments: [sessionID, Self.encode(next), next.lastSeen.map(ms) ?? 0, next.version])
    }

    func loadPoolState(_ db: Database, poolID: String) throws -> PoolState? {
        try String.fetchOne(db, sql: "SELECT snapshot_json FROM pool_snapshots WHERE pool_id = ?", arguments: [poolID]).flatMap(Self.decodePool)
    }

    func save(_ db: Database, pool: PoolRow, state: PoolState, closed: [WindowState], events: [EngineEvent]) throws {
        for window in closed + [state.window].compactMap({ $0 }) {
            try db.execute(sql: """
                INSERT INTO pool_windows (id, pool_id, opened_at, resets_at, closed_at, version) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET resets_at = excluded.resets_at, closed_at = excluded.closed_at, version = excluded.version
                """, arguments: [window.id.uuidString, pool.id, ms(window.openedAt), window.resetsAt.map(ms), window.closedAt.map(ms), window.version])
        }
        try db.execute(sql: """
            INSERT OR REPLACE INTO pool_snapshots (pool_id, account_id, window_id, snapshot_json, state, last_provider_measured, last_seen, version)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [pool.id, pool.accountID, state.window?.id.uuidString, Self.encode(state), state.limit.label,
                             state.lastProviderMeasured.map(ms), state.lastSeen.map(ms), state.version])
        for event in events {
            let windowText = event.windowID?.uuidString ?? "-"
            let dedupe = [pool.accountID, pool.id, windowText, event.kind.rawValue, event.level?.rawValue ?? "-"].joined(separator: "|")
            let id = derivedUUID("event|\(dedupe)|\(ms(event.occurredAt))")
            try db.execute(sql: """
                INSERT OR IGNORE INTO derived_events (id, kind, account_id, pool_id, window_id, level, occurred_at, dedupe_key, payload_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [id.uuidString, event.kind.rawValue, pool.accountID, pool.id, event.windowID?.uuidString,
                                 event.level?.rawValue, ms(event.occurredAt), dedupe, Self.encode(event)])
        }
    }

    // MARK: - Encoding

    static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]                 // byte-stable: rebuilds compare equal
        return String(decoding: (try? encoder.encode(value)) ?? Data(), as: UTF8.self)
    }

    static func decodePool(_ json: String) -> PoolState? { try? JSONDecoder().decode(PoolState.self, from: Data(json.utf8)) }
}

func ms(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }
func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }

public enum StoreError: Error, Equatable {
    /// `ingest(_:session:connection:)` was given a connection the store never created.
    case unknownConnection
}
