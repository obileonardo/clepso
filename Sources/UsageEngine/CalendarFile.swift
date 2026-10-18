import Foundation

/// One-shot reset events as an iCalendar file (RFC 5545): the `.ics` route of NOTIFICATIONS §3.1, increment 2.5.
/// The user opens the file, Calendar asks which calendar to add it to, and nothing is written without that step; no
/// calendar permission or entitlement is involved. Times are written as UTC instants, so a zone or daylight-saving
/// change can't move the event (F16, F17). Pure: the caller passes the stamp and the text.
public enum CalendarFile {
    public struct Event: Sendable, Equatable {
        /// Stable for one reset instant, so adding the same reset again updates the event instead of duplicating it.
        public var uid: String
        public var start: Date
        public var duration: TimeInterval
        public var summary: String
        public var notes: String
        /// A display alarm at the start time.
        public var alarm: Bool
        public init(uid: String, start: Date, duration: TimeInterval, summary: String, notes: String, alarm: Bool) {
            self.uid = uid; self.start = start; self.duration = duration
            self.summary = summary; self.notes = notes; self.alarm = alarm
        }
    }

    /// A complete `VCALENDAR` with CRLF line ends and lines folded at 75 octets (RFC 5545 §3.1).
    public static func calendar(_ events: [Event], stamp: Date, product: String) -> String {
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//\(escape(product))//\(escape(product))//EN",
                     "CALSCALE:GREGORIAN", "METHOD:PUBLISH"]
        for event in events {
            lines += ["BEGIN:VEVENT", "UID:\(escape(event.uid))", "DTSTAMP:\(utc(stamp))", "DTSTART:\(utc(event.start))",
                      "DURATION:\(duration(event.duration))", "SUMMARY:\(escape(event.summary))",
                      "DESCRIPTION:\(escape(event.notes))", "TRANSP:TRANSPARENT"]      // a reset never makes the user busy
            if event.alarm {
                lines += ["BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:\(escape(event.summary))", "TRIGGER:PT0S", "END:VALARM"]
            }
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    /// TEXT escaping (§3.3.11): backslash, semicolon, comma and line breaks.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\n")
    }

    /// Splits a content line so no physical line exceeds 75 octets, never inside a UTF-8 sequence; continuation lines
    /// start with one space, which counts toward their 75.
    static func fold(_ line: String) -> String {
        var out = "", width = 0
        for scalar in line.unicodeScalars {
            let size = String(scalar).utf8.count
            if width + size > 75 {
                out += "\r\n "
                width = 1
            }
            out.unicodeScalars.append(scalar)
            width += size
        }
        return out
    }

    /// `20261025T003000Z`, from calendar components in UTC (no formatter, so no locale can change the digits).
    static func utc(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func two(_ n: Int?) -> String { String(format: "%02d", n ?? 0) }
        return String(format: "%04d", c.year ?? 0) + two(c.month) + two(c.day) + "T" + two(c.hour) + two(c.minute) + two(c.second) + "Z"
    }

    /// `PT15M`, `PT1H30M`; whole minutes, at least one.
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        let h = minutes / 60, m = minutes % 60
        return "PT" + (h > 0 ? "\(h)H" : "") + (m > 0 || h == 0 ? "\(m)M" : "")
    }
}
