import CodexAdapter
import Foundation
import Testing
@testable import PulseApp

/// Increment 3.4b in the app: Codex's tokens per day are read in the background while Codex is on, and dropped when off.
@MainActor
struct CodexUsageModelTests {
    @Test func readWhileOnDroppedWhenOff() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let file = CodexReader.sessionsURL(home: box.home).appendingPathComponent("2026/10/16/rollout-a.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let line = #"{"timestamp":"2026-10-16T09:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1200,"cached_input_tokens":200,"output_tokens":34,"reasoning_output_tokens":4,"total_tokens":1234}},"rate_limits":null}}"#
        try (line + "\n").write(to: file, atomically: true, encoding: .utf8)

        let model = box.model(clock: TestClock())
        await model.start(); defer { model.stop() }
        await model.setDemo(false)
        #expect(model.codexDays == nil, "off: Codex's files aren't read")
        await model.setCodexEnabled(true)
        #expect(await eventually { model.codexDays != nil })
        #expect(model.codexDays?.map(\.day) == ["2026-10-16"] && model.codexDays?.first?.tokens.sum == 1234)
        await model.setCodexEnabled(false)
        #expect(model.codexDays == nil)
    }
}
