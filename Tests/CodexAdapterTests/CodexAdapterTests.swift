import Domain
import Foundation
import Testing
@testable import CodexAdapter

/// Increment 3.4. Synthetic rollout lines in the shape Codex writes (surveyed 17 Oct 2026, key names only). Every
/// line that is not a token count carries a canary; none of it may reach a reading or an observation.
struct CodexAdapterTests {
    static let canary = "CANARY-PROMPT-7f3a /Users/someone/secret-project"

    static func tokenCount(at: String = "2026-10-17T18:00:00.000Z", primary: Double? = 44, secondary: Double? = 33,
                           primaryMinutes: Int = 300, plan: String? = "plus", input: Int = 48_397, limitID: String = "codex") -> String {
        func window(_ pct: Double?, _ minutes: Int, _ resets: Int) -> String {
            pct.map { #"{"used_percent":\#($0),"window_minutes":\#(minutes),"resets_at":\#(resets)}"# } ?? "null"
        }
        let planJSON = plan.map { "\"\($0)\"" } ?? "null"
        return #"{"timestamp":"\#(at)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":6016,"cache_write_input_tokens":0,"output_tokens":182,"reasoning_output_tokens":111,"total_tokens":48579},"model_context_window":258400},"rate_limits":{"limit_id":"\#(limitID)","limit_name":null,"primary":\#(window(primary, primaryMinutes, 1792171134)),"secondary":\#(window(secondary, 10080, 1792651827)),"plan_type":\#(planJSON),"credits":{"has_credits":false,"unlimited":false,"balance":"0"},"individual_limit":null,"spend_control_reached":null,"rate_limit_reached_type":null}}}"#
    }

    /// A thread's first line: ids and version up front, then Codex's instructions (here a canary) as Codex 0.163 writes it.
    static func sessionMeta(version: String = "0.163.0") -> String {
        #"{"timestamp":"2026-10-16T13:04:28.000Z","type":"session_meta","payload":{"id":"00000000-0000-7000-8000-000000000001","timestamp":"2026-10-16T13:04:28.000Z","cwd":"\#(canary)","originator":"codex-tui","cli_version":"\#(version)","source":"cli","base_instructions":{"text":"\#(canary) \"cli_version\":\"9.9.9\""}}}"#
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

    @Test("A window Codex reports as null is left out: never 0, and never a made-up \"primary\" or \"secondary\" pool")
    func missingWindowIsLeftOutNeverZero() throws {
        let r = try #require(CodexRollout.latest(in: Self.file([Self.tokenCount(primary: nil)])))
        #expect(r.primary == nil && r.secondary?.usedPct == 33)
        let obs = CodexMapper.observations(r, connectionID: UUID(), receivedAt: Date())
        #expect(Set(obs.map(\.subject)) == [.pool(providerPoolKey: "codex.rate_limits.seven_day")])
        #expect(!obs.contains { $0.value == .percent(0) })
    }

    @Test("A token count with both windows null says nothing about them: the reading before it stands")
    func tokenCountWithoutWindowsIsNotAReading() throws {
        let data = Self.file([Self.tokenCount(at: "2026-10-16T17:35:38.000Z", primary: 35),
                              Self.tokenCount(at: "2026-10-16T17:36:00.000Z", primary: nil, secondary: nil)])
        let r = try #require(CodexRollout.latest(in: data))
        #expect(r.primary?.usedPct == 35 && r.observedAt == CodexRollout.timestamp("2026-10-16T17:35:38.000Z"))
        #expect(CodexRollout.latest(in: Self.file([Self.tokenCount(primary: nil, secondary: nil)])) == nil)
    }

    /// Regression, founder's Mac 16 Oct 2026: Codex also reports other allowances in the same event. The newest event
    /// in a long session was "premium" with both windows null; an older one was "base_model_inference" with only a
    /// 10080-minute window. Neither is Codex's 5-hour or weekly limit.
    @Test func otherAllowancesNeverStandInForCodexsLimits() throws {
        let data = Self.file([Self.tokenCount(at: "2026-10-16T17:30:00.000Z", primary: 84, secondary: nil, primaryMinutes: 10_080,
                                              limitID: "base_model_inference"),
                              Self.tokenCount(at: "2026-10-16T17:36:11.000Z", primary: 36, secondary: 100),
                              Self.tokenCount(at: "2026-10-16T17:36:13.000Z", primary: nil, secondary: nil, plan: nil, limitID: "premium")])
        let r = try #require(CodexRollout.latest(in: data))
        #expect(r.limitID == "codex" && r.primary?.usedPct == 36 && r.secondary?.usedPct == 100)
        #expect(CodexRollout.latest(in: Self.file([Self.tokenCount(limitID: "premium")])) == nil)
        let keys = Set(CodexMapper.observations(r, connectionID: UUID(), receivedAt: Date()).map(\.subject))
        #expect(keys == [.pool(providerPoolKey: "codex.rate_limits.five_hour"), .pool(providerPoolKey: "codex.rate_limits.seven_day")])
    }

    /// A token count in the shape of the 9 Oct 2026 Reserve events (synthetic numbers): labelled "codex", one 10080-minute
    /// window in the primary slot, no 5-hour window, a reset of its own.
    static func reserveUnderCodexLabel(at: String, pct: Double, resets: Int = 1_791_783_900, limitID: String = "codex",
                                       limitName: String? = nil) -> String {
        let name = limitName.map { "\"\($0)\"" } ?? "null"
        return #"{"timestamp":"\#(at)","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"\#(limitID)","limit_name":\#(name),"primary":{"used_percent":\#(pct),"window_minutes":10080,"resets_at":\#(resets)},"secondary":null,"plan_type":"plus","credits":{"has_credits":false,"unlimited":false,"balance":"0"},"individual_limit":null,"spend_control_reached":null,"rate_limit_reached_type":null}}}"#
    }

    static func turnContext(model: String) -> String {
        #"{"timestamp":"2026-10-09T12:39:00.000Z","type":"turn_context","payload":{"model":"\#(model)","cwd":"\#(canary)"}}"#
    }

    /// Regression, founder's Mac 9 Oct 2026 12:39–12:42 UTC: after a switch to gpt-reserve ("Luna Reserve"), Codex wrote
    /// 11 token counts labelled "codex" carrying only a weekly window at 27–31% that belonged to the Reserve allowance
    /// (31% at 12:43 under "base_model_inference"). Codex's own weekly figure was 11%. They must never become Codex's
    /// weekly reading: the reading before them stands.
    @Test func reserveReadingsUnderCodexsLabelAreNotCodexsLimits() throws {
        let data = Self.file([Self.turnContext(model: "gpt-6-astra"),
                              Self.tokenCount(at: "2026-10-09T12:14:05.000Z", primary: 69, secondary: 11),
                              Self.turnContext(model: "gpt-reserve"),
                              Self.reserveUnderCodexLabel(at: "2026-10-09T12:39:34.000Z", pct: 27),
                              Self.reserveUnderCodexLabel(at: "2026-10-09T12:42:42.000Z", pct: 31),
                              Self.reserveUnderCodexLabel(at: "2026-10-09T12:43:52.000Z", pct: 31, limitID: "base_model_inference",
                                                          limitName: "gpt-reserve")])
        let r = try #require(CodexRollout.latest(in: data))
        #expect(r.observedAt == CodexRollout.timestamp("2026-10-09T12:14:05.000Z"))
        #expect(r.primary?.usedPct == 69 && r.secondary?.usedPct == 11 && r.model == "gpt-6-astra")
        let weekly = CodexMapper.observations(r, connectionID: UUID(), receivedAt: Date(timeIntervalSince1970: 1_791_600_000))
            .filter { $0.subject == .pool(providerPoolKey: "codex.rate_limits.seven_day") && $0.kind == .quotaUsedPct }
        #expect(weekly.map(\.value) == [.percent(11)])
        // Only the Reserve events in the tail: nothing of Codex's own to report.
        #expect(CodexRollout.latest(in: Self.file([Self.turnContext(model: "gpt-reserve"),
                                                   Self.reserveUnderCodexLabel(at: "2026-10-09T12:39:34.000Z", pct: 27)])) == nil)
    }

    @Test("Each rule alone catches a Reserve reading: by its turn's model, and by a weekly window that isn't Codex's own")
    func reserveReadingsAreCaughtByEitherField() throws {
        let before = Self.tokenCount(at: "2026-10-09T12:14:05.000Z", primary: 69, secondary: 11)   // weekly resets 22 Oct
        // Model unknown (its turn_context fell outside the tail): the weekly window's reset (ten days before Codex's,
        // whose window is still open) gives it away.
        let byReset = try #require(CodexRollout.latest(in: Self.file([before, Self.reserveUnderCodexLabel(at: "2026-10-09T12:39:34.000Z", pct: 27)])))
        #expect(byReset.secondary?.usedPct == 11)
        // Model renamed, but another bucket names it as its own: its turns' readings are that bucket's.
        let renamed = Self.file([Self.turnContext(model: "gpt-reserve-2"),
                                 Self.reserveUnderCodexLabel(at: "2026-10-09T12:39:34.000Z", pct: 27, resets: 1_792_651_827),
                                 Self.reserveUnderCodexLabel(at: "2026-10-09T12:43:52.000Z", pct: 31, limitID: "base_model_inference",
                                                             limitName: "gpt-reserve-2")])
        #expect(CodexRollout.latest(in: renamed) == nil)
        // The rules leave Codex's own weekly-only readings alone: one matching Codex's weekly window (a few seconds of
        // jitter, as Codex reports), and one with nothing earlier to compare with.
        let matching = Self.file([before, Self.reserveUnderCodexLabel(at: "2026-10-09T12:39:34.000Z", pct: 12, resets: 1_792_651_829)])
        #expect(CodexRollout.latest(in: matching)?.primary?.usedPct == 12)
        #expect(CodexRollout.latest(in: Self.file([Self.reserveUnderCodexLabel(at: "2026-10-09T12:39:34.000Z", pct: 27)]))?.primary?.usedPct == 27)
        // Once Codex's weekly window has reset (22 Oct 06:50), a new weekly reset is Codex's next window.
        let afterReset = Self.file([before, Self.reserveUnderCodexLabel(at: "2026-10-23T12:00:00.000Z", pct: 3, resets: 1_793_300_000)])
        #expect(CodexRollout.latest(in: afterReset)?.primary?.usedPct == 3)
    }

    @Test("Codex sometimes writes a token count without its plan: the plan from earlier in the file stands")
    func planCarriesOverAMissingOne() throws {
        let data = Self.file([Self.tokenCount(at: "2026-10-16T17:35:13.000Z", primary: 34),
                              Self.tokenCount(at: "2026-10-16T17:35:38.000Z", primary: 35, plan: nil)])
        let r = try #require(CodexRollout.latest(in: data))
        #expect(r.primary?.usedPct == 35 && r.plan == "plus")
    }

    @Test("Codex's version comes from the first line's head by its bytes; the instructions after it are never read")
    func versionFromTheSessionHead() {
        let head = Data(Self.sessionMeta().utf8)
        #expect(CodexRollout.version(inHead: head) == "0.163.0")
        #expect(CodexRollout.version(inHead: Data(Self.message.utf8)) == nil)                // not a session_meta line
        #expect(CodexRollout.version(inHead: Data(Self.sessionMeta(version: "0.1 rm -rf").utf8)) == nil)  // not a plain value
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

    /// Regression, founder's Mac 16 Oct 2026: the newest reading (36%) sat in a session started three days earlier and
    /// still being written, while that day's folder held dozens of finished sessions. The reader stopped listing at the
    /// first folders that gave it a dozen files and showed 35% from one of them.
    @Test func readerFindsTheNewestReadingInASessionStartedDaysAgo() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("codex-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_792_172_220)                        // 2026-10-16 17:37 UTC
        let sessions = CodexReader.sessionsURL(home: home)
        let today = sessions.appendingPathComponent(dayPath(now, cal))
        let started = sessions.appendingPathComponent(dayPath(now.addingTimeInterval(-3 * 86_400), cal))
        for dir in [today, started] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        for n in 0..<16 {                                                           // today's finished sessions, older readings
            let url = today.appendingPathComponent("rollout-today-\(n).jsonl")
            try Self.file([Self.sessionMeta(), Self.tokenCount(at: "2026-10-16T17:\(10 + n):00.000Z", primary: Double(10 + n))]).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(Double(-1800 + n * 60))], ofItemAtPath: url.path)
        }
        let long = started.appendingPathComponent("rollout-long.jsonl")
        try Self.file([Self.sessionMeta(version: "0.162.1"), Self.message, Self.tokenCount(at: "2026-10-16T17:36:11.010Z", primary: 36, secondary: 100),
                       Self.tokenCount(at: "2026-10-16T17:36:13.998Z", primary: nil, secondary: nil, plan: nil, limitID: "premium")]).write(to: long)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-46)], ofItemAtPath: long.path)
        let r = try #require(CodexReader.latest(home: home, now: now, calendar: cal))
        #expect(r.primary?.usedPct == 36 && r.secondary?.usedPct == 100 && r.limitID == "codex")
        #expect(r.version == "0.162.1")
        #expect(!String(describing: r).contains("CANARY"))
    }

    @Test func noCodexFolderMeansNoReading() {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("none-\(UUID().uuidString)")
        #expect(!CodexReader.isInstalled(home: home))
        #expect(CodexReader.latest(home: home, now: Date()) == nil)
    }

    @Test("Item 8: timestamps come from one shared parser, with or without fractional seconds, safely from many threads")
    func sharedTimestampParser() async {
        let at = Date(timeIntervalSince1970: 1_792_260_000)
        #expect(CodexRollout.timestamp("2026-10-17T18:00:00.250Z") == at.addingTimeInterval(0.25))
        #expect(CodexRollout.timestamp("2026-10-17T18:00:00Z") == at)
        #expect(CodexRollout.timestamp("2026-10-17T19:00:00+01:00") == at)
        #expect(CodexRollout.timestamp("yesterday") == nil && CodexRollout.timestamp(42) == nil)
        // A background scan and a tail read parse at the same time.
        let results = await withTaskGroup(of: Bool.self) { group in
            for i in 0..<64 {
                group.addTask { CodexRollout.timestamp(i.isMultiple(of: 2) ? "2026-10-17T18:00:00.000Z" : "2026-10-17T18:00:00Z") == at }
            }
            return await group.reduce(into: [Bool]()) { $0.append($1) }
        }
        #expect(results.count == 64 && results.allSatisfy { $0 })
    }

    func dayPath(_ date: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d/%02d/%02d", c.year!, c.month!, c.day!)
    }
}
