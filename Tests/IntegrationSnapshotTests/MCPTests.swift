import ClepsoMCP
import Foundation
import IntegrationSnapshot
import Testing

@Suite("Read-only MCP and private snapshot boundary")
struct MCPTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func message(_ server: inout MCPServer, _ object: [String: Any], at: Date? = nil) throws -> [String: Any] {
        let request = try JSONSerialization.data(withJSONObject: object)
        let response = server.respond(to: request, now: at ?? now)
        let reply = try #require(response)
        return try #require(JSONSerialization.jsonObject(with: reply) as? [String: Any])
    }
    func initialize(_ server: inout MCPServer) throws {
        let reply = try message(&server, ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-11-25"]])
        #expect((reply["result"] as? [String: Any])?["protocolVersion"] as? String == MCPServer.protocolVersion)
        let response = server.respond(to: Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8), now: now)
        #expect(response == nil)
    }
    func reading(reset: Date? = nil) -> UsageSnapshot {
        UsageSnapshot(generatedAt: now, limits: [.init(provider: .codex, window: .fiveHour, source: .automatic,
            usedPercent: 112.5, observedAt: now, resetsAt: reset, state: .reported)])
    }

    @Test func consentAndRevocationApplyToRunningClient() throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = SnapshotFile(dataDirectory: directory)
        var server = MCPServer(dataDirectory: directory, client: "test-client")
        try initialize(&server)
        let request: [String: Any] = ["jsonrpc": "2.0", "id": "tools", "method": "tools/list"]
        #expect(try message(&server, request)["error"] != nil)
        try file.setClients(["test-client"]); try file.publish(reading())
        #expect(try message(&server, request)["result"] != nil)
        try file.setClients([])
        #expect(try message(&server, request)["error"] != nil)
    }
    @Test func staleAndResetAreRecomputedWithoutAppRunning() throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = SnapshotFile(dataDirectory: directory)
        try file.setClients(["test"]); try file.publish(reading(reset: now.addingTimeInterval(60)))
        var server = MCPServer(dataDirectory: directory, client: "test"); try initialize(&server)
        let reply = try message(&server, ["jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": "get_limits", "arguments": ["provider": "codex"]]], at: now.addingTimeInterval(601))
        let result = try #require(reply["result"] as? [String: Any])
        let payload = try #require(result["structuredContent"] as? [String: Any])
        #expect(payload["appSnapshotFresh"] as? Bool == false)
        let row = try #require((payload["readings"] as? [[String: Any]])?.first)
        #expect(row["state"] as? String == "resetExpected")
        #expect(row["freshness"] as? String == "stale")
        #expect(row["usedPercent"] as? Double == 112.5)
        #expect(Set(row.keys) == ["provider", "window", "source", "state", "freshness", "observedAt", "usedPercent", "resetsAt"])
    }
    @Test func arbitraryArgumentsAndMethodsAreRejected() throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        try SnapshotFile(dataDirectory: directory).setClients(["test"])
        var server = MCPServer(dataDirectory: directory, client: "test"); try initialize(&server)
        for params: [String: Any] in [["name": "exec"], ["name": "get_limits", "arguments": ["path": "/etc/passwd"]],
                                    ["name": "get_limits", "arguments": ["provider": "../../secret"]]] {
            #expect(try message(&server, ["jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": params])["error"] != nil)
        }
        #expect(try message(&server, ["jsonrpc": "2.0", "id": 3, "method": "resources/read"])["error"] != nil)
    }
    @Test func unsafeFilesAndInvalidSnapshotsFailClosed() throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = SnapshotFile(dataDirectory: directory)
        try file.publish(reading()); #expect(try file.load() == reading())
        let path = file.directory.appendingPathComponent("usage.v1.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path.path)
        #expect(throws: SnapshotFile.Failure.self) { try file.load() }
        try FileManager.default.removeItem(at: path)
        let secret = directory.appendingPathComponent("secret")
        try Data("private account content".utf8).write(to: secret)
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: secret)
        #expect(throws: SnapshotFile.Failure.self) { try file.load() }
        #expect(!SnapshotFile.validClient("../test"))
        #expect(!SnapshotFile.validClient(""))
        #expect(throws: SnapshotFile.Failure.self) {
            try file.publish(UsageSnapshot(generatedAt: now, limits: [.init(provider: .grok, window: .daily, source: .manual,
                usedPercent: -1, observedAt: now, resetsAt: nil, state: .reported)]))
        }
    }
    @Test func demoAndAbsentDataNeverInventReadings() throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = SnapshotFile(dataDirectory: directory); try file.setClients(["test"])
        var server = MCPServer(dataDirectory: directory, client: "test"); try initialize(&server)
        let request: [String: Any] = ["jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": "get_limits"]]
        #expect((try message(&server, request)["result"] as? [String: Any])?["isError"] as? Bool == true)
        try file.publish(UsageSnapshot(generatedAt: now, demo: true, limits: []))
        #expect((try message(&server, request)["result"] as? [String: Any])?["isError"] as? Bool == true)
    }
    @Test func malformedAndPreInitializationRequests() throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        var server = MCPServer(dataDirectory: directory, client: "test")
        let malformed = server.respond(to: Data("{bad".utf8), now: now)
        #expect(malformed != nil)
        #expect(try message(&server, ["jsonrpc": "2.0", "id": 2, "method": "tools/list"])["error"] != nil)
        let notification = server.respond(to: Data(#"{"jsonrpc":"2.0","method":"notifications/cancelled"}"#.utf8), now: now)
        #expect(notification == nil)
    }
}
