import CryptoKit
import Foundation

/// Turns a raw status-line capture into a committable fixture.
///
/// The capture is evidence of Claude Code's real payload shape, so the scrubber keeps every key, every
/// type and every null exactly as captured. It only rewrites string values: paths become placeholders,
/// identifying names become "redacted", the session id becomes a one-way hash with a throwaway key,
/// and any other string that looks like a path, email or secret is redacted and counted.
public enum CaptureScrubber {
    public struct Result {
        public let scrubbed: [String: Any]
        public let scrubCount: Int
        public let topLevelKeys: [String]
        public let sourceVersion: String?
    }

    /// Keys whose string values are filesystem paths.
    static let pathKeys: Set<String> = [
        "cwd", "transcript_path", "scratchpad_dir", "workspace.current_dir", "workspace.project_dir", "workspace.added_dirs",
        "workspace.git_worktree", "worktree.path", "worktree.original_cwd",
    ]
    /// Keys whose string values can identify the user, a project or a repository.
    static let identifyingKeys: Set<String> = [
        "session_name", "prompt_id", "workspace.repo.host", "workspace.repo.owner", "workspace.repo.name",
        "pr.url", "worktree.name", "worktree.branch", "worktree.original_branch", "agent.name",
    ]

    public static func scrub(_ raw: Data, key: Data) throws -> Result {
        guard let object = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        var count = 0
        let scrubbed = walk(object, path: [], key: key, count: &count) as? [String: Any] ?? [:]
        return Result(scrubbed: scrubbed, scrubCount: count, topLevelKeys: object.keys.sorted(),
                      sourceVersion: object["version"] as? String)
    }

    static func walk(_ value: Any, path: [String], key: Data, count: inout Int) -> Any {
        let dotted = path.joined(separator: ".")
        switch value {
        case let object as [String: Any]:
            var out: [String: Any] = [:]
            for (k, v) in object { out[k] = walk(v, path: path + [k], key: key, count: &count) }
            return out
        case let array as [Any]:
            return array.map { walk($0, path: path, key: key, count: &count) }
        case let string as String:
            if dotted == "session_id" { return "capture-" + hmacHex(string, key: key) }
            if pathKeys.contains(dotted) { count += 1; return "/fixture/path" }
            if identifyingKeys.contains(dotted) { count += 1; return "redacted" }
            if looksSensitive(string) { count += 1; return "redacted" }
            return string
        default:
            return value                                      // numbers, booleans and NSNull untouched
        }
    }

    static func looksSensitive(_ s: String) -> Bool {
        if s.contains("/") || s.contains("\\") || s.contains("@") { return true }
        if s.unicodeScalars.contains(where: { $0.value < 0x20 }) { return true }
        for marker in ["sk-ant-", "AKIA", "ghp_", "Bearer ", NSUserName()] where !marker.isEmpty && s.contains(marker) {
            return true
        }
        return s.range(of: #"[A-Za-z0-9+/=]{32,}"#, options: .regularExpression) != nil
    }

    static func hmacHex(_ value: String, key: Data) -> String {
        HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: SymmetricKey(data: key))
            .prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Lint applied to anything about to enter the repository.
    public static func lintFindings(_ text: String) -> [String] {
        ["/Users/", "/Volumes/", "@", NSUserName()].filter { !$0.isEmpty && text.contains($0) }
    }

    /// Writes `stdin/01-<label>.json` and `meta.json` for a captured fixture. `expected.json` is authored
    /// by hand after reading the capture; it is never generated from the code under test.
    public static func writeFixture(raw: Data, to directory: URL, id: String, label: String, capturedAt: Date) throws -> Result {
        var keyBytes = [UInt8](repeating: 0, count: 32)
        var generator = SystemRandomNumberGenerator()
        for i in keyBytes.indices { keyBytes[i] = UInt8.random(in: 0...255, using: &generator) }
        let result = try scrub(raw, key: Data(keyBytes))           // the key is discarded with this frame

        let stdinData = try JSONSerialization.data(withJSONObject: result.scrubbed,
                                                   options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let findings = lintFindings(String(decoding: stdinData, as: UTF8.self))
        guard findings.isEmpty else { throw ScrubError.lintFailed(findings) }

        let iso = ISO8601DateFormatter()
        let meta: [String: Any] = [
            "fixtureSchema": 1, "id": id, "slug": label, "origin": "captured", "scrubbed": true,
            "scrubCount": result.scrubCount,
            "providerSchema": ["name": "claude-code-statusline", "version": result.sourceVersion.map { $0 as Any } ?? NSNull(),
                               "docURL": "https://code.claude.com/docs/en/statusline", "docCheckedAt": "2026-10-16"],
            "clock": ["start": iso.string(from: capturedAt), "renderAt": iso.string(from: capturedAt.addingTimeInterval(60)),
                      "displayTimeZone": "Europe/London"],
            "capture": ["capturedAt": iso.string(from: capturedAt), "rawStdinBytes": raw.count,
                        "topLevelKeys": result.topLevelKeys],
            "events": [["file": "stdin/01-\(label).json", "atOffsetSeconds": 0, "originalCommandStdout": ""]],
            "history": [["date": String(iso.string(from: capturedAt).prefix(10)), "by": "increment 0.6", "why": "First real capture."]],
        ]
        let fm = FileManager.default
        try fm.createDirectory(at: directory.appendingPathComponent("stdin"), withIntermediateDirectories: true)
        try (stdinData + Data("\n".utf8)).write(to: directory.appendingPathComponent("stdin/01-\(label).json"))
        let metaData = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try (metaData + Data("\n".utf8)).write(to: directory.appendingPathComponent("meta.json"))
        return result
    }

    public enum ScrubError: Error, Equatable { case lintFailed([String]) }
}
