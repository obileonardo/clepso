import CryptoKit
import Foundation
import Storage
import Testing
@testable import ClepsoApp

/// Increment 1.5: diagnostics log, export and delete-all (PRIVACY_AND_SECURITY §5, §6, §8).
@MainActor
@Suite("Data lifecycle: diagnostics, export, delete-all", .serialized)
struct DataLifecycleTests {
    static let original = Data("{\n  \"model\": \"opus\",\n  \"statusLine\": {\"type\": \"command\", \"command\": \"~/bin/my-line.sh\"}\n}\n".utf8)

    /// A model that has been used: installed, a reading, a plan, demo seen, login item chosen, an export logged.
    func usedModel(_ box: Sandbox, login: FakeLoginItem, notifications: FakeNotifications, keychain: FakeKeychain) async throws -> AppModel {
        try Self.original.write(to: box.settings)
        let clock = TestClock()
        let model = box.model(clock: clock, login: login, notifications: notifications, keychain: keychain)
        await model.start()
        guard case .installed = await model.install() else { throw CancellationError() }
        #expect(send(model.environment.socketPath, try frameBytes(at: clock.now(), fiveHour: 83)))
        #expect(await eventually { model.snapshot.provider?.pools.count == 2 })
        await model.choosePlan(model.catalog?.claudePlans.first, confirmed: true)
        await model.setLoginItem(true)
        await model.completeOnboarding()
        return model
    }

    @Test("Delete all leaves nothing behind: data folder gone, ~/.claude/pulse gone, settings restored byte for byte")
    func deleteAllLeavesNothing() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let login = FakeLoginItem(), notifications = FakeNotifications(), keychain = FakeKeychain()
        let model = try await usedModel(box, login: login, notifications: notifications, keychain: keychain)
        let before = Sandbox.inventory(box.data)
        #expect(before.contains("pulse.sqlite") && before.contains("diagnostics.jsonl") && before.contains("run/agent.sock"), "\(before)")
        #expect(FileManager.default.fileExists(atPath: box.home.appendingPathComponent(".claude/pulse").path))

        let report = await model.deleteAll(includeBackups: false, relaunch: false)

        #expect(report == AppModel.DeleteReport(failure: nil, leftovers: [], backupsRemoved: false))
        #expect(!FileManager.default.fileExists(atPath: box.data.path), "left: \(Sandbox.inventory(box.data))")
        #expect(!FileManager.default.fileExists(atPath: box.home.appendingPathComponent(".claude/pulse").path))
        #expect(SHA256.hash(data: try Data(contentsOf: box.settings)) == SHA256.hash(data: Self.original))
        #expect(!Sandbox.inventory(box.home.appendingPathComponent(".claude/pulse-backups")).isEmpty, "backups kept by default")
        #expect(notifications.removeAllCount == 1 && keychain.sweepCount == 1)
        #expect(login.calls == [true, false], "the login item the user turned on is turned off")
        // First-run state in memory.
        #expect(!model.onboardingComplete && model.plan == nil && !model.demo && model.firstRealReadingAt == nil)
        #expect(model.snapshot.empty == .notConnected && model.diagnostics.entries.isEmpty)
    }

    @Test("After delete all the app relaunches into first run on an empty database, and still works")
    func relaunchIntoFirstRun() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let model = try await usedModel(box, login: FakeLoginItem(), notifications: FakeNotifications(), keychain: FakeKeychain())
        let report = await model.deleteAll(includeBackups: true)
        defer { model.stop() }
        #expect(report.failure == nil && report.backupsRemoved)
        #expect(!FileManager.default.fileExists(atPath: box.home.appendingPathComponent(".claude/pulse-backups").path))
        #expect(model.started && !model.onboardingComplete && model.plan == nil)
        let store = try Store.onDisk(at: model.environment.databaseURL, now: t0)
        #expect(try await store.poolStates().isEmpty)
        #expect(try await store.sessionSummaries(limit: 10).isEmpty)
        #expect(try await store.preference("onboarding.completed", as: Bool.self) == nil)
        #expect(model.diagnostics.entries.map(\.code).allSatisfy { ["app.started", "socket.listening"].contains($0) },
                "\(model.diagnostics.entries.map(\.code))")
        #expect(send(model.environment.socketPath, try frameBytes(at: t0, fiveHour: 5)))
        #expect(await eventually { model.snapshot.provider?.pools.first?.model.used.value == 5 })
    }

    @Test("If settings cannot be restored safely, delete all deletes nothing")
    func restoreFailureDeletesNothing() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let model = try await usedModel(box, login: FakeLoginItem(), notifications: FakeNotifications(), keychain: FakeKeychain())
        defer { model.stop() }
        // Tamper with the backup: an exact restore would now write the wrong bytes, so uninstall refuses.
        let backups = box.home.appendingPathComponent(".claude/pulse-backups")
        let backup = try #require(Sandbox.inventory(backups).first { $0.hasSuffix(".bak") })
        try Data("tampered".utf8).write(to: backups.appendingPathComponent(backup))
        let before = Sandbox.inventory(box.data)

        let report = await model.deleteAll(includeBackups: true)

        #expect(report.failure?.contains("nothing was deleted") == true)
        #expect(Sandbox.inventory(box.data) == before)
        #expect(FileManager.default.fileExists(atPath: box.home.appendingPathComponent(".claude/pulse/config.json").path))
        #expect(model.onboardingComplete && model.plan != nil, "state untouched")
        #expect(send(model.environment.socketPath, try frameBytes(at: t0 + 60, fiveHour: 90)), "listening again")
    }

    @Test("Only what's ticked goes: diagnostics and notifications alone leave data, settings, account and login item")
    func partialDeleteKeepsTheRest() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let login = FakeLoginItem(), notifications = FakeNotifications(), keychain = FakeKeychain()
        let model = try await usedModel(box, login: login, notifications: notifications, keychain: keychain)
        defer { model.stop() }
        let report = await model.delete([.diagnostics, .notifications], includeBackups: false)
        #expect(report == AppModel.DeleteReport(failure: nil, leftovers: [], backupsRemoved: false))
        #expect(notifications.removeAllCount == 1 && keychain.sweepCount == 0 && login.calls == [true])
        #expect(model.diagnostics.entries.isEmpty)
        #expect(FileManager.default.fileExists(atPath: box.data.appendingPathComponent("pulse.sqlite").path))
        #expect(FileManager.default.fileExists(atPath: box.home.appendingPathComponent(".claude/pulse/config.json").path))
        #expect(model.onboardingComplete && model.plan != nil)
        #expect(send(model.environment.socketPath, try frameBytes(at: t0 + 60, fiveHour: 91)), "still listening")
        #expect(await eventually { model.snapshot.provider?.pools.first?.model.used.value == 91 })
    }

    @Test("Claude Code alone: settings restored byte for byte and the helper folder gone; readings and plan kept")
    func claudeCodeOnly() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let keychain = FakeKeychain()
        let model = try await usedModel(box, login: FakeLoginItem(), notifications: FakeNotifications(), keychain: keychain)
        defer { model.stop() }
        let report = await model.delete([.claudeCode], includeBackups: false)
        #expect(report.failure == nil)
        #expect(SHA256.hash(data: try Data(contentsOf: box.settings)) == SHA256.hash(data: Self.original))
        #expect(!FileManager.default.fileExists(atPath: box.home.appendingPathComponent(".claude/pulse").path))
        #expect(FileManager.default.fileExists(atPath: box.data.appendingPathComponent("pulse.sqlite").path))
        #expect(model.plan != nil && model.onboardingComplete && keychain.sweepCount == 0)
    }

    @Test("Data alone: a fresh database and first-run state, while Claude Code stays connected and readings keep coming")
    func dataOnly() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let model = try await usedModel(box, login: FakeLoginItem(), notifications: FakeNotifications(), keychain: FakeKeychain())
        defer { model.stop() }
        let report = await model.delete([.data], includeBackups: false)
        #expect(report.failure == nil)
        #expect(model.started && !model.onboardingComplete && model.plan == nil)
        #expect(FileManager.default.fileExists(atPath: box.home.appendingPathComponent(".claude/pulse/config.json").path))
        let store = try Store.onDisk(at: model.environment.databaseURL, now: t0)
        #expect(try await store.preference("onboarding.completed", as: Bool.self) == nil)
        #expect(send(model.environment.socketPath, try frameBytes(at: t0 + 60, fiveHour: 7)))
        #expect(await eventually { model.snapshot.provider?.pools.first?.model.used.value == 7 })
    }

    @Test("A file Clepso did not create is left in place and named")
    func unknownFilesAreReported() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let model = try await usedModel(box, login: FakeLoginItem(), notifications: FakeNotifications(), keychain: FakeKeychain())
        try Data("mine".utf8).write(to: box.data.appendingPathComponent("notes.txt"))
        let report = await model.deleteAll(includeBackups: false, relaunch: false)
        #expect(report.leftovers == ["notes.txt"])
        #expect(Sandbox.inventory(box.data) == ["notes.txt"])
    }

    @Test("Export: header, the six tables, 0600, no dedupe hash, and a failing string becomes null and is counted")
    func export() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let model = try await usedModel(box, login: FakeLoginItem(), notifications: FakeNotifications(), keychain: FakeKeychain())
        defer { model.stop() }
        // A preference value that the scrub must catch (a path).
        let store = try Store.onDisk(at: model.environment.databaseURL, now: t0)
        try await store.setPreference("test.path", "/Users/someone/secret", now: t0)

        let url = box.root.appendingPathComponent("export.json")
        guard case .success(let summary) = await model.export(to: url) else { Issue.record("export failed"); return }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
        let text = try String(contentsOf: url, encoding: .utf8)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let header = try #require(json["header"] as? [String: Any])
        #expect(header["schemaVersion"] as? Int == 1 && header["appVersion"] as? String == "0.1.0-test" && header["retentionDays"] as? Int == 90)
        let tables = try #require(json["tables"] as? [String: Any])
        #expect(Set(tables.keys) == Set(Store.exportTables))
        #expect(summary.rowsByTable["observations"] ?? 0 > 0 && summary.scrubbed >= 1)
        #expect(!text.contains("dedupe_key") && !text.contains("/Users/") && !text.contains("my-line.sh"))
        #expect(model.diagnostics.entries.last?.code == "data.exported")
    }

    @Test("Diagnostics log: ASCII lines, 0600, a failing line keeps only its code, 7-day and 1 MB limits")
    func diagnosticsLog() throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let clock = TestClock()
        let url = box.root.appendingPathComponent("d/diagnostics.jsonl")
        let log = DiagnosticsLog(url: url, clock: clock)
        log.record(.listening)
        log.record(.installRefused(reason: "/Users/someone/.claude"))           // a path can only arrive by mistake
        #expect(log.entries.map(\.text) == ["Listening for Claude Code updates", "(details removed)"])
        #expect((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) == 0o600)
        #expect(!(try String(contentsOf: url, encoding: .utf8)).contains("/Users/"))

        clock.advance(8 * 86_400)
        let reopened = DiagnosticsLog(url: url, clock: clock)
        #expect(reopened.entries.isEmpty, "older than 7 days is dropped on open")

        for i in 0..<9000 { reopened.record(.exported(rows: i, scrubbed: 0)) }      // ~110 bytes each, about 1 MB
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        #expect(size <= DiagnosticsLog.maxBytes, "\(size)")
        #expect(reopened.entries.last?.text == "Exported 8999 rows, 0 value(s) removed by the scrub", "newest kept")
        reopened.clear()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
