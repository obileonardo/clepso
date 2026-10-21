import Domain
import Foundation
import Testing
import UsageEngine
@testable import ClepsoApp

/// Increment 2.5: One-tap Calendar through the real app model (NOTIFICATIONS §3.1, `.ics` route; DECISIONS B9).
@MainActor
@Suite(.serialized)
struct CalendarActionTests {
    let start = try! Date("2026-10-23T12:00:00Z", strategy: .iso8601)
    let weekly = try! Date("2026-10-25T00:30:00Z", strategy: .iso8601)
    let fiveHour = try! Date("2026-10-23T17:00:00Z", strategy: .iso8601)

    func harness() async throws -> TimeTravel {
        let h = TimeTravel(at: start, zone: TimeZone(identifier: "Europe/London")!, locale: Locale(identifier: "en_GB"))
        await h.start()
        try await h.frame(fiveHour: 40, fiveHourResets: fiveHour, sevenDay: 100, sevenDayResets: weekly)
        return h
    }

    var calendarFiles: (TimeTravel) -> [String] {
        { h in (try? FileManager.default.contentsOfDirectory(atPath: h.model.environment.calendarDirectory.path)) ?? [] }
    }

    @Test("Calendar is available by default, but readings, ticks and alerts never create or open an event")
    func nothingByDefault() async throws {
        let h = try await harness()
        defer { h.finish() }
        #expect(AppEnvironment(dataDirectory: h.box.data, home: h.box.home, shimPath: "", loginItem: FakeLoginItem(),
                               notifications: FakeNotifications()).calendarActions)
        await h.travel(weekly.timeIntervalSince(h.clock.now()) + 60)          // through the reset, alerts and all
        #expect(h.opened.isEmpty)
        #expect(calendarFiles(h).isEmpty)
    }

    @Test("Weekly only (B9): the 7-day reset becomes an event at its exact instant; the 5-hour window never does")
    func weeklyOnly() async throws {
        let h = try await harness()
        defer { h.finish() }
        #expect(h.fiveHour.flatMap { h.model.calendarEvent(for: $0) } == nil)
        let event = try #require(h.sevenDay.flatMap { h.model.calendarEvent(for: $0) })
        #expect(event.start == weekly)
        #expect(event.uid == "claude-code.rate_limits.seven_day.1792888200@clepso")
        #expect(event.summary == "Claude Code 7-day limit resets" && event.alarm)
    }

    @Test("Add writes one .ics and opens it once; adding again rewrites the same event; a passed reset offers nothing")
    func addOnce() async throws {
        let h = try await harness()
        defer { h.finish() }
        let row = try #require(h.sevenDay)
        let file = try #require(h.model.addResetToCalendar(row))
        #expect(h.opened == [file])
        #expect(file.lastPathComponent == "Claude Code 7-day limit resets.ics")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("\r\nDTSTART:20261025T003000Z\r\n") && text.contains("\r\nDTSTAMP:20261023T120000Z\r\n"))
        #expect(text.contains("\r\nUID:claude-code.rate_limits.seven_day.1792888200@clepso\r\n"))

        #expect(h.model.addResetToCalendar(row) == file)                    // the same reset: same file, same UID
        #expect(calendarFiles(h) == [file.lastPathComponent] && h.opened.count == 2)

        await h.travel(weekly.timeIntervalSince(h.clock.now()) + 1)
        #expect(h.sevenDay.flatMap { h.model.calendarEvent(for: $0) } == nil)
        #expect(h.sevenDay.flatMap { h.model.addResetToCalendar($0) } == nil)
        #expect(h.opened.count == 2)
    }
}
