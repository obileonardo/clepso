import Foundation

/// Wire format (statusline-shim.md §6, ADR-004): a 4-byte big-endian length, then UTF-8 JSON of at
/// most 4096 bytes. One frame per connection.
public enum FrameCodec {
    public static let maxPayloadBytes = 4096

    public enum DecodeError: Error, Equatable {
        case truncatedPrefix, lengthMismatch, oversize, notJSON, notObject, wrongVersion, wrongKind
    }

    static func payload(_ frame: JSONValue) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(frame)
    }

    /// Encodes with the length prefix. Throws `oversize` rather than truncating.
    public static func encode(_ frame: JSONValue) throws -> Data {
        let body = try payload(frame)
        guard body.count <= maxPayloadBytes else { throw DecodeError.oversize }
        var length = UInt32(body.count).bigEndian
        var data = Data(bytes: &length, count: 4)
        data.append(body)
        return data
    }

    /// The app's side: validates size before parsing and the schema header after.
    public static func decode(_ data: Data) throws -> JSONValue {
        guard data.count >= 4 else { throw DecodeError.truncatedPrefix }
        let declared = data.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        guard declared <= maxPayloadBytes else { throw DecodeError.oversize }
        guard data.count - 4 == declared else { throw DecodeError.lengthMismatch }
        let frame: JSONValue
        do {
            frame = try JSONDecoder().decode(JSONValue.self, from: data.dropFirst(4))
        } catch {
            throw DecodeError.notJSON
        }
        guard case .object = frame else { throw DecodeError.notObject }
        guard frame["v"] == .number(Double(FrameBuilder.version)) else { throw DecodeError.wrongVersion }
        guard frame["kind"] == .string(FrameBuilder.kind) else { throw DecodeError.wrongKind }
        return frame
    }
}
