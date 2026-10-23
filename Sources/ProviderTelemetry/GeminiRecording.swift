import CryptoKit
import Foundation

/// A projection of Gemini CLI's own recordings. This is recorded token activity, never subscription quota.
/// Transcripts, tool arguments, thoughts, project paths and raw identifiers are not retained in this value.
public struct RecordedUsage: Equatable, Sendable {
    public let observedAt: Date
    public let input: Int64
    public let output: Int64
    public let cachedInput: Int64
    public let reasoning: Int64
    public let tool: Int64
    public let total: Int64
    public let messages: Int
    public let recordings: Int
    public let incomplete: Bool
}

public enum GeminiRecording {
    public static let maxBytes = 8 * 1024 * 1024
    public static let maxLine = 256 * 1024
    static let maxMessages = 8192

    struct Tokens: Decodable, Sendable, Equatable {
        let input: Int64, output: Int64, cached: Int64, thoughts: Int64, tool: Int64, total: Int64
        enum CodingKeys: String, CodingKey { case input, output, cached, thoughts, tool, total }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            input = try c.decode(Int64.self, forKey: .input)
            output = try c.decode(Int64.self, forKey: .output)
            cached = try c.decode(Int64.self, forKey: .cached)
            thoughts = try c.decodeIfPresent(Int64.self, forKey: .thoughts) ?? 0
            tool = try c.decodeIfPresent(Int64.self, forKey: .tool) ?? 0
            total = try c.decode(Int64.self, forKey: .total)
            guard [input, output, cached, thoughts, tool, total].allSatisfy({ (0...1_000_000_000_000).contains($0) }),
                  cached <= input else { throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Invalid token counts")) }
        }
    }
    struct Message: Decodable {
        let id: String?
        let type: String?
        let timestamp: String?
        let tokens: Tokens?
        // CodingKeys deliberately exclude content, thoughts, tool calls and arbitrary metadata.
        enum CodingKeys: String, CodingKey { case id, type, timestamp, tokens }
    }
    struct Header: Decodable {
        let sessionId: String
        let messages: [Message]?
        enum CodingKeys: String, CodingKey { case sessionId, messages }
    }
    struct Checkpoint: Decodable {
        let set: Values
        struct Values: Decodable { let messages: [Message]? }
        enum CodingKeys: String, CodingKey { case set = "$set" }
    }
    struct Ignorable: Decodable {
        enum CodingKeys: String, CodingKey { case patch = "$patch", rewind = "$rewindTo", set = "$set" }
        enum MetadataKeys: String, CodingKey { case messages }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard c.contains(.patch) || c.contains(.rewind) || c.contains(.set) else {
                throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Unknown recording line"))
            }
            if c.contains(.set) {
                let metadata = try c.nestedContainer(keyedBy: MetadataKeys.self, forKey: .set)
                // A malformed token checkpoint is not an ignorable metadata update.
                guard !metadata.contains(.messages) else {
                    throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Invalid token checkpoint"))
                }
            }
        }
    }
    struct Entry: Sendable, Equatable { let at: Date; let tokens: Tokens }
    struct Result: Sendable { let entries: [String: Entry]; let incomplete: Bool }

    static func date(_ value: String?) -> Date? {
        guard let value, value.utf8.count <= 40 else { return nil }
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value))
            ?? (try? Date.ISO8601FormatStyle().parse(value))
    }
    static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }
    static func digest(_ session: String, _ message: String) -> String {
        SHA256.hash(data: Data((session + "/" + message).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Repeated message records and legacy checkpoints replace the same message's counters. Rewinds and content
    /// patches do not refund tokens already consumed. This counts evidence still in these files, not a billing ledger.
    static func parse(_ data: Data, legacy: Bool, now: Date) -> Result? {
        guard data.count <= maxBytes else { return nil }
        let decoder = JSONDecoder()
        var entries: [String: Entry] = [:], incomplete = false
        func consume(_ message: Message, session: String) {
            guard message.type == "gemini", let tokens = message.tokens else { return }
            guard let id = message.id, validID(id), let at = date(message.timestamp),
                  at.timeIntervalSince1970 >= 0, at <= now.addingTimeInterval(60) else { incomplete = true; return }
            guard entries.count < maxMessages || entries[digest(session, id)] != nil else { incomplete = true; return }
            entries[digest(session, id)] = Entry(at: at, tokens: tokens)
        }
        if legacy {
            guard let record = try? decoder.decode(Header.self, from: data), validID(record.sessionId),
                  let messages = record.messages, messages.count <= maxMessages else { return nil }
            for message in messages { consume(message, session: record.sessionId) }
        } else {
            // A partially written last record is deliberately deferred until the next scan.
            let lines = data.split(separator: 10, omittingEmptySubsequences: true)
            guard let first = lines.first, first.count <= maxLine,
                  let header = try? decoder.decode(Header.self, from: Data(first)), validID(header.sessionId) else { return nil }
            if let messages = header.messages {
                guard messages.count <= maxMessages else { return nil }
                for message in messages { consume(message, session: header.sessionId) }
            }
            for (index, line) in lines.dropFirst().enumerated() {
                if index == lines.count - 2, data.last != 10 { incomplete = true; break }
                guard line.count <= maxLine else { incomplete = true; continue }
                if let message = try? decoder.decode(Message.self, from: Data(line)), message.type != nil {
                    consume(message, session: header.sessionId)
                } else if let checkpoint = try? decoder.decode(Checkpoint.self, from: Data(line)), let messages = checkpoint.set.messages {
                    guard messages.count <= maxMessages else { incomplete = true; continue }
                    for message in messages { consume(message, session: header.sessionId) }
                } else if (try? decoder.decode(Ignorable.self, from: Data(line))) == nil {
                    incomplete = true
                }
            }
        }
        return Result(entries: entries, incomplete: incomplete)
    }

    static func project(_ records: [Result], incomplete: Bool) -> RecordedUsage? {
        var entries: [String: Entry] = [:]
        for record in records {
            for (id, value) in record.entries {
                if let previous = entries[id], previous.at > value.at { continue }
                entries[id] = value
            }
        }
        guard let latest = entries.values.map(\.at).max() else { return nil }
        let values = entries.values.map(\.tokens)
        return RecordedUsage(observedAt: latest, input: values.reduce(0) { $0 + $1.input }, output: values.reduce(0) { $0 + $1.output },
                             cachedInput: values.reduce(0) { $0 + $1.cached }, reasoning: values.reduce(0) { $0 + $1.thoughts },
                             tool: values.reduce(0) { $0 + $1.tool }, total: values.reduce(0) { $0 + $1.total }, messages: entries.count,
                             recordings: records.count, incomplete: incomplete || records.contains(where: \.incomplete))
    }
}
