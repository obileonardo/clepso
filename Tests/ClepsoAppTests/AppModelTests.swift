import CryptoKit
import Foundation
import SubscriptionCatalog
import Testing
@testable import ClepsoApp

@MainActor
@Suite("AppModel: composition root (socket → store → snapshot), consent and preferences", .serialized)
struct AppModelTests {
    @Test("A frame on the socket reaches the snapshot; nothing asks for permissions on start")
    func frameReachesSnapshot() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let clock = TestClock(), login = FakeLoginItem(), notifications = FakeNotifications()
        let model = box.model(clock: clock, login: login, notifications: notifications)
        await model.start(); defer { model.stop() }
        #expect(model.problem == nil)
        #expect(model.snapshot.empty == .notConnected)

        #expect(send(model.environment.socketPath, try frameBytes(at: clock.now(), fiveHour: 83)))
        #expect(await eventually { model.snapshot.provider?.pools.count == 2 })
        let fiveHour = try #require(model.snapshot.provider?.pools.first)
        #expect(fiveHour.model.used.value == 83 && fiveHour.model.card == .approaching)
        #expect(model.snapshot.provider?.sourceVersion == "2.1.302")
        #expect(model.snapshot.provider?.session?.modelName == "Opus 5.5")
        #expect(model.firstRealReadingAt == clock.now())
        #expect(login.calls.isEmpty, "no login item without consent")
        #expect(notifications.requestCount == 0, "no notification prompt on start")

        // Database file and folder permissions (PRIVACY_AND_SECURITY §4).
        let attributes = try FileManager.default.attributesOfItem(atPath: model.environment.databaseURL.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
    }

    @Test("C7: a frame reporting an unread limit window reaches the detail view and the diagnostics log")
    func unreadLimitWindows() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let clock = TestClock()
        let model = box.model(clock: clock)
        await model.start(); defer { model.stop() }
        #expect(send(model.environment.socketPath, try frameBytes(at: clock.now(), unreadWindows: 1)))
        #expect(await eventually { model.snapshot.provider != nil })
        await model.refreshIngestHealth()
        await model.refresh()
        #expect(model.snapshot.provider?.unreadLimitWindows == 1)
        #expect(model.diagnostics.entries.contains { $0.code == "ingest.unreadLimitWindows" && $0.text.contains("1 limit(s)") })
    }

    @Test("A real reading ends demo mode")
    func realReadingEndsDemo() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let clock = TestClock()
        let model = box.model(clock: clock)
        await model.start(); defer { model.stop() }
        await model.setDemo(true)
        #expect(model.snapshot.isDemo && model.snapshot.icon == .demo)
        #expect(model.snapshot.provider?.pools.first?.model.used.value == 83, "demo runs through the real engine")

        #expect(send(model.environment.socketPath, try frameBytes(at: clock.now(), fiveHour: 14)))
        #expect(await eventually { !model.snapshot.isDemo })
        #expect(!model.demo)
        #expect(model.snapshot.provider?.pools.first?.model.used.value == 14)
    }

    @Test("Plan choice is stored with its provenance and survives a restart")
    func planAndPreferencesPersist() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let clock = TestClock()
        let first = box.model(clock: clock)
        await first.start()
        let max5 = try #require(first.catalog?.claudePlans.first { $0.id == "anthropic.max.5x" })
        await first.choosePlan(max5, confirmed: true)
        await first.setShowPercent(false)
        await first.completeOnboarding()
        first.stop()

        let second = box.model(clock: clock)
        await second.start(); defer { second.stop() }
        #expect(second.problem == nil, "\(String(describing: second.problem))")
        #expect(second.plan?.catalogID == "anthropic.max.5x" && second.plan?.evidence == .userConfirmed)
        #expect(!second.showPercent && second.onboardingComplete)

        await second.choosePlan(nil, confirmed: false)
        #expect(second.plan == nil, "Not sure ends the plan")
    }

    @Test("Install happens only through install(): preview reads, install wraps, Remove restores byte for byte")
    func consentInstallAndRemove() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let original = Data("{\n  \"model\": \"opus\",\n  \"statusLine\": {\"type\": \"command\", \"command\": \"~/bin/my-line.sh\"}\n}\n".utf8)
        try original.write(to: box.settings)
        let model = box.model(clock: TestClock())
        await model.start(); defer { model.stop() }

        #expect(model.preview.claudeDetected && model.preview.settingsExists && !model.preview.installed)
        #expect(model.preview.existingCommand == "~/bin/my-line.sh")
        #expect(model.preview.refusal == nil)
        #expect(try Data(contentsOf: box.settings) == original, "starting the app and previewing never writes")

        let outcome = await model.install()
        guard case .installed(let backup, let kept) = outcome else { Issue.record("\(outcome)"); return }
        #expect(kept && backup != nil)
        #expect(model.preview.installed)
        #expect(String(decoding: try Data(contentsOf: box.settings), as: UTF8.self).contains(".claude/pulse/statusline.sh"))
        #expect(model.snapshot.empty == .waitingForFirstReading)

        #expect(await model.uninstall() == .restoredExactly)
        #expect(SHA256.hash(data: try Data(contentsOf: box.settings)) == SHA256.hash(data: original))
        #expect(!model.preview.installed)
    }

    @Test("A settings file install would refuse is reported before any write, in plain words")
    func refusalIsPreviewed() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let broken = Data(#"{"model": "opus",}"#.utf8)
        try broken.write(to: box.settings)
        let model = box.model(clock: TestClock())
        await model.start(); defer { model.stop() }
        #expect(model.preview.refusal == .settingsInvalidJSON)
        let outcome = await model.install()
        #expect(outcome == .failed(reason: "Claude Code's settings file isn't valid JSON, so it was left alone."))
        #expect(try Data(contentsOf: box.settings) == broken)
    }

    @Test("Login item and notification prompt change only on explicit calls")
    func consentGates() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let login = FakeLoginItem(), notifications = FakeNotifications()
        let model = box.model(clock: TestClock(), login: login, notifications: notifications)
        await model.start(); defer { model.stop() }
        await model.setDemo(true)
        await model.completeOnboarding()
        #expect(login.calls.isEmpty && notifications.requestCount == 0)

        await model.setLoginItem(true)
        #expect(login.calls == [true] && model.loginItemEnabled)
        await model.requestNotifications()
        #expect(notifications.requestCount == 1 && model.notificationStatus == .authorized)
    }

    @Test("A system report of 'enabled' without the user's choice shows off; the choice survives a restart")
    func loginItemNeedsTheUsersChoice() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let clock = TestClock()
        let spurious = FakeLoginItem(reportsEnabled: true)
        let first = box.model(clock: clock, login: spurious)
        await first.start()
        #expect(!first.loginItemEnabled, "never claim a login item the user did not turn on")
        await first.setLoginItem(true)
        #expect(first.loginItemEnabled && spurious.calls == [true])
        first.stop()

        let second = box.model(clock: clock, login: spurious)
        await second.start(); defer { second.stop() }
        #expect(second.loginItemEnabled)
        #expect(spurious.calls == [true], "starting never registers")
    }

    @Test("A socket path that is not a socket is a visible problem; Reconnect recovers once it is fixed")
    func socketProblemAndReconnect() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let model = box.model(clock: TestClock())
        let socketURL = URL(fileURLWithPath: model.environment.socketPath)
        try FileManager.default.createDirectory(at: socketURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try Data("not a socket".utf8).write(to: socketURL)
        await model.start(); defer { model.stop() }
        guard case .socket = model.problem else { Issue.record("expected a socket problem, got \(String(describing: model.problem))"); return }

        try FileManager.default.removeItem(at: socketURL)
        model.reconnect()
        #expect(model.problem == nil)
    }
}
