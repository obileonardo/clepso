import Foundation
import Testing
@testable import ProviderTelemetry

@Suite("Gemini recording projection") struct GeminiTests {
    let now = Date(timeIntervalSince1970: 1_792_665_600)
    func row(_ id: String = "m1", input: String = "100", total: String = "150") -> String {
        """
        {"id":"\(id)","type":"gemini","timestamp":"2026-10-22T00:00:00Z","content":"PRIVATE PROMPT AND REPLY","toolCalls":[{"args":{"secret":"PRIVATE KEY"}}],"tokens":{"input":\(input),"output":30,"cached":20,"thoughts":10,"tool":10,"total":\(total)}}
        """
    }
    func parse(_ rows: [String]) -> GeminiRecording.Result? {
        GeminiRecording.parse(Data(([#"{"sessionId":"session-one","projectHash":"private-project","directories":["/private/project"]}"#] + rows).joined(separator: "\n").appending("\n").utf8), legacy: false, now: now)
    }
    @Test func deduplicatesUpdatesCheckpointsAndRewindsWithoutRefundingUsage() throws {
        let a = try #require(parse([row(), row(), #"{"$rewindTo":"m1"}"#, #"{"$patch":{"id":"m1","content":"PRIVATE CONTENT"}}"#, row("m2")]))
        let projected = try #require(GeminiRecording.project([a, a], incomplete: false))
        #expect(projected.messages == 2 && projected.total == 300 && projected.cachedInput == 40)
        #expect(projected.input == 200 && projected.output == 60 && projected.reasoning == 20)
        #expect(!String(describing: projected).contains("PRIVATE"))
        let checkpoint = try #require(parse([row(), "{\"$set\":{\"messages\":[\(row())]}} "]))
        #expect(GeminiRecording.project([checkpoint], incomplete: false)?.messages == 1)
    }
    @Test func legacyAndJSONLAgree() throws {
        let json = Data("{\"sessionId\":\"session-one\",\"messages\":[\(row())]}".utf8)
        let legacy = try #require(GeminiRecording.parse(json, legacy: true, now: now))
        #expect(legacy.entries == parse([row()])?.entries)
    }
    @Test func rejectsInvalidCountsAndDefersIncompleteRecord() throws {
        for bad in ["true", "-1", "1.25", "1000000000001", "null"] {
            #expect(parse([row(input: bad)])?.entries.isEmpty == true)
        }
        let partial = Data((#"{"sessionId":"session-one"}"# + "\n" + row()).utf8)
        let result = try #require(GeminiRecording.parse(partial, legacy: false, now: now))
        #expect(result.entries.isEmpty && result.incomplete)
        #expect(GeminiRecording.parse(Data(repeating: 32, count: GeminiRecording.maxBytes + 1), legacy: false, now: now) == nil)
    }
    @Test func malformedRecordsArePartialAlongsideValidEvidence() throws {
        let result = try #require(parse([row(), row("broken", input: "true"), "{broken-json", "{\"$set\":{\"messages\":[\(row(input: "-1"))]}} "]))
        #expect(result.entries.count == 1 && result.incomplete)
        let metadata = try #require(parse([row(), #"{"$set":{"lastUpdated":"2026-10-22T00:00:00Z","summary":"PRIVATE"}}"#]))
        #expect(!metadata.incomplete && metadata.entries.count == 1)
    }
    @Test func scannerRefreshesAndRejectsSymlinksAndMigratedDuplicates() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let chats = home.appendingPathComponent(".gemini/tmp/project/chats")
        try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
        let json = chats.appendingPathComponent("session-one.json")
        try Data("{\"sessionId\":\"session-one\",\"messages\":[\(row())]}".utf8).write(to: json)
        var reader = GeminiReader()
        #expect(reader.scan(home: home, now: now)?.total == 150)
        let jsonl = chats.appendingPathComponent("session-one.jsonl")
        try Data((#"{"sessionId":"session-one"}"# + "\n" + row() + "\n" + row("m2") + "\n").utf8).write(to: jsonl)
        #expect(reader.scan(home: home, now: now)?.total == 300)
        try FileManager.default.removeItem(at: jsonl)
        try FileManager.default.removeItem(at: json)
        try FileManager.default.createSymbolicLink(at: jsonl, withDestinationURL: home.appendingPathComponent("secret.jsonl"))
        #expect(reader.scan(home: home, now: now) == nil)
    }
}
