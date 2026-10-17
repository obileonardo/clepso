import Foundation

/// Byte positions of the members of a JSON object, so one member can be edited while every other byte
/// of the file stays exactly as it was (docs/specs/statusline-shim.md §3 step 4).
///
/// Deliberately small: it understands strings with escapes, nesting, a UTF-8 BOM and CRLF, and refuses
/// anything else (`nil`), in which case the installer falls back to reformatting and says so.
struct JSONObjectLayout {
    struct Member {
        let key: String
        let keyStart: Int          // index of the opening quote of the key
        let valueStart: Int
        let valueEnd: Int          // exclusive
    }

    let bytes: [UInt8]
    let openBrace: Int
    let closeBrace: Int
    let members: [Member]

    /// Parses the top-level object of a whole file (BOM allowed, only whitespace after it).
    static func parseDocument(_ bytes: [UInt8]) -> JSONObjectLayout? {
        var i = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        guard let layout = parseObject(bytes, at: &i) else { return nil }
        skipWhitespace(bytes, &i)
        return i == bytes.count ? layout : nil
    }

    /// Parses the object starting at `index` (after leading whitespace) and leaves `index` past its `}`.
    static func parseObject(_ bytes: [UInt8], at index: inout Int) -> JSONObjectLayout? {
        skipWhitespace(bytes, &index)
        guard index < bytes.count, bytes[index] == UInt8(ascii: "{") else { return nil }
        let open = index
        index += 1
        var members: [Member] = []
        skipWhitespace(bytes, &index)
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
            index += 1
            return JSONObjectLayout(bytes: bytes, openBrace: open, closeBrace: index - 1, members: [])
        }
        while true {
            skipWhitespace(bytes, &index)
            let keyStart = index
            guard let keyEnd = skipString(bytes, from: index),
                  let key = try? JSONDecoder().decode(String.self, from: Data(bytes[keyStart..<keyEnd])) else { return nil }
            index = keyEnd
            skipWhitespace(bytes, &index)
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { return nil }
            index += 1
            skipWhitespace(bytes, &index)
            let valueStart = index
            guard let valueEnd = skipValue(bytes, from: index) else { return nil }
            members.append(Member(key: key, keyStart: keyStart, valueStart: valueStart, valueEnd: valueEnd))
            index = valueEnd
            skipWhitespace(bytes, &index)
            guard index < bytes.count else { return nil }
            if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
            guard bytes[index] == UInt8(ascii: "}") else { return nil }
            index += 1
            return JSONObjectLayout(bytes: bytes, openBrace: open, closeBrace: index - 1, members: members)
        }
    }

    func members(named key: String) -> [Member] { members.filter { $0.key == key } }

    /// Line ending used by the file.
    var newline: String { bytes.indices.dropLast().contains { bytes[$0] == 0x0D && bytes[$0 + 1] == 0x0A } ? "\r\n" : "\n" }

    /// Whitespace before the first member on its line, or nil when members share the brace's line.
    var memberIndent: String? {
        guard let first = members.first else { return nil }
        var i = first.keyStart - 1
        while i > openBrace, bytes[i] == 0x20 || bytes[i] == 0x09 { i -= 1 }
        guard i > openBrace, bytes[i] == 0x0A else { return nil }
        return String(decoding: bytes[(i + 1)..<first.keyStart], as: UTF8.self)
    }

    // MARK: - Edits (each returns new file bytes; nothing outside the edited range changes)

    func replacingValue(of member: Member, with value: [UInt8]) -> [UInt8] {
        Array(bytes[..<member.valueStart]) + value + Array(bytes[member.valueEnd...])
    }

    /// Appends `"key": value` as the last member, using the file's own indentation and line ending.
    func appendingMember(key: String, value: [UInt8]) -> [UInt8] {
        let entry = Array("\(JSONObjectLayout.quoted(key)): ".utf8) + value
        guard let last = members.last else {
            let insertion = Array("\(newline)  ".utf8) + entry + Array(newline.utf8)
            return Array(bytes[...openBrace]) + insertion + Array(bytes[closeBrace...])
        }
        let separator = memberIndent.map { ",\(newline)\($0)" } ?? ", "
        return Array(bytes[..<last.valueEnd]) + Array(separator.utf8) + entry + Array(bytes[last.valueEnd...])
    }

    /// Removes a member together with exactly one adjoining comma, leaving valid JSON.
    func removingMember(_ member: Member) -> [UInt8] {
        guard let position = members.firstIndex(where: { $0.keyStart == member.keyStart }) else { return bytes }
        if position + 1 < members.count {
            return Array(bytes[..<member.keyStart]) + Array(bytes[members[position + 1].keyStart...])
        }
        if position > 0 {
            return Array(bytes[..<members[position - 1].valueEnd]) + Array(bytes[member.valueEnd...])
        }
        return Array(bytes[...openBrace]) + Array(bytes[closeBrace...])
    }

    static func quoted(_ string: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes     // "~/.claude/…", never "~\/.claude\/…"
        let data = (try? encoder.encode(string)) ?? Data("\"\"".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Scanning

    static func skipWhitespace(_ b: [UInt8], _ i: inout Int) {
        while i < b.count, b[i] == 0x20 || b[i] == 0x09 || b[i] == 0x0A || b[i] == 0x0D { i += 1 }
    }

    static func skipString(_ b: [UInt8], from start: Int) -> Int? {
        guard start < b.count, b[start] == UInt8(ascii: "\"") else { return nil }
        var i = start + 1
        while i < b.count {
            switch b[i] {
            case UInt8(ascii: "\\"): i += 2
            case UInt8(ascii: "\""): return i + 1
            case 0x00...0x1F: return nil               // raw control characters are invalid JSON
            default: i += 1
            }
        }
        return nil
    }

    static func skipValue(_ b: [UInt8], from start: Int) -> Int? {
        guard start < b.count else { return nil }
        switch b[start] {
        case UInt8(ascii: "\""):
            return skipString(b, from: start)
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            var depth = 0
            var i = start
            while i < b.count {
                switch b[i] {
                case UInt8(ascii: "\""):
                    guard let end = skipString(b, from: i) else { return nil }
                    i = end
                    continue
                case UInt8(ascii: "{"), UInt8(ascii: "["): depth += 1
                case UInt8(ascii: "}"), UInt8(ascii: "]"):
                    depth -= 1
                    if depth == 0 { return i + 1 }
                default: break
                }
                i += 1
            }
            return nil
        default:
            var i = start
            while i < b.count, !",}] \t\r\n".utf8.contains(b[i]) { i += 1 }
            return i > start ? i : nil
        }
    }
}
