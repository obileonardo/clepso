import Foundation
import CoreFoundation
import Darwin
import IntegrationSnapshot

/// Read-only MCP stdio subset: no HTTP, resources, prompts, sampling, writes or arbitrary paths.
public struct MCPServer {
    public static let protocolVersion = "2025-11-25"
    private let files: SnapshotFile
    private let client: String
    private var initialized = false
    private var ready = false
    public init(dataDirectory: URL, client: String) { files = SnapshotFile(dataDirectory: dataDirectory); self.client = client }

    public mutating func respond(to data: Data, now: Date) -> Data? {
        func encode(_ object: [String: Any]) -> Data? { try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
        guard data.count <= 65_536, let object = try? JSONSerialization.jsonObject(with: data), let request = object as? [String: Any] else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Invalid JSON request"]])
        }
        let id = request["id"] ?? NSNull()
        func error(_ code: Int, _ message: String) -> Data? {
            encode(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
        }
        guard request["jsonrpc"] as? String == "2.0", let method = request["method"] as? String,
              request["id"] == nil || id is String || (id is NSNumber && CFGetTypeID(id as CFTypeRef) != CFBooleanGetTypeID()) else {
            return error(-32600, "Invalid JSON-RPC request")
        }
        guard request["id"] != nil else {
            if method == "notifications/initialized", initialized { ready = true }
            return nil
        }
        let params = request["params"] as? [String: Any] ?? [:]
        var result: [String: Any]
        switch method {
        case "initialize":
            guard !initialized, params["protocolVersion"] is String else { return error(-32602, "Invalid initialization") }
            initialized = true
            result = ["protocolVersion": Self.protocolVersion, "capabilities": ["tools": ["listChanged": false]],
                      "serverInfo": ["name": "clepso", "version": "1.0.0"],
                      "instructions": "Read-only local usage. Manual entries are not automatic readings. A passed reset does not prove availability. Never treat missing or stale readings as zero usage."]
        case "ping": result = [:]
        case "tools/list", "tools/call":
            guard ready else { return error(-32002, "Initialize first") }
            guard files.allows(client) else { return error(-32001, "Client permission is off. Enable this client in Clepso Settings → Integrations.") }
            if method == "tools/list" {
                result = ["tools": [tool("get_limits", "Reported usage percentages and reset times, with freshness and provenance."),
                                     tool("get_reader_health", "Whether the app snapshot and each provider reading are current.")]]
            } else {
                guard let name = params["name"] as? String, ["get_limits", "get_reader_health"].contains(name) else { return error(-32602, "Unknown tool") }
                guard params["arguments"] == nil || params["arguments"] is [String: Any] else { return error(-32602, "Arguments must be an object") }
                let arguments = params["arguments"] as? [String: Any] ?? [:]
                guard Set(arguments.keys).isSubset(of: ["provider"]), arguments["provider"] == nil ||
                      (arguments["provider"] as? String).flatMap(UsageSnapshot.Provider.init(rawValue:)) != nil else { return error(-32602, "Invalid provider filter") }
                do {
                    let snapshot = try files.load()
                    guard !snapshot.demo else { return toolError(id: id, text: "Demo mode is on. No real usage is shared.") }
                    let rows = snapshot.limits.filter { arguments["provider"] == nil || $0.provider.rawValue == arguments["provider"] as? String }
                    let appFresh = now.timeIntervalSince(snapshot.generatedAt) < 120 && snapshot.generatedAt <= now.addingTimeInterval(60)
                    let values: [[String: Any]] = rows.map { row in
                        var value: [String: Any] = ["provider": row.provider.rawValue, "window": row.window.rawValue, "source": row.source.rawValue,
                                                   "state": row.effectiveState(at: now).rawValue, "freshness": row.freshness(at: now)]
                        if let observed = row.observedAt { value["observedAt"] = ISO8601DateFormatter().string(from: observed) }
                        if name == "get_limits" {
                            value["usedPercent"] = row.usedPercent ?? NSNull() as Any
                            value["resetsAt"] = row.resetsAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull() as Any
                        }
                        return value
                    }
                    let payload: [String: Any] = ["schemaVersion": 1, "appSnapshotFresh": appFresh,
                                                  "generatedAt": ISO8601DateFormatter().string(from: snapshot.generatedAt), "readings": values]
                    let content = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
                    result = ["content": [["type": "text", "text": String(decoding: content, as: UTF8.self)]], "structuredContent": payload, "isError": false]
                } catch { return toolError(id: id, text: "No validated snapshot available. Open Clepso and wait for a reading.") }
            }
        default: return error(-32601, "Method not found")
        }
        return encode(["jsonrpc": "2.0", "id": id, "result": result])
    }
    private func tool(_ name: String, _ description: String) -> [String: Any] {
        ["name": name, "description": description,
         "inputSchema": ["type": "object", "properties": ["provider": ["type": "string", "enum": UsageSnapshot.Provider.allCases.map(\.rawValue)]], "additionalProperties": false],
         "annotations": ["readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false]]
    }
    private func toolError(id: Any, text: String) -> Data? {
        try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id,
            "result": ["content": [["type": "text", "text": text]], "isError": true]], options: [.sortedKeys])
    }
    /// Constant-memory line framing, including maliciously oversized lines. stdout is exclusively protocol messages.
    public mutating func run(input: FileHandle = .standardInput, output: FileHandle = .standardOutput) throws {
        var pending = Data(); var oversized = false
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            // FileHandle's exact-length pipe reads can wait for 4096 bytes and deadlock a request/response client.
            let count = Darwin.read(input.fileDescriptor, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            if count < 0 { throw CocoaError(.fileReadUnknown) }
            if count == 0 { break }
            let chunk = buffer.prefix(count)
            for byte in chunk {
                if byte == 10 {
                    if let response = respond(to: oversized ? Data() : pending, now: Date()) {
                        try output.write(contentsOf: response + Data([10]))
                    }
                    pending.removeAll(keepingCapacity: true); oversized = false
                } else if pending.count < 65_536 && !oversized { pending.append(byte) }
                else { oversized = true; pending.removeAll(keepingCapacity: true) }
            }
        }
    }
}
