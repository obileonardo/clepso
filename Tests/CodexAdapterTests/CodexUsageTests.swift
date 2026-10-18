@testable import CodexAdapter
import Foundation
import Testing

/// Increment 3.4b: Codex's tokens per day and model, from how each thread's running total grew.
struct CodexUsageTests {
    let utc = TimeZone(identifier: "UTC")!

    func count(_ at: String, input: Int, output: Int, cached: Int = 0) -> String {
        #"{"timestamp":"\#(at)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"output_tokens":\#(output),"reasoning_output_tokens":0,"total_tokens":\#(input + output)}},"rate_limits":null}}"#
    }
    func context(_ model: String) -> String { #"{"timestamp":"2026-10-16T09:00:00Z","type":"turn_context","payload":{"model":"\#(model)"}}"# }
    let prompt = #"{"timestamp":"2026-10-16T09:00:01Z","type":"response_item","payload":{"type":"message","content":"token_count secret prompt"}}"#

    func home(_ files: [String: [String]]) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("codex-usage-\(UUID().uuidString)")
        for (name, lines) in files {
            let url = CodexReader.sessionsURL(home: home).appendingPathComponent("2026/10/16/rollout-\(name).jsonl")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
        return home
    }

    @Test func growthPerDayAndModelAcrossThreads() throws {
        let home = try home([
            "a": [context("gpt-5-codex"), count("2026-10-16T09:00:00Z", input: 100, output: 10), prompt,
                  count("2026-10-16T23:59:00Z", input: 300, output: 30), count("2026-10-17T00:01:00Z", input: 350, output: 40)],
            "sub": [context("gpt-5-codex"), count("2026-10-17T10:00:00Z", input: 50, output: 5)],
        ])
        defer { try? FileManager.default.removeItem(at: home) }
        var usage = CodexUsage(zone: utc)
        usage.scan(home: home)
        #expect(usage.days.map(\.day) == ["2026-10-16", "2026-10-17"])
        #expect(usage.days.map(\.tokens.sum) == [330, 115], "16th: 330; 17th: a grew 60, the sub-agent 55")
        #expect(usage.days.allSatisfy { $0.model == "gpt-5-codex" })
    }

    @Test func appendedLinesAreReadOnceAndHalfLinesWait() throws {
        let home = try home(["a": [count("2026-10-16T09:00:00Z", input: 100, output: 10)]])
        defer { try? FileManager.default.removeItem(at: home) }
        let url = CodexReader.sessionsURL(home: home).appendingPathComponent("2026/10/16/rollout-a.jsonl")
        var usage = CodexUsage(zone: utc)
        usage.scan(home: home)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        let next = count("2026-10-16T10:00:00Z", input: 200, output: 20)
        try handle.write(contentsOf: Data(next.prefix(40).utf8))                // Codex mid-write
        usage.scan(home: home)
        #expect(usage.days.map(\.tokens.sum) == [110])
        try handle.write(contentsOf: Data((next.dropFirst(40) + "\n").utf8))
        try handle.close()
        usage.scan(home: home)
        usage.scan(home: home)                                                  // nothing new: nothing added twice
        #expect(usage.days.map(\.tokens.sum) == [220])
    }

    @Test func aDroppedTotalStartsAFreshCountAndUnknownModelsStayUnnamed() throws {
        let home = try home(["a": [count("2026-10-16T09:00:00Z", input: 500, output: 50), count("2026-10-16T10:00:00Z", input: 20, output: 2)]])
        defer { try? FileManager.default.removeItem(at: home) }
        var usage = CodexUsage(zone: utc)
        usage.scan(home: home)
        #expect(usage.days.map(\.tokens.sum) == [572])
        #expect(usage.days.first?.model == nil)
    }
}
