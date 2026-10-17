import Domain
import Foundation
import Testing
@testable import CodexAdapter

/// Increment 3.4. Synthetic rollout lines in the shape Codex writes (surveyed 17 Oct 2026, key names only). Every
/// line that is not a token count carries a canary; none of it may reach a reading or an observation.
struct CodexAdapterTests {
    static let canary = "CANARY-PROMPT-7f3a /Users/someone/secret-project"

    static func tokenCount(at: String = "2026-10-17T18:00:00.000Z", primary: Double? = 44, secondary: Double? = 33,
                           primaryMinutes: Int = 300, plan: String? = "plus", input: Int = 48_397) -> String {
        func window(_ pct: Double?, _ minutes: Int, _ resets: Int) -> String {
            pct.map { #"{"used_percent":\#($0),"window_minutes":\#(minutes),"resets_at":\#(resets)}"# } ?? "null"
        }
        let planJSON = plan.map { "\"\($0)\"" } ?? "null"
        return #"{"timestamp":"\#(at)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":6016,"cache_write_input_tokens":0,"output_tokens":182,"reasoning_output_tokens":111,"total_tokens":48579},"model_context_window":258400},"rate_limits":{"limit_id":"codex","primary":\#(window(primary, primaryMinutes, 1792171134)),"secondary":\#(window(secondary, 10080, 1792651827)),"plan_type":\#(planJSON),"credits":{"has_credits":false,"unlimited":false,"balance":"0"}}}}"#
    }

    static let turnContext = #"{"timestamp":"2026-10-17T17:59:00.000Z","type":"turn_context","payload":{"model":"gpt-5-codex","cwd":"\#(canary)","user_instructions":"\#(canary)"}}"#
    static let message = #"{"timestamp":"2026-10-17T17:59:30.000Z","type":"response_item","payload":{"type":"message","content":[{"type":"input_text","text":"\#(canary) token_count rate_limits"}]}}"#

    static func file(_ lines: [String]) -> Data { Data((lines.joined(separator: "\n") + "\n").utf8) }

    @Test func readsLimitsPlanTokensAndModel() throws {
        let r = try #require(CodexRollout.latest(in: Self.file([Self.turnContext, Self.message, Self.tokenCount()])))
        #expect(r.primary == .init(usedPct: 44, windowMinutes: 300, resetsAt: Date(timeIntervalSince1970: 1792171134)))
        #expect(r.secondary?.usedPct == 33 && r.secondary?.windowMinutes == 10_080)
        #expect(r.plan == "plus" && r.limitID == "codex" && r.model == "gpt-5-codex")
        #expect(r.sessionTokens == .init(input: 48_397, cachedInput: 6016, cacheWrite: 0, output: 182, reasoningOutput: 111))
        #expect(r.contextWindow == 258_400)
    }

    @Test func latestTokenCountWins() throws {
        let data = Self.file([Self.tokenCount(at: "2026-10-17T18:00:00.000Z", primary: 10),
                              Self.tokenCount(at: "2026-10-17T18:05:00.000Z", primary: 12)])
        #expect(CodexRollout.latest(in: data)?.primary?.usedPct == 12)
    }

    @Test func promptTextNeverReachesAReading() throws {
        let r = try #require(CodexRollout.latest(in: Self.file([Self.message, Self.turnContext, Self.tokenCount()])))
        #expect(!String(describing: r).contains("CANARY"))
        let obs = CodexMapper.observations(r, connectionID: UUID(), receivedAt: Date())
        #expect(!String(describing: obs).contains("CANARY") && !String(describing: obs).contains("secret-project"))
    }

    @Test func messagesThatMentionTokenCountAreNotReadings() {
        // A user message containing the words is a response_item, never an event_msg token count.
        #expect(CodexRollout.latest(in: Self.file([Self.message])) == nil)
    }

    @Test func cutFirstLineAndGarbageAreSkipped() throws {
        let full = Self.tokenCount()
        let cut = String(full.dropFirst(40))
        let r = CodexRollout.latest(in: Self.file([cut, "not json", "{\"type\":\"event_msg\"}", full]))
        #expect(r?.primary?.usedPct == 44)
        #expect(CodexRollout.latest(in: Self.file([cut])) == nil)
    }

    @Test func missingWindowIsAbsentNeverZero() throws {
        let r = try #require(CodexRollout.latest(in: Self.file([Self.tokenCount(primary: nil)])))
        #expect(r.primary == nil)
        let obs = CodexMapper.observations(r, connectionID: UUID(), receivedAt: Date())
        let used = obs.filter { $0.kind == .quotaUsedPct }
        #expect(used.contains { $0.value == .absent(.providerNull) && $0.subject == .pool(providerPoolKey: "codex.rate_limits.primary") })
        #expect(!used.contains { $0.value == .percent(0) })
    }

    @Test func implausibleValuesAreDropped() throws {
        var line = Self.tokenCount(plan: "plus; rm -rf /")
        line = line.replacingOccurrences(of: #""resets_at":1792171134"#, with: #""resets_at":12"#)
        let r = try #require(CodexRollout.latest(in: Self.file([line])))
        #expect(r.plan == nil)                     // not an identifier
        #expect(r.primary?.resetsAt == nil)        // 1970 is not a reset time
        #expect(r.primary?.usedPct == 44)
    }

    @Test func poolKeysFollowWindowLength() {
        #expect(CodexMapper.poolKey(.init(usedPct: 1, windowMinutes: 300, resetsAt: nil), fallback: "primary") == "codex.rate_limits.five_hour")
        #expect(CodexMapper.poolKey(.init(usedPct: 1, windowMinutes: 10_080, resetsAt: nil), fallback: "secondary") == "codex.rate_limits.seven_day")
        #expect(CodexMapper.poolKey(.init(usedPct: 1, windowMinutes: 60, resetsAt: nil), fallback: "primary") == "codex.rate_limits.window_60m")
    }

    @Test func observationsMatchTheStatusLineShape() throws {
        let r = try #require(CodexRollout.latest(in: Self.file([Self.tokenCount()])))
        let id = UUID(), at = Date(timeIntervalSince1970: 1_792_000_000)
        let obs = CodexMapper.observations(r, connectionID: id, receivedAt: at)
        #expect(obs.count == 4)
        #expect(obs.allSatisfy { $0.evidence == .officialLocalTelemetry && $0.receivedAt == at && $0.sessionRef == nil })
        #expect(Set(obs.map(\.dedupeKey)).count == 4)
        // Same reading, same keys: re-reading the file never duplicates the ledger.
        #expect(obs.map(\.dedupeKey) == CodexMapper.observations(r, connectionID: id, receivedAt: at.addingTimeInterval(30)).map(\.dedupeKey))
    }

    @Test func readerFindsNewestFileAndReadsOnlyItsTail() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("codex-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_792_000_000)              // 2026-10-15 UTC
        let today = CodexReader.sessionsURL(home: home).appendingPathComponent(dayPath(now, cal))
        let old = CodexReader.sessionsURL(home: home).appendingPathComponent(dayPath(now.addingTimeInterval(-20 * 86_400), cal))
        for dir in [today, old] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        // A big file whose head is all prompts: the tail read must still find the last token count.
        let padding = Array(repeating: Self.message, count: 4000)
        try Self.file(padding + [Self.tokenCount(primary: 61)]).write(to: today.appendingPathComponent("rollout-a.jsonl"))
        try Self.file([Self.tokenCount(primary: 99)]).write(to: old.appendingPathComponent("rollout-old.jsonl"))
        #expect(CodexReader.isInstalled(home: home))
        #expect(CodexReader.latest(home: home, now: now, calendar: cal)?.primary?.usedPct == 61)
        #expect(CodexReader.tail(today.appendingPathComponent("rollout-a.jsonl")).count == CodexReader.tailBytes)
    }

    @Test func noCodexFolderMeansNoReading() {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("none-\(UUID().uuidString)")
        #expect(!CodexReader.isInstalled(home: home))
        #expect(CodexReader.latest(home: home, now: Date()) == nil)
    }

    func dayPath(_ date: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d/%02d/%02d", c.year!, c.month!, c.day!)
    }
}
