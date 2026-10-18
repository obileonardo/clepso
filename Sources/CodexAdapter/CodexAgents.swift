import Foundation

/// Agents per task for Codex (item 4), from Codex's own session files, read in the same pass as `CodexUsage`.
///
/// Codex writes one file per thread: the user's own threads and every sub-agent thread, each with its own
/// `rollout-*.jsonl`. Every turn starts with a `task_started` event and ends with `task_complete` or `turn_aborted`.
/// Since multi-agent v2, `task_started` carries Codex's own attribution: the turn's `parent_turn_id` (none for a turn
/// the user started) and its `root_turn_id`, the user's turn that set it off however deep the sub-agent is.
///
/// - A **task** is one turn of a top-level thread (no parent turn): from its `task_started` until its `task_complete`
///   or `turn_aborted`, or until the thread's next turn starts if Codex never wrote either.
/// - A task's **agents** are the sub-agent threads Codex spawned for it (`session_meta.source.subagent.thread_spawn`):
///   a thread belongs to the task its first own turn names as root. A sub-agent reused in a later task still counts
///   once, under the task that spawned it. **Finished**: every turn it ran for that task has ended.
/// - Codex's approval auto-reviews (the `guardian` sub-agent, turns triggered by `guardian_review`) are counted per
///   task as **reviews**, not as agents, the way Claude Code's internal agents are left out on its side.
/// - Spawned threads begin with a copy of their parent's history: lines numbered below the thread's
///   `subagent_history_start_ordinal` are the parent's and are skipped.
/// - A root turn whose own file is missing still gets a task, built from its sub-agents (`fromPrompt` false).
///
/// Privacy (PRIVACY_AND_SECURITY §4.3): nothing here is JSON-decoded. `session_meta` also holds Codex's instructions,
/// the working folder, git details and account ids, and `task_complete` holds the final reply, so instead of decoding
/// a line and dropping most of it, the reader looks up a few keys by their bytes and reads only short plain values
/// (`CodexBytes`). An unescaped `"key":` can only be a JSON key, never text inside a string, where quotes are escaped.
/// Kept: turn ids, times, the agent's role (built-in names; anything else becomes "custom") and counts. Never read:
/// prompts, replies, paths, agent nicknames and paths, instructions.
public struct CodexAgents: Sendable {
    public struct Task: Sendable, Equatable, Identifiable {
        /// Codex's turn id; in memory only, never shown.
        public let id: String
        public let startedAt: Date
        public let endedAt: Date?
        /// False when the user's turn wasn't found (its file is gone) and the task is known only from its agents.
        public let fromPrompt: Bool
        /// Spawned agents by role: `roles` or `customRole`.
        public let byRole: [String: Int]
        public let finished: Int
        /// Approval auto-reviews Codex ran during the task; not agents.
        public let reviews: Int
        public var agents: Int { byRole.values.reduce(0, +) }

        public init(id: String, startedAt: Date, endedAt: Date?, fromPrompt: Bool, byRole: [String: Int], finished: Int, reviews: Int) {
            self.id = id
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.fromPrompt = fromPrompt
            self.byRole = byRole
            self.finished = finished
            self.reviews = reviews
        }
    }

    /// Codex's built-in agent roles (`agent_role`; none means `default`). Roles the user defines become `customRole`.
    public static let roles: Set<String> = ["default", "explorer", "worker", "awaiter"]
    public static let customRole = "custom"

    enum Thread: Sendable, Equatable { case main, spawned(role: String), other }

    struct Turn: Sendable {
        let id: String
        let root: String?                  // nil: written by a Codex without turn attribution
        let topLevel: Bool
        let review: Bool
        let start: Date
        var end: Date?
    }

    struct FileState: Sendable {
        var started = false                // the first line has been seen
        var thread: Thread?                // nil: the first line wasn't a `session_meta` Clepso could read
        var historyStart: Int64 = 0
        var turns: [Turn] = []
        var index: [String: Int] = [:]
    }

    var files: [String: FileState] = [:]

    public init() {}

    /// Reads complete lines appended to `file` (the caller keeps the offset; the first call starts at the file's start).
    /// Lines are found with `memchr` and looked at in place, without copying: the first read covers every session file.
    mutating func read(_ data: Data, file: String) {
        var state = files[file] ?? FileState()
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            var start = 0
            while start < raw.count {
                let end = memchr(base + start, 0x0A, raw.count - start).map { base.distance(to: UnsafeRawPointer($0)) } ?? raw.count
                if end > start { Self.consume(UnsafeRawBufferPointer(rebasing: raw[start..<end]), into: &state) }
                start = end + 1
            }
        }
        files[file] = state
    }

    /// The file was rewritten rather than appended to: forget it, so it is read again from the start.
    mutating func forget(_ file: String) { files[file] = nil }

    /// Event lines put their type in the first few hundred bytes (`timestamp`, `ordinal`, `type`, then the payload's
    /// `type` and ids); only that head is searched, so long lines (replies, tool output) are never scanned.
    static let head = 512

    static func consume(_ line: UnsafeRawBufferPointer, into state: inout FileState) {
        if !state.started {
            state.started = true
            if CodexBytes.find(Key.sessionMeta, in: line, limit: head) != nil { readMeta(line, into: &state); return }
        }
        guard CodexBytes.find(Key.eventMsg, in: line, limit: head) != nil else { return }
        let started = CodexBytes.find(Key.taskStarted, in: line, limit: head) != nil
        guard started || CodexBytes.find(Key.taskComplete, in: line, limit: head) != nil
            || CodexBytes.find(Key.turnAborted, in: line, limit: head) != nil else { return }
        // A spawned thread's copy of its parent's history isn't its own.
        if case .int(let ordinal)? = CodexBytes.scalar(Key.ordinal, in: line, limit: head), ordinal < state.historyStart { return }
        guard case .string(let id)? = CodexBytes.scalar(Key.turnID, in: line, limit: head),
              case .string(let stamp)? = CodexBytes.scalar(Key.timestamp, in: line, limit: head),
              let at = CodexRollout.timestamp(stamp) else { return }
        if started {
            guard state.index[id] == nil else { return }
            // `task_started` is short (ids and numbers), so the whole line is searched for its attribution.
            let parent = CodexBytes.scalar(Key.parentTurnID, in: line, limit: line.count)
            let topLevel = parent.map { $0 == .null } ?? (state.thread == .main || state.thread == nil)
            var root: String?
            if case .string(let r)? = CodexBytes.scalar(Key.rootTurnID, in: line, limit: line.count) { root = r }
            let review = CodexBytes.scalar(Key.trigger, in: line, limit: line.count) == .string("guardian_review")
            state.index[id] = state.turns.count
            state.turns.append(Turn(id: id, root: topLevel ? (root ?? id) : root, topLevel: topLevel, review: review, start: at))
        } else if let i = state.index[id], state.turns[i].end == nil {
            state.turns[i].end = at
        }
    }

    /// The thread's kind and where its own history starts. The line is about 20 KB, almost all of it instructions;
    /// three keys are looked up by their bytes and nothing else is read.
    static func readMeta(_ line: UnsafeRawBufferPointer, into state: inout FileState) {
        if case .int(let start)? = CodexBytes.scalar(Key.historyStart, in: line, limit: line.count) { state.historyStart = start }
        if CodexBytes.find(Key.threadSpawn, in: line, limit: line.count) != nil {
            let role: String = switch CodexBytes.scalar(Key.agentRole, in: line, limit: line.count) {
            case .string(let r)?: roles.contains(r) ? r : customRole
            default: "default"
            }
            state.thread = .spawned(role: role)
        } else {
            state.thread = CodexBytes.find(Key.subagent, in: line, limit: line.count) != nil ? .other : .main
        }
    }

    /// Every task, newest first.
    public var tasks: [Task] {
        struct Draft { var start: Date; var end: Date?; var fromPrompt: Bool; var open = false
                       var byRole: [String: Int] = [:]; var finished = 0; var reviews = 0 }
        var drafts: [String: Draft] = [:]
        // The user's turns: one task each. A turn Codex never closed ends when the thread's next turn starts.
        for file in files.values {
            let top = file.turns.filter(\.topLevel).sorted { $0.start < $1.start }
            for (n, turn) in top.enumerated() where drafts[turn.id] == nil {
                drafts[turn.id] = Draft(start: turn.start, end: turn.end ?? (n + 1 < top.count ? top[n + 1].start : nil), fromPrompt: true)
            }
        }
        // Folds a sub-agent's or reviewer's turn into its root's task, opening one when the user's turn wasn't found.
        func touch(_ root: String, _ turn: Turn) {
            if drafts[root] == nil { drafts[root] = Draft(start: turn.start, end: turn.end, fromPrompt: false) }
            guard !drafts[root]!.fromPrompt else { return }
            drafts[root]!.start = min(drafts[root]!.start, turn.start)
            if let end = turn.end { drafts[root]!.end = max(drafts[root]!.end ?? end, end) } else { drafts[root]!.open = true }
        }
        for file in files.values {
            for turn in file.turns where turn.review {
                guard let root = turn.root else { continue }
                touch(root, turn)
                drafts[root]!.reviews += 1
            }
            // A sub-agent thread: spawned, or of unknown kind with sub-agent turns. It counts once, for its first turn's root.
            let role: String
            switch file.thread {
            case .spawned(let r): role = r
            case nil: role = "default"
            case .main?, .other?: continue
            }
            let own = file.turns.filter { !$0.topLevel && !$0.review }
            guard let first = own.first, let root = first.root else { continue }
            let forTask = own.filter { $0.root == root }
            for turn in forTask { touch(root, turn) }
            drafts[root]!.byRole[role, default: 0] += 1
            if forTask.allSatisfy({ $0.end != nil }) { drafts[root]!.finished += 1 }
        }
        return drafts.map { id, d in
            Task(id: id, startedAt: d.start, endedAt: d.open ? nil : d.end, fromPrompt: d.fromPrompt, byRole: d.byRole,
                 finished: d.finished, reviews: d.reviews)
        }
        .sorted { ($0.startedAt, $0.id) > ($1.startedAt, $1.id) }
    }

    /// The byte patterns looked up. Codex writes compact JSON (`"key":value`, no spaces).
    enum Key {
        static let sessionMeta = Array(#""type":"session_meta""#.utf8)
        static let eventMsg = Array(#""type":"event_msg""#.utf8)
        static let taskStarted = Array(#""type":"task_started""#.utf8)
        static let taskComplete = Array(#""type":"task_complete""#.utf8)
        static let turnAborted = Array(#""type":"turn_aborted""#.utf8)
        static let ordinal = Array(#""ordinal":"#.utf8)
        static let timestamp = Array(#""timestamp":"#.utf8)
        static let turnID = Array(#""turn_id":"#.utf8)
        static let parentTurnID = Array(#""parent_turn_id":"#.utf8)
        static let rootTurnID = Array(#""root_turn_id":"#.utf8)
        static let trigger = Array(#""turn_trigger":"#.utf8)
        static let historyStart = Array(#""subagent_history_start_ordinal":"#.utf8)
        static let threadSpawn = Array(#""thread_spawn":"#.utf8)
        static let subagent = Array(#""subagent":"#.utf8)
        static let agentRole = Array(#""agent_role":"#.utf8)
    }
}

/// Byte-level lookups in one JSON line, for lines Clepso must not decode (see `CodexAgents`).
enum CodexBytes {
    enum Scalar: Sendable, Equatable { case string(String), int(Int64), null }

    /// The offset of `needle` within the first `limit` bytes of `line`.
    static func find(_ needle: [UInt8], in line: UnsafeRawBufferPointer, limit: Int) -> Int? {
        let count = min(line.count, limit)
        guard count >= needle.count, let base = line.baseAddress else { return nil }
        return needle.withUnsafeBytes { n -> Int? in
            guard let hit = memmem(base, count, n.baseAddress, n.count) else { return nil }
            return base.distance(to: UnsafeRawPointer(hit))
        }
    }

    /// The value after the first `key` (a `"name":` pattern) that starts within the first `limit` bytes: null, an
    /// integer, or a string of at most 64 letters, digits and `.`, `_`, `:`, `+`, `-`. Anything else (escapes, other
    /// characters, longer text, objects, arrays) is nil, so free text can't come back through here.
    static func scalar(_ key: [UInt8], in raw: UnsafeRawBufferPointer, limit: Int) -> Scalar? {
        guard let at = find(key, in: raw, limit: limit) else { return nil }
        var i = at + key.count
        guard i < raw.count else { return nil }
        switch raw[i] {
        case UInt8(ascii: "\""):
            let start = i + 1
            i = start
            while i < raw.count, raw[i] != UInt8(ascii: "\"") {
                guard i - start < 64, allowed(raw[i]) else { return nil }
                i += 1
            }
            guard i < raw.count, i > start else { return nil }
            return .string(String(decoding: raw[start..<i], as: UTF8.self))
        case UInt8(ascii: "n"):
            return raw.count >= i + 4 && Array(raw[i..<(i + 4)]) == Array("null".utf8) ? .null : nil
        case UInt8(ascii: "0")...UInt8(ascii: "9"):
            var value: Int64 = 0
            while i < raw.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(raw[i]) {
                guard value < 100_000_000_000_000 else { return nil }
                value = value * 10 + Int64(raw[i] - UInt8(ascii: "0"))
                i += 1
            }
            return .int(value)
        default:
            return nil
        }
    }

    static func allowed(_ b: UInt8) -> Bool {
        switch b {
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: ":"), UInt8(ascii: "+"), UInt8(ascii: "-"): true
        default: false
        }
    }
}
