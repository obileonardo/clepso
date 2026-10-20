import Foundation
import ShimProtocol
import Storage

/// "Export my data" (PRIVACY_AND_SECURITY §8): the six tables §8 names, every string scrubbed again by the
/// helper's own rule (a failing string becomes null and is counted), a header, written 0600.
public enum Exporter {
    public static let schemaVersion = 1
    public static let retentionDays = 90

    public struct Summary: Sendable, Equatable {
        public var rowsByTable: [String: Int]
        public var scrubbed: Int
        public var rows: Int { rowsByTable.values.reduce(0, +) }
    }

    /// Longest string kept: stored snapshots are JSON text of a few hundred bytes.
    static let maxStringBytes = 16_384

    public static func document(_ tables: [(table: String, rows: [[String: ExportValue]])], exportedAt: Date,
                                appVersion: String, retention: DataRetention = DataRetention()) throws -> (Data, Summary) {
        var summary = Summary(rowsByTable: [:], scrubbed: 0)
        var body: [String: Any] = [:]
        for (table, rows) in tables {
            summary.rowsByTable[table] = rows.count
            body[table] = rows.map { row in
                row.mapValues { value -> Any in
                    switch value {
                    case .null: return NSNull()
                    case .integer(let n): return n
                    case .real(let d): return d
                    case .text(let text):
                        guard Scrubber.isAcceptable(text, maxLength: maxStringBytes) else { summary.scrubbed += 1; return NSNull() }
                        return text
                    }
                }
            }
        }
        let document: [String: Any] = [
            "header": ["schemaVersion": schemaVersion, "exportedAt": Int64((exportedAt.timeIntervalSince1970 * 1000).rounded()),
                       "appVersion": appVersion, "retentionDays": retention.validated.readings,
                       "retention": ["readings": retention.validated.readings, "sessions": retention.validated.sessions,
                                     "receipts": retention.validated.receipts, "logs": retention.validated.logs],
                       "contains": "Usage readings, plan label and preferences. No prompts, paths, keys or transcripts."],
            "tables": body,
        ]
        let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return (data, summary)
    }

    /// Writes with mode 0600 from the first byte (no window where another user could read it).
    public static func write(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        guard fm.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
    }
}
