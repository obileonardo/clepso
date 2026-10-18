import Foundation
import Testing
@testable import UsageEngine

/// Increment 2.5: the `.ics` a weekly reset becomes (RFC 5545).
struct CalendarFileTests {
    let reset = Date(timeIntervalSince1970: 1_792_888_200)          // 2026-10-25T00:30:00Z: 01:30 BST, before the clocks go back
    let stamp = Date(timeIntervalSince1970: 1_792_756_800)          // 2026-10-23T12:00:00Z

    func event(summary: String = "Claude Code 7-day limit resets", notes: String = "Notes, with a comma") -> CalendarFile.Event {
        CalendarFile.Event(uid: "pool.1792888200@clepso", start: reset, duration: 15 * 60, summary: summary, notes: notes, alarm: true)
    }

    @Test("The file, byte for byte: UTC instants, CRLF, a display alarm at the reset, never busy")
    func golden() {
        let expected = [
            "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Clepso//Clepso//EN", "CALSCALE:GREGORIAN", "METHOD:PUBLISH",
            "BEGIN:VEVENT", "UID:pool.1792888200@clepso", "DTSTAMP:20261023T120000Z", "DTSTART:20261025T003000Z",
            "DURATION:PT15M", "SUMMARY:Claude Code 7-day limit resets", "DESCRIPTION:Notes\\, with a comma", "TRANSP:TRANSPARENT",
            "BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:Claude Code 7-day limit resets", "TRIGGER:PT0S", "END:VALARM",
            "END:VEVENT", "END:VCALENDAR",
        ].joined(separator: "\r\n") + "\r\n"
        #expect(CalendarFile.calendar([event()], stamp: stamp, product: "Clepso") == expected)
    }

    @Test("Long and non-ASCII text folds at 75 octets, never inside a character, and unfolds to the original")
    func folding() {
        let long = String(repeating: "Résumé ☕ · ", count: 20)
        let text = CalendarFile.calendar([event(summary: long)], stamp: stamp, product: "Clepso")
        let physical = text.components(separatedBy: "\r\n").dropLast()
        #expect(physical.allSatisfy { $0.utf8.count <= 75 })
        #expect(!text.replacingOccurrences(of: "\r\n", with: "").contains("\n"), "no bare line feeds")
        let unfolded = text.replacingOccurrences(of: "\r\n ", with: "")
        #expect(unfolded.contains("SUMMARY:" + long + "\r\n"))
    }

    @Test("TEXT escaping: backslash, semicolon, comma, and every kind of line break")
    func escaping() {
        #expect(CalendarFile.escape("a\\b;c,d\ne\r\nf\rg") == "a\\\\b\\;c\\,d\\ne\\nf\\ng")
    }

    @Test("Instants are written in UTC whatever the zone, and durations in whole minutes")
    func instantsAndDurations() {
        #expect(CalendarFile.utc(reset) == "20261025T003000Z")
        #expect(CalendarFile.utc(reset.addingTimeInterval(3600)) == "20261025T013000Z")    // 01:30 GMT: the repeated wall hour
        #expect(CalendarFile.duration(15 * 60) == "PT15M")
        #expect(CalendarFile.duration(90 * 60) == "PT1H30M")
        #expect(CalendarFile.duration(3600) == "PT1H")
        #expect(CalendarFile.duration(0) == "PT1M")
    }
}
