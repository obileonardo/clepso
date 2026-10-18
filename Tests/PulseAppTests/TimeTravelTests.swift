import DesignSystem
import Domain
import Foundation
import ShimProtocol
import Testing
import UsageEngine
@testable import PulseApp

/// Increment 2.4: the time-travel harness (TEST_PLAN §5 cases 10–12, fixtures F16 and F17). The real app model, store,
/// reducers and alert planner run against a clock the test moves: across both daylight-saving changes in London and
/// New York, through a time-zone change, across a 90-day (and a 3-day) sleep, and with the clock stepping back.
/// Readings arrive as real helper frames over the socket; alerts are read off the notification fake.
@MainActor
final class TimeTravel {
    let box = Sandbox()
    let clock: TestClock
    let notifications = FakeNotifications()
    /// Files the app asked the system to open (Add to Calendar); never the real Calendar in tests.
    private(set) var opened: [URL] = []
    private(set) var model: AppModel!                      // set in init, once the harness can hand it its file opener
    private(set) var zone: TimeZone
    private(set) var locale: Locale

    init(at start: Date, zone: TimeZone, locale: Locale) {
        clock = TestClock(start)
        self.zone = zone
        self.locale = locale
        try? Data("{}\n".utf8).write(to: box.settings)          // a Claude Code settings file with no status line yet
        model = makeModel()
    }

    private func makeModel() -> AppModel {
        var environment = AppEnvironment(dataDirectory: box.data, home: box.home, shimPath: "/Applications/Clepso.app/Contents/Helpers/pulse-statusline",
                                         clock: clock, loginItem: FakeLoginItem(), notifications: notifications, keychain: FakeKeychain(),
                                         appVersion: "0.1.0-test", timeZone: zone, locale: locale, tickInterval: .seconds(3600))
        environment.calendarDirectory = box.root.appendingPathComponent("calendar")
        environment.openFile = { [weak self] url in self?.opened.append(url) }
        return AppModel(environment: environment)
    }

    /// The first start connects Claude Code the way a user does (consent install), so the cards stay connected through
    /// long silences, as on a real Mac; relaunches find it installed.
    func start() async {
        await model.start()
        await model.requestNotifications()
        if !model.preview.installed {
            guard case .installed = await model.install() else { Issue.record("install failed"); return }
        }
    }

    /// Quit and open again on the same data, optionally in another zone (the user flew, or changed the setting).
    func relaunch(zone: TimeZone? = nil, locale: Locale? = nil) async {
        model.stop()
        if let zone { self.zone = zone }
        if let locale { self.locale = locale }
        model = makeModel()
        await start()
    }

    func finish() {
        model.stop()
        box.cleanUp()
    }

    /// One status-line frame stamped now. Returns once the snapshot shows it (or, when `applied` is false, after giving
    /// the app time to have shown it, for readings the engine must ignore).
    func frame(fiveHour: Double, fiveHourResets: Date, sevenDay: Double, sevenDayResets: Date, applied: Bool = true) async throws {
        let at = clock.now()
        let json = """
        {"v":1,"kind":"claude_code.statusline","emitted_at_ms":\(ms(at)),"shim_version":"0.1.0","source_version":"2.1.302",
         "session_ref":"0123456789abcdef","model":{"id":"claude-opus-5-5","display_name":"Opus 5.5"},
         "context":{"window_size":1000000,"used_pct":40,"total_input_tokens":400000},
         "rate_limits":{"five_hour":{"used_pct":\(fiveHour),"resets_at":\(Int64(fiveHourResets.timeIntervalSince1970))},
                        "seven_day":{"used_pct":\(sevenDay),"resets_at":\(Int64(sevenDayResets.timeIntervalSince1970))}},
         "health":{"unknown_rate_limit_windows":0}}
        """
        let bytes = try FrameCodec.encode(try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
        #expect(send(model.environment.socketPath, bytes))
        if applied {
            #expect(await eventually { self.model.snapshot.provider?.lastSeen == at })
        } else {
            try await Task.sleep(for: .milliseconds(300))
        }
        try await Task.sleep(for: .milliseconds(50))          // the alert pass runs after the snapshot refresh
    }

    /// One 30-second tick, as the app's timer runs it: reset expected, stale, purge, refresh, alerts.
    func tick() async { await model.refreshNow() }

    func travel(_ seconds: TimeInterval) async {
        clock.advance(seconds)
        await tick()
    }

    func row(_ window: String) -> PoolRow? { model.snapshot.provider?.pools.first { $0.poolKey.hasSuffix(window) } }
    var fiveHour: PoolRow? { row("five_hour") }
    var sevenDay: PoolRow? { row("seven_day") }

    /// The Limits page's line for a pool ("Resets Sun 01:30").
    func resetLine(_ row: PoolRow?) -> String? {
        row?.model.resetsAt.value.map { Copy.Limits.resets(Formatting.resetTime($0, now: model.snapshot.now, zone: zone, locale: locale)) }
    }

    /// The popover's line under the figure ("Resets 05:00 · in 5h 0m", or "Reset expected · awaiting next update").
    func countdown(_ row: PoolRow?) -> String? {
        guard let row else { return nil }
        if row.model.card == .resetExpected { return StatusStyles.of(CardState.resetExpected).label }
        guard let date = row.model.resetsAt.value else { return nil }
        guard let remaining = Formatting.countdown(to: date, now: model.snapshot.now) else { return StatusStyles.of(CardState.resetExpected).label }
        return "Resets \(Formatting.resetTime(date, now: model.snapshot.now, zone: zone, locale: locale)) · \(remaining)"
    }

    var titles: [String] { notifications.delivered.map(\.title) }

    private func ms(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }
}

private func instant(_ iso: String) -> Date { try! Date(iso, strategy: .iso8601) }
private let london = TimeZone(identifier: "Europe/London")!
private let newYork = TimeZone(identifier: "America/New_York")!
private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
private let enGB = Locale(identifier: "en_GB")
private let hour: TimeInterval = 3600, day: TimeInterval = 86_400

@MainActor
@Suite(.serialized)
struct TimeTravelTests {
    // MARK: Daylight saving

    @Test("London, clocks go back (F17): weekly reset on the absolute instant, shown in the new offset, alerts once each")
    func londonFallBack() async throws {
        // Fri 23 Oct 2026 13:00 BST. British Summer Time ends Sun 25 Oct at 01:00 UTC (02:00 BST → 01:00 GMT).
        let h = TimeTravel(at: instant("2026-10-23T12:00:00Z"), zone: london, locale: enGB)
        defer { h.finish() }
        await h.start()
        let weekly = instant("2026-10-25T00:30:00Z")            // 01:30 BST, half an hour before the change
        let fiveHour = instant("2026-10-23T17:00:00Z")
        try await h.frame(fiveHour: 10, fiveHourResets: fiveHour, sevenDay: 70, sevenDayResets: weekly)
        #expect(h.resetLine(h.sevenDay) == "Resets Sun 01:30")
        #expect(h.countdown(h.sevenDay) == "Resets Sun 01:30 · in 36h 30m")
        #expect(h.resetLine(h.fiveHour) == "Resets 18:00")

        h.clock.advance(60)
        try await h.frame(fiveHour: 12, fiveHourResets: fiveHour, sevenDay: 100, sevenDayResets: weekly)
        #expect(await eventually { h.titles == ["Claude Code · 7-day limit reached"] })
        #expect(h.notifications.delivered.first?.body == "Resets Sun 01:30.")

        // One second before the reset instant, across the evening and up to the change: nothing yet.
        await h.travel(weekly.timeIntervalSince(h.clock.now()) - 1)
        #expect(h.sevenDay?.model.card != .resetExpected)
        #expect(h.countdown(h.sevenDay) == "Resets 01:30 · in 1m")
        #expect(h.titles.count == 1)
        // The instant itself: reset expected, announced once (it reached its limit), then never again.
        await h.travel(1)
        #expect(h.sevenDay?.model.card == .resetExpected)
        #expect(h.titles.last == "Claude Code · 7-day reset time has arrived")
        await h.travel(hour)                                      // 01:30 GMT: the wall clock repeats 01:30
        await h.travel(60)
        #expect(h.titles.count == 2)

        // A fresh reading after the change: available again, the next weekly reset shown in GMT.
        let next = weekly.addingTimeInterval(7 * day)             // Sun 1 Nov 00:30 GMT: same instant arithmetic, new offset
        try await h.frame(fiveHour: 0, fiveHourResets: h.clock.now().addingTimeInterval(5 * hour), sevenDay: 4, sevenDayResets: next)
        #expect(await eventually { h.titles.count == 3 })
        #expect(h.titles.last == "Claude Code · 7-day limit available again")
        #expect(h.sevenDay?.model.resetsAt.value == next)
        #expect(h.resetLine(h.sevenDay) == "Resets 1 Nov")
        #expect(h.countdown(h.sevenDay) == "Resets 1 Nov · in 6 days")
        #expect(Set(h.notifications.delivered.map(\.identifier)).count == h.notifications.delivered.count)
    }

    @Test("London, clocks go forward: a 5-hour window across 01:00 UTC lasts five hours, not four or six")
    func londonSpringForward() async throws {
        // Sat 27 Mar 2027 23:30 GMT; BST starts Sun 28 Mar at 01:00 UTC (01:00 GMT → 02:00 BST).
        let h = TimeTravel(at: instant("2027-03-27T23:30:00Z"), zone: london, locale: enGB)
        defer { h.finish() }
        await h.start()
        let reset = instant("2027-03-28T04:30:00Z")              // 05:30 BST
        let weekly = instant("2027-04-02T09:00:00Z")             // Fri 10:00 BST
        try await h.frame(fiveHour: 60, fiveHourResets: reset, sevenDay: 20, sevenDayResets: weekly)
        #expect(h.countdown(h.fiveHour) == "Resets Sun 05:30 · in 5h 0m")
        #expect(h.resetLine(h.sevenDay) == "Resets Fri 10:00")

        await h.travel(2 * hour)                                  // 01:30 UTC = 02:30 BST: wall clock jumped an hour
        #expect(h.countdown(h.fiveHour) == "Resets 05:30 · in 3h 0m")
        try await h.frame(fiveHour: 100, fiveHourResets: reset, sevenDay: 22, sevenDayResets: weekly)
        #expect(await eventually { h.titles == ["Claude Code · 5-hour limit reached"] })
        #expect(h.notifications.delivered.first?.body == "Resets 05:30.")

        await h.travel(reset.timeIntervalSince(h.clock.now()) - 1)
        #expect(h.fiveHour?.model.card == .exhausted)
        await h.travel(1)
        #expect(h.fiveHour?.model.card == .resetExpected)
        #expect(h.titles == ["Claude Code · 5-hour limit reached", "Claude Code · 5-hour reset time has arrived"])
    }

    @Test("New York, clocks go back then forward: weekly and 5-hour resets keep their instants; text follows the offset")
    func newYorkBothWays() async throws {
        // Thu 29 Oct 2026 09:30 EDT. EDT ends Sun 1 Nov at 06:00 UTC (02:00 EDT → 01:00 EST).
        let h = TimeTravel(at: instant("2026-10-29T13:30:00Z"), zone: newYork, locale: enUS)
        defer { h.finish() }
        await h.start()
        let weekly = instant("2026-11-05T13:30:00Z")             // Thu 5 Nov 08:30 EST: seven days of seconds, an hour earlier on the wall
        try await h.frame(fiveHour: 5, fiveHourResets: instant("2026-10-29T18:30:00Z"), sevenDay: 30, sevenDayResets: weekly)
        #expect(h.resetLine(h.sevenDay) == "Resets Nov 5")
        #expect(h.resetLine(h.fiveHour) == "Resets 2:30 PM")

        await h.travel(instant("2026-11-02T13:30:00Z").timeIntervalSince(h.clock.now()))   // Mon 08:30 EST
        #expect(h.resetLine(h.sevenDay) == "Resets Thu 8:30 AM")
        #expect(h.sevenDay?.model.resetsAt.value == weekly)
        await h.travel(weekly.timeIntervalSince(h.clock.now()) - 60)
        #expect(h.countdown(h.sevenDay) == "Resets 8:30 AM · in 1m")
        await h.travel(60)
        #expect(h.sevenDay?.model.card == .resetExpected)
        #expect(h.titles.isEmpty)                                 // never hit its limit: no reset announcement

        // Spring forward, Sun 14 Mar 2027 at 07:00 UTC (02:00 EST → 03:00 EDT): a 5-hour window from midnight EST.
        await h.travel(instant("2027-03-14T05:00:00Z").timeIntervalSince(h.clock.now()))
        let reset = instant("2027-03-14T10:00:00Z")               // 06:00 EDT
        try await h.frame(fiveHour: 79, fiveHourResets: reset, sevenDay: 10, sevenDayResets: instant("2027-03-20T05:00:00Z"))
        #expect(h.countdown(h.fiveHour) == "Resets 6:00 AM · in 5h 0m")
        h.clock.advance(3 * hour)                                 // 08:00 UTC = 04:00 EDT
        try await h.frame(fiveHour: 81, fiveHourResets: reset, sevenDay: 10, sevenDayResets: instant("2027-03-20T05:00:00Z"))
        #expect(await eventually { h.titles == ["Claude Code · 5-hour limit at 80%"] })
        #expect(h.notifications.delivered.first?.body == "Resets 6:00 AM.")
        #expect(h.countdown(h.fiveHour) == "Resets 6:00 AM · in 2h 0m")
    }

    // MARK: Time zone

    @Test("Zone change mid-window (F16): same stored instant, new wall-clock text, no alert repeated")
    func zoneChange() async throws {
        let h = TimeTravel(at: instant("2026-10-16T14:00:00Z"), zone: london, locale: enUS)
        defer { h.finish() }
        await h.start()
        let reset = instant("2026-10-16T16:15:00Z")
        try await h.frame(fiveHour: 50, fiveHourResets: reset, sevenDay: 20, sevenDayResets: instant("2026-10-21T16:15:00Z"))
        h.clock.advance(60)
        try await h.frame(fiveHour: 96, fiveHourResets: reset, sevenDay: 20, sevenDayResets: instant("2026-10-21T16:15:00Z"))
        #expect(await eventually { h.titles == ["Claude Code · 5-hour limit at 95%"] })
        #expect(h.resetLine(h.fiveHour) == "Resets 5:15 PM")

        await h.relaunch(zone: losAngeles)
        await h.travel(60)
        #expect(h.fiveHour?.model.resetsAt.value == reset)
        #expect(h.resetLine(h.fiveHour) == "Resets 9:15 AM")
        #expect(h.countdown(h.fiveHour) == "Resets 9:15 AM · in 2h 13m")
        #expect(h.resetLine(h.sevenDay) == "Resets Wed 9:15 AM")
        h.clock.advance(60)
        try await h.frame(fiveHour: 97, fiveHourResets: reset, sevenDay: 20, sevenDayResets: instant("2026-10-21T16:15:00Z"))
        try await Task.sleep(for: .milliseconds(200))
        #expect(h.titles.count == 1)
    }

    @Test("The running app follows the system's time zone and clock format: the defaults update themselves")
    func liveZoneFollowsSystem() {
        let env = AppEnvironment(dataDirectory: URL(fileURLWithPath: "/tmp/unused"), home: URL(fileURLWithPath: "/tmp/unused"),
                                 shimPath: "", loginItem: FakeLoginItem(), notifications: FakeNotifications())
        // `TimeZone.current` is a snapshot: after the Mac changes zone it still answers the old one, so every reset
        // time would stay in the departure zone until a relaunch. The auto-updating values follow the system.
        #expect(env.timeZone == TimeZone.autoupdatingCurrent)
        #expect(env.locale == Locale.autoupdatingCurrent)
    }

    // MARK: Long sleeps

    @Test("90 days idle with the app running: zero alerts, both limits read reset expected, freshness says when")
    func ninetyDaysIdle() async throws {
        let h = TimeTravel(at: instant("2026-10-16T14:00:00Z"), zone: london, locale: enUS)
        defer { h.finish() }
        await h.start()
        let five = instant("2026-10-16T17:00:00Z"), seven = instant("2026-10-21T14:00:00Z")
        try await h.frame(fiveHour: 70, fiveHourResets: five, sevenDay: 70, sevenDayResets: seven)
        h.clock.advance(60)
        try await h.frame(fiveHour: 100, fiveHourResets: five, sevenDay: 100, sevenDayResets: seven)
        #expect(await eventually { h.titles.count == 2 })
        let before = h.notifications.delivered

        await h.travel(90 * day)
        await h.travel(30)
        #expect(h.notifications.delivered == before)
        #expect(h.fiveHour?.model.card == .resetExpected && h.sevenDay?.model.card == .resetExpected)
        #expect(h.countdown(h.sevenDay) == "Reset expected · awaiting next update")
        #expect(h.fiveHour.map { $0.model.isStale(now: h.clock.now(), staleAfter: Freshness.localTelemetryTTL) } == true)
        #expect(h.model.snapshot.aggregateLine == "Claude Code reset expected · awaiting next update · last seen Oct 16")
        #expect(h.fiveHour?.model.used.value == 100)              // the last measured value stays, never zeroed

        // Back at work: a fresh reading opens new windows, live again, still no alert storm.
        let now = h.clock.now()
        try await h.frame(fiveHour: 3, fiveHourResets: now.addingTimeInterval(5 * hour), sevenDay: 1, sevenDayResets: now.addingTimeInterval(7 * day))
        await h.tick()
        #expect(h.notifications.delivered == before)
        #expect(h.fiveHour?.model.card == .availableAgain)       // verified by the fresh reading; its alert is not (B4, 30-day receipts)
        #expect(h.fiveHour?.model.isStale(now: h.clock.now(), staleAfter: Freshness.localTelemetryTTL) == false)
    }

    @Test("90 days with the app quit, then opened: zero alerts on launch and on the first ticks")
    func ninetyDaysRelaunch() async throws {
        let h = TimeTravel(at: instant("2026-10-16T14:00:00Z"), zone: london, locale: enUS)
        defer { h.finish() }
        await h.start()
        let five = instant("2026-10-16T17:00:00Z"), seven = instant("2026-10-21T14:00:00Z")
        try await h.frame(fiveHour: 90, fiveHourResets: five, sevenDay: 90, sevenDayResets: seven)
        h.clock.advance(60)
        try await h.frame(fiveHour: 100, fiveHourResets: five, sevenDay: 100, sevenDayResets: seven)
        #expect(await eventually { h.titles.count == 2 })
        let before = h.notifications.delivered

        h.model.stop()
        h.clock.advance(90 * day)
        await h.relaunch()
        await h.tick()
        await h.travel(30)
        #expect(h.notifications.delivered == before)
        #expect(h.sevenDay?.model.card == .resetExpected)
    }

    @Test("A weekend asleep: a reset that passed while the Mac slept is not announced days late (fire instant > 15 min past)")
    func weekendAsleep() async throws {
        let h = TimeTravel(at: instant("2026-10-16T14:00:00Z"), zone: london, locale: enUS)
        defer { h.finish() }
        await h.start()
        let five = instant("2026-10-16T17:00:00Z"), seven = instant("2026-10-21T14:00:00Z")
        try await h.frame(fiveHour: 90, fiveHourResets: five, sevenDay: 40, sevenDayResets: seven)
        h.clock.advance(60)
        try await h.frame(fiveHour: 100, fiveHourResets: five, sevenDay: 40, sevenDayResets: seven)
        #expect(await eventually { h.titles == ["Claude Code · 5-hour limit reached"] })

        await h.travel(3 * day)                                   // Friday 15:01 → Monday: the 17:00 reset passed long ago
        #expect(h.fiveHour?.model.card == .resetExpected)
        #expect(h.titles == ["Claude Code · 5-hour limit reached"])
        #expect(h.model.diagnostics.entries.contains { $0.code == "alerts.expired" })

        // Asleep through the reset but awake within 15 minutes of it: still announced.
        h.clock.advance(60)
        let next = h.clock.now().addingTimeInterval(5 * hour)
        try await h.frame(fiveHour: 99, fiveHourResets: next, sevenDay: 41, sevenDayResets: seven)
        h.clock.advance(60)
        try await h.frame(fiveHour: 100, fiveHourResets: next, sevenDay: 41, sevenDayResets: seven)
        #expect(await eventually { h.titles.count == 2 })
        h.clock.advance(next.timeIntervalSince(h.clock.now()) + 10 * 60)
        await h.tick()
        #expect(h.titles.last == "Claude Code · 5-hour reset time has arrived")
    }

    // MARK: Clock going backwards

    @Test("Clock steps back 90 s (a time sync): earlier-stamped readings never replace newer ones, nothing alerts twice")
    func clockStepsBack() async throws {
        let h = TimeTravel(at: instant("2026-10-16T14:00:00Z"), zone: london, locale: enUS)
        defer { h.finish() }
        await h.start()
        let five = instant("2026-10-16T17:00:00Z"), seven = instant("2026-10-21T14:00:00Z")
        try await h.frame(fiveHour: 50, fiveHourResets: five, sevenDay: 20, sevenDayResets: seven)
        h.clock.advance(60)
        try await h.frame(fiveHour: 83, fiveHourResets: five, sevenDay: 20, sevenDayResets: seven)
        #expect(await eventually { h.titles == ["Claude Code · 5-hour limit at 80%"] })
        let newest = h.clock.now()

        h.clock.advance(-90)
        await h.tick()
        #expect(h.fiveHour?.model.used.value == 83)
        #expect(h.fiveHour?.model.isStale(now: h.clock.now(), staleAfter: Freshness.localTelemetryTTL) == false)
        #expect(h.model.snapshot.aggregateLine == "1 limit nearing capacity")  // live: no "last seen" suffix
        #expect(Formatting.age(of: newest, now: h.clock.now(), zone: h.zone, locale: h.locale) == "just now")   // never "-1m ago"
        // A reading stamped before the newest one is history only (DATA_MODEL §6.1).
        try await h.frame(fiveHour: 96, fiveHourResets: five, sevenDay: 20, sevenDayResets: seven, applied: false)
        #expect(h.fiveHour?.model.used.value == 83 && h.model.snapshot.provider?.lastSeen == newest)
        #expect(h.titles.count == 1)

        // Once the clock passes the newest reading again, readings apply and the 95% crossing alerts once.
        h.clock.advance(120)
        try await h.frame(fiveHour: 96, fiveHourResets: five, sevenDay: 20, sevenDayResets: seven)
        #expect(await eventually { h.titles.count == 2 })
        #expect(h.titles.last == "Claude Code · 5-hour limit at 95%")
        await h.tick()
        #expect(h.titles.count == 2)
    }

    @Test("Clock steps back across a reset that already passed: reset expected stays, no second announcement")
    func clockStepsBackAcrossReset() async throws {
        let h = TimeTravel(at: instant("2026-10-16T16:58:00Z"), zone: london, locale: enUS)
        defer { h.finish() }
        await h.start()
        let five = instant("2026-10-16T17:00:00Z"), seven = instant("2026-10-21T14:00:00Z")
        try await h.frame(fiveHour: 98, fiveHourResets: five, sevenDay: 20, sevenDayResets: seven)
        h.clock.advance(30)
        try await h.frame(fiveHour: 100, fiveHourResets: five, sevenDay: 20, sevenDayResets: seven)
        await h.travel(120)                                       // 17:00:30: reset expected, announced
        #expect(h.titles == ["Claude Code · 5-hour limit reached", "Claude Code · 5-hour reset time has arrived"])
        await h.travel(-60)                                       // 16:59:30 again
        await h.travel(45)                                        // and across 17:00 a second time
        #expect(h.fiveHour?.model.card == .resetExpected)
        #expect(h.titles.count == 2)
    }
}
