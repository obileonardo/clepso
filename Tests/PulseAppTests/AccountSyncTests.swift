@testable import ClaudeCodeAdapter
import Foundation
import Storage
@testable import Sync
import Testing
import UsageEngine
@testable import PulseApp

/// Records requests and answers from a queue (default 200, empty body).
final class RecordingTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [(Int, String)] = []
    private var log: [URLRequest] = []
    func respond(_ status: Int, _ body: String) { lock.withLock { queue.append((status, body)) } }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body) = lock.withLock { () -> (Int, String) in log.append(request); return queue.isEmpty ? (200, "") : queue.removeFirst() }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    var paths: [String] { lock.withLock { log.map { $0.url!.path } } }
    var bodies: String { lock.withLock { log.map { String(decoding: $0.httpBody ?? Data(), as: UTF8.self) }.joined(separator: "\n") } }
}

/// ROADMAP 2.0 step 2: what an upload contains, and the account flow through the app.
@MainActor
@Suite("Accounts in the app", .serialized)
struct AccountSyncTests {
    func stats() throws -> ClaudeCodeStats {
        guard case .success(let s) = StatsReader.parse(Data(StatsTests.file.utf8)) else { throw CancellationError() }
        return s
    }

    @Test("The payload has only what's turned on, within 14 days, with no ids or paths")
    func payload() throws {
        let utc = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_792_159_200)                    // 16 Oct 2026 14:00 UTC
        let day: Double = 86_400
        let task = Store.AgentTask(id: "task-uuid-should-not-leak", sessionRef: "0123456789abcdef", startedAt: now - 3600, endedAt: nil,
                                   fromPrompt: true, byType: ["Explore": 2, "custom": 1], finished: 1)
        var input = SyncPayloadBuilder.Input(profileName: "Elvis", planLabel: "Max 5×", stats: nil,
                                             fiveHour: [UsagePoint(at: now - day, usedPct: 40), UsagePoint(at: now - 60, usedPct: 63), UsagePoint(at: now - 120, usedPct: 70),
                                                        UsagePoint(at: now - 20 * day, usedPct: 99)],
                                             sevenDay: [UsagePoint(at: now - 7200, usedPct: 18), UsagePoint(at: now - 60, usedPct: 21)],
                                             agentTasks: nil, goals: Goals(weeklyFinishMax: nil),
                                             goalStatuses: [GoalStatus(kind: .fiveHourPeak, value: "70%", amount: 70, target: "≤ 80%", fraction: 0.875, state: .onTrack, detail: "", streak: 1),
                                                            GoalStatus(kind: .activeDays, value: "—", target: "5/7", fraction: 0, state: .noData, detail: "", streak: nil)],
                                             now: now, zone: utc)
        var payload = SyncPayloadBuilder.make(input)
        #expect(payload.activity.isEmpty && payload.modelTokens.isEmpty && payload.modelTotals.isEmpty, "stats off: none of its rows")
        #expect(payload.agents.isEmpty, "agent counting off: no agent rows")
        #expect(payload.limits == [.init(day: "2026-10-15", fiveHourPeakPct: 40, sevenDayEndPct: nil),
                                   .init(day: "2026-10-16", fiveHourPeakPct: 70, sevenDayEndPct: 21)], "20 days ago is outside the window")
        #expect(payload.goals.map(\.target) == [5, 80, nil])
        #expect(payload.goalDays == [.init(day: "2026-10-16", kind: "fiveHourPeak", value: 70, met: true)], "no row for a goal without data")

        input.stats = try stats()
        input.agentTasks = [task]
        payload = SyncPayloadBuilder.make(input)
        #expect(!payload.modelTotals.isEmpty)
        #expect(payload.activity.allSatisfy { $0.day >= "2026-10-03" && $0.day <= "2026-10-16" })
        #expect(payload.agents == [.init(day: "2026-10-16", tasks: 1, agents: 3, byType: ["Explore": 2, "custom": 1])])
        let encoder = JSONEncoder()
        let text = [try encoder.encode(payload.agents), try encoder.encode(payload.limits), try encoder.encode(payload.activity)]
            .map { String(decoding: $0, as: UTF8.self) }.joined()
        #expect(!text.contains("0123456789abcdef") && !text.contains("task-uuid") && !text.contains("/Users"))
    }

    @Test("Email link, sign-in from the link, upload; never while demo data shows; delete-all signs out")
    func flow() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let transport = RecordingTransport(), store = MemoryAuthStore(), clock = TestClock()
        var environment = box.model(clock: clock).environment
        environment.sync = SyncClient(config: .production, transport: transport, store: store, now: { clock.now() })
        let model = AppModel(environment: environment)
        await model.start(); defer { model.stop() }

        await model.emailSignInLink("not-an-email")
        #expect(model.account == .signedOut && model.accountMessage == Copy.Sync.invalidEmail && transport.paths.isEmpty)
        await model.emailSignInLink("e@example.test")
        #expect(model.account == .linkSent(email: "e@example.test") && transport.paths == ["/auth/v1/otp"])

        await model.handleOpenURL(URL(string: "https://elsewhere.test/?code=x")!)          // not ours: ignored
        #expect(model.account == .linkSent(email: "e@example.test"))
        transport.respond(200, #"{"access_token":"a","refresh_token":"r","expires_in":3600,"user":{"id":"u-1","email":"e@example.test"}}"#)
        await model.handleOpenURL(URL(string: "dev.tokone.pulse://auth-callback?code=abc")!)
        #expect(model.account == .signedIn(email: "e@example.test") && model.detailsSection == .account)
        #expect(transport.paths.contains("/rest/v1/profiles") && transport.paths.contains("/rest/v1/goals"), "first upload right after signing in")
        #expect(model.lastSync == clock.now())
        #expect(!transport.bodies.contains("e@example.test") || transport.paths.first == "/auth/v1/otp", "the email goes to Auth only")

        let before = transport.paths.count
        await model.setDemo(true)
        await model.syncNow()
        #expect(transport.paths.count == before, "no upload while demo data shows")
        await model.setDemo(false)

        _ = await model.deleteAll(includeBackups: false, relaunch: false)
        #expect(model.account == .signedOut && store.load() == StoredAuth())
        #expect(transport.paths.last == "/auth/v1/logout")
    }
}
