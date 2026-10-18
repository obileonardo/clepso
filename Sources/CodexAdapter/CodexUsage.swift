import Foundation

/// Codex's tokens per day and model (increment 3.4b), for Stats. Codex writes a running total (`total_token_usage`)
/// after every turn; a thread's tokens on a day are how much that total grew on it. Every thread has its own file
/// (sub-agents too, each starting from zero), so summing every file's growth counts each token once.
///
/// Reading whole files is new for Codex (the limits reader reads tails only), so the same rules hold more strictly:
/// a line is decoded only when its bytes contain `"token_count"` or `"turn_context"` and it is short enough to be
/// one; every other line, where prompts and replies are, is skipped without decoding. Files are read once: each
/// file's position is kept, and later scans read only what Codex appended.
public struct CodexUsage: Sendable {
    public typealias Tokens = CodexReading.Tokens

    /// One day's tokens for one model (`model` nil when the thread never said).
    public struct Day: Sendable, Equatable {
        public let day: String
        public let model: String?
        public let tokens: Tokens
    }

    struct FileState: Sendable {
        var offset: UInt64 = 0
        var total: Tokens?
        var model: String?
        var byDay: [String: [String: Tokens]] = [:]      // day → model ("" when unknown) → tokens
    }

    var files: [String: FileState] = [:]
    let zone: TimeZone

    public init(zone: TimeZone) { self.zone = zone }

    /// Reads what's new in every session file under `home`. Cheap after the first call.
    public mutating func scan(home: URL) {
        let root = CodexReader.sessionsURL(home: home)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return }
        for case let url as URL in walker where url.lastPathComponent.hasPrefix("rollout-") && url.pathExtension == "jsonl" {
            update(url)
        }
    }

    /// Every day and model, oldest first.
    public var days: [Day] {
        var merged: [String: [String: Tokens]] = [:]
        for file in files.values {
            for (day, models) in file.byDay {
                for (model, t) in models { merged[day, default: [:]][model] = (merged[day]?[model]).map { $0 + t } ?? t }
            }
        }
        return merged.keys.sorted().flatMap { day in
            merged[day]!.keys.sorted().map { Day(day: day, model: $0.isEmpty ? nil : $0, tokens: merged[day]![$0]!) }
        }
    }

    mutating func update(_ url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        var state = files[url.path] ?? FileState()
        if size < state.offset { state = FileState() }                // rewritten, not appended: start this file over
        guard size > state.offset else { files[url.path] = state; return }
        try? handle.seek(toOffset: state.offset)
        let chunk = 4 * 1024 * 1024
        var carry = Data()
        while let data = try? handle.read(upToCount: chunk), !data.isEmpty {
            carry.append(data)
            guard let lastNewline = carry.lastIndex(of: UInt8(ascii: "\n")) else { continue }
            let complete = carry[carry.startIndex...lastNewline]
            consume(complete, into: &state)
            state.offset += UInt64(complete.count)
            carry = Data(carry[carry.index(after: lastNewline)...])
        }
        files[url.path] = state                                        // a line still being written is read next time
    }

    func consume(_ data: Data.SubSequence, into state: inout FileState) {
        for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) where line.count <= CodexRollout.maxLine {
            if CodexRollout.contains(line, #""turn_context""#) {
                if let m = CodexRollout.decodeModel(Data(line)) { state.model = m }
            } else if CodexRollout.contains(line, #""token_count""#), let (at, total) = Self.decodeTotal(Data(line)) {
                let grown = state.total.map { total.isAtLeast($0) ? total - $0 : total } ?? total   // a drop: a fresh count
                state.total = total
                guard grown.sum > 0 else { continue }
                let day = Self.dayLabel(at, zone: zone), model = state.model ?? ""
                state.byDay[day, default: [:]][model] = (state.byDay[day]?[model]).map { $0 + grown } ?? grown
            }
        }
    }

    static func decodeTotal(_ line: Data) -> (Date, Tokens)? {
        guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any], root["type"] as? String == "event_msg",
              let payload = root["payload"] as? [String: Any], payload["type"] as? String == "token_count",
              let at = CodexRollout.timestamp(root["timestamp"]),
              let t = (payload["info"] as? [String: Any])?["total_token_usage"] as? [String: Any],
              let input = CodexRollout.count(t["input_tokens"]), let output = CodexRollout.count(t["output_tokens"]) else { return nil }
        return (at, Tokens(input: input, cachedInput: CodexRollout.count(t["cached_input_tokens"]) ?? 0,
                           cacheWrite: CodexRollout.count(t["cache_write_input_tokens"]) ?? 0, output: output,
                           reasoningOutput: CodexRollout.count(t["reasoning_output_tokens"]) ?? 0))
    }

    static func dayLabel(_ date: Date, zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

extension CodexReading.Tokens {
    public static let zero = Self(input: 0, cachedInput: 0, cacheWrite: 0, output: 0, reasoningOutput: 0)
    /// Codex's own `total_tokens`: input (cached input is part of it) plus output (reasoning is part of it).
    public var sum: Int64 { input + output }

    static func + (a: Self, b: Self) -> Self {
        Self(input: a.input + b.input, cachedInput: a.cachedInput + b.cachedInput, cacheWrite: a.cacheWrite + b.cacheWrite,
             output: a.output + b.output, reasoningOutput: a.reasoningOutput + b.reasoningOutput)
    }
    static func - (a: Self, b: Self) -> Self {
        Self(input: a.input - b.input, cachedInput: a.cachedInput - b.cachedInput, cacheWrite: a.cacheWrite - b.cacheWrite,
             output: a.output - b.output, reasoningOutput: a.reasoningOutput - b.reasoningOutput)
    }
    func isAtLeast(_ b: Self) -> Bool {
        input >= b.input && cachedInput >= b.cachedInput && cacheWrite >= b.cacheWrite && output >= b.output && reasoningOutput >= b.reasoningOutput
    }
}
