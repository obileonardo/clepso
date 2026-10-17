import Foundation

/// A JSON tree that keeps "key absent" and "value null" apart, which Swift optionals cannot.
/// The status-line payload and the socket frame both need that distinction (PRIVACY_AND_SECURITY §4).
public enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// Deepest coding path accepted while decoding stdin (ARCHITECTURE §3: depth > 4 is rejected).
    static let maxDecodeDepth = 4
}

/// Result of looking up a dotted path: the frame contract distinguishes all three.
public enum FieldPresence: Sendable, Equatable {
    case absent
    case null
    case value(JSONValue)
}

extension JSONValue {
    public subscript(key: String) -> JSONValue? {
        if case .object(let members) = self { return members[key] }
        return nil
    }

    public func lookup(_ path: [String]) -> FieldPresence {
        var node = self
        for key in path {
            guard case .object(let members) = node, let next = members[key] else { return .absent }
            node = next
        }
        if case .null = node { return .null }
        return .value(node)
    }

    /// Sets `value` at `path`, creating intermediate objects. Overwrites non-object intermediates.
    mutating func set(_ value: JSONValue, at path: [String]) {
        guard let head = path.first else {
            self = value
            return
        }
        var members: [String: JSONValue] = if case .object(let existing) = self { existing } else { [:] }
        var child = members[head] ?? .object([:])
        child.set(value, at: Array(path.dropFirst()))
        members[head] = child
        self = .object(members)
    }

    mutating func remove(at path: [String]) {
        guard let head = path.first, case .object(var members) = self else { return }
        if path.count == 1 {
            members[head] = nil
        } else if var child = members[head] {
            child.remove(at: Array(path.dropFirst()))
            members[head] = child
        }
        self = .object(members)
    }
}

struct JSONDepthExceeded: Error {}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        if decoder.codingPath.count > Self.maxDecodeDepth { throw JSONDepthExceeded() }
        let single = try? decoder.singleValueContainer()
        if let single {
            if single.decodeNil() { self = .null; return }
            if let bool = try? single.decode(Bool.self) { self = .bool(bool); return }
            if let number = try? single.decode(Double.self) { self = .number(number); return }
            if let string = try? single.decode(String.self) { self = .string(string); return }
        }
        if var unkeyed = try? decoder.unkeyedContainer() {
            var items: [JSONValue] = []
            while !unkeyed.isAtEnd { items.append(try unkeyed.decode(JSONValue.self)) }
            self = .array(items)
            return
        }
        let keyed = try decoder.container(keyedBy: AnyKey.self)
        var members: [String: JSONValue] = [:]
        for key in keyed.allKeys { members[key.stringValue] = try keyed.decode(JSONValue.self, forKey: key) }
        self = .object(members)
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .null:
            var c = encoder.singleValueContainer(); try c.encodeNil()
        case .bool(let b):
            var c = encoder.singleValueContainer(); try c.encode(b)
        case .number(let n):
            var c = encoder.singleValueContainer()
            // Integral values encode without a fraction so epoch seconds and token counts stay integers.
            if n.rounded() == n, abs(n) < 9_007_199_254_740_992 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .string(let s):
            var c = encoder.singleValueContainer(); try c.encode(s)
        case .array(let items):
            var c = encoder.unkeyedContainer()
            for item in items { try c.encode(item) }
        case .object(let members):
            var c = encoder.container(keyedBy: AnyKey.self)
            for (key, value) in members { try c.encode(value, forKey: AnyKey(key)) }
        }
    }
}

struct AnyKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
