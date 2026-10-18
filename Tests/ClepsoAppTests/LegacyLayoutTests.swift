import ClaudeCodeAdapter
import CryptoKit
import Darwin
import Foundation
import SQLite3
import Storage
import Testing
@testable import ClepsoApp

/// The rename from Pulse to Clepso, as the app sees it at launch: `~/Library/Application Support/Pulse` (with
/// `pulse.sqlite`) and `~/.claude/pulse` move before anything is opened; Remove and Delete work from either layout.
@MainActor
@Suite("Launch moves the layout from before the rename", .serialized)
struct LegacyLayoutTests {
    static let original = Data("""
    {
      "model": "opus",
      "statusLine": {"type": "command", "command": "~/bin/my-line.sh", "padding": 0},
      "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "afplay done.aiff"}]}]}
    }

    """.utf8)

    var fm: FileManager { .default }

    func environment(_ box: Sandbox, clock: TestClock, keychain: FakeKeychain = FakeKeychain()) -> AppEnvironment {
        AppEnvironment(dataDirectory: box.root.appendingPathComponent("Clepso"), home: box.home,
                       shimPath: "/Applications/Clepso.app/Contents/Helpers/clepso-statusline", clock: clock,
                       loginItem: FakeLoginItem(), notifications: FakeNotifications(), keychain: keychain, appVersion: "0.1.0-test",
                       timeZone: utc, locale: enUS, tickInterval: .seconds(3600),
                       legacyDataDirectory: box.root.appendingPathComponent("Pulse"))
    }

    func legacyData(_ box: Sandbox) -> URL { box.root.appendingPathComponent("Pulse") }
    func currentData(_ box: Sandbox) -> URL { box.root.appendingPathComponent("Clepso") }

    /// The old data folder. `wal`: as a crash would leave a write-ahead-log database, `pulse.sqlite` copied while the app
    /// still had it open, so the latest writes are only in `pulse.sqlite-wal`. Otherwise as the app leaves it on quit
    /// (the store uses SQLite's default rollback journal): `pulse.sqlite` alone. Either way a diagnostics log, a
    /// schema-migration backup and a stale socket.
    func writeOldDataFolder(_ box: Sandbox, into folder: URL, wal: Bool = true) async throws {
        let scratch = box.root.appendingPathComponent("scratch-\(UUID().uuidString.prefix(4))")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        try fm.createDirectory(at: folder.appendingPathComponent("run"), withIntermediateDirectories: true)
        let path = scratch.appendingPathComponent("pulse.sqlite")
        if wal {
            try await Store.onDisk(at: path, now: t0).close()
            var db: OpaquePointer?
            #expect(sqlite3_open(path.path, &db) == SQLITE_OK)
            #expect(sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil) == SQLITE_OK)
            sqlite3_close(db)
        }
        let store = try Store.onDisk(at: path, now: t0)
        try await store.setPreference(AppModel.Pref.onboardingComplete, true, now: t0)
        try await store.setPreference(AppModel.Pref.profileName, "Ada", now: t0)
        if !wal { try await store.close() }
        for name in try fm.contentsOfDirectory(atPath: scratch.path) {
            try fm.copyItem(at: scratch.appendingPathComponent(name), to: folder.appendingPathComponent(name))
        }
        if wal { try await store.close() }
        #expect(fm.fileExists(atPath: folder.appendingPathComponent("pulse.sqlite-wal").path) == wal)
        let log = DiagnosticsLog(url: folder.appendingPathComponent("diagnostics.jsonl"), clock: TestClock())
        log.record(.demo(on: true))
        try Data("backup".utf8).write(to: folder.appendingPathComponent("pulse.sqlite.pre-v2_value_kinds.bak"))
        staleSocket(folder.appendingPathComponent("run/agent.sock").path)
    }

    /// A socket file nobody listens on, as a quit app leaves it.
    func staleSocket(_ path: String) {
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in raw.copyBytes(from: bytes); raw[bytes.count] = 0 }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        _ = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        close(fd)
    }

    /// The install the app made before the rename: status line and hooks in `~/.claude/pulse`, backups in
    /// `~/.claude/pulse-backups`, settings.json pointing there.
    func installOldClaudeLayout(_ box: Sandbox) throws {
        try Self.original.write(to: box.settings)
        let paths = SettingsInstaller.Paths.legacy(home: box.home)
        let oldShim = "/Applications/Clepso.app/Contents/Helpers/pulse-statusline"
        _ = try SettingsInstaller(paths: paths, shimPath: oldShim, socketPath: legacyData(box).appendingPathComponent("run/agent.sock").path,
                                  now: { t0 }).install()
        try HooksInstaller(paths: paths, shimPath: oldShim, now: { t0 }).install()
    }

    @Test("The old data folder moves before anything opens it; the database keeps every value, its log included")
    func dataFolderMoves() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        try await writeOldDataFolder(box, into: legacyData(box))
        let clock = TestClock()
        let model = AppModel(environment: environment(box, clock: clock))
        await model.start(); defer { model.stop() }

        #expect(model.problem == nil)
        #expect(!fm.fileExists(atPath: legacyData(box).path))
        let files = Sandbox.inventory(currentData(box))
        #expect(files.contains("clepso.sqlite") && files.contains("clepso.sqlite.pre-v2_value_kinds.bak"), "\(files)")
        #expect(!files.contains { $0.hasPrefix("pulse.") }, "\(files)")
        #expect(model.onboardingComplete && model.profileName == "Ada", "values written only to the -wal arrived")
        #expect(model.diagnostics.entries.contains { $0.code == "demo.changed" }, "the old diagnostics log is the log")
        #expect(model.diagnostics.entries.contains { $0.code == "migration.legacyLayout" && $0.level == .info })
        // The socket is the new folder's, and it works.
        #expect(send(model.environment.socketPath, try frameBytes(at: clock.now(), fiveHour: 61)))
        #expect(await eventually { model.snapshot.provider?.pools.first?.model.used.value == 61 })

        // The next launch has nothing left to move.
        model.stop()
        let again = AppModel(environment: environment(box, clock: clock))
        await again.start(); defer { again.stop() }
        #expect(again.problem == nil && again.onboardingComplete)
        #expect(again.diagnostics.entries.filter { $0.code == "migration.legacyLayout" }.count == 1, "logged once, by the launch that moved it")
    }

    @Test("Interrupted while renaming the database files: the next launch finishes, nothing is lost")
    func resumeDatabaseRename() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let folder = currentData(box)
        try await writeOldDataFolder(box, into: folder)
        // A crash after the first companion moved: the log is already clepso.sqlite-wal, the database still pulse.sqlite.
        #expect(rename(folder.appendingPathComponent("pulse.sqlite-wal").path, folder.appendingPathComponent("clepso.sqlite-wal").path) == 0)
        let model = AppModel(environment: environment(box, clock: TestClock()))
        await model.start(); defer { model.stop() }
        #expect(model.problem == nil && model.onboardingComplete && model.profileName == "Ada")
        #expect(!Sandbox.inventory(folder).contains { $0.hasPrefix("pulse.") })
    }

    @Test("Both data folders exist: the new one is used, the old one is left exactly as it was")
    func bothDataFolders() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        try await writeOldDataFolder(box, into: legacyData(box))
        try fm.createDirectory(at: currentData(box), withIntermediateDirectories: true)
        let before = Sandbox.inventory(legacyData(box))
        let model = AppModel(environment: environment(box, clock: TestClock()))
        await model.start(); defer { model.stop() }
        #expect(model.problem == nil && !model.onboardingComplete, "a fresh database in the new folder")
        #expect(Sandbox.inventory(legacyData(box)) == before)
        #expect(model.diagnostics.entries.contains { $0.code == "migration.legacyLayout" && $0.level == .warning })
    }

    @Test("pulse.sqlite and clepso.sqlite side by side: clepso.sqlite is used, pulse.sqlite stays")
    func bothDatabases() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        try await writeOldDataFolder(box, into: currentData(box))
        _ = try Store.onDisk(at: currentData(box).appendingPathComponent("clepso.sqlite"), now: t0)
        let model = AppModel(environment: environment(box, clock: TestClock()))
        await model.start(); defer { model.stop() }
        #expect(model.problem == nil && !model.onboardingComplete)
        #expect(fm.fileExists(atPath: currentData(box).appendingPathComponent("pulse.sqlite").path))
    }

    @Test("Another copy still listening in the old folder: nothing moves, nothing is created, the store stays closed")
    func oldAppStillRunning() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        try await writeOldDataFolder(box, into: legacyData(box))
        let socketPath = legacyData(box).appendingPathComponent("run/agent.sock").path
        unlink(socketPath)
        var oldApp: IngestSocket? = try IngestSocket(path: socketPath)
        oldApp?.start()
        let before = Sandbox.inventory(legacyData(box))
        let model = AppModel(environment: environment(box, clock: TestClock()))
        await model.start()
        #expect(model.problem == .storage("legacyInUse"))
        #expect(!fm.fileExists(atPath: currentData(box).path), "nothing written to the new folder")
        #expect(Sandbox.inventory(legacyData(box)) == before)
        #expect(model.diagnostics.entries.contains { $0.code == "migration.legacyLayout" })
        model.stop()

        // The other copy quits: the next launch moves everything.
        oldApp?.stop()
        oldApp = nil
        let next = AppModel(environment: environment(box, clock: TestClock()))
        await next.start(); defer { next.stop() }
        #expect(next.problem == nil && next.onboardingComplete)
        #expect(!fm.fileExists(atPath: legacyData(box).path))
    }

    @Test("The whole old layout: data and ~/.claude move, settings.json changes only in Clepso's entries, a reading arrives, Remove restores the original")
    func wholeOldLayout() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        try await writeOldDataFolder(box, into: legacyData(box), wal: false)
        try installOldClaudeLayout(box)
        let oldSettings = try Data(contentsOf: box.settings)
        let clock = TestClock()
        let model = AppModel(environment: environment(box, clock: clock))
        await model.start(); defer { model.stop() }

        let claude = box.home.appendingPathComponent(".claude")
        #expect(!fm.fileExists(atPath: claude.appendingPathComponent("pulse").path))
        #expect(!fm.fileExists(atPath: claude.appendingPathComponent("pulse-backups").path))
        #expect(model.preview.installed && model.agentsCounting)
        #expect(model.onboardingComplete && model.profileName == "Ada")
        let migrated = try Data(contentsOf: box.settings)
        let restoredText = String(decoding: migrated, as: UTF8.self)
            .replacingOccurrences(of: "~/.claude/clepso/", with: "~/.claude/pulse/")
        #expect(Data(restoredText.utf8) == oldSettings, "only Clepso's command strings changed")
        // Launch repair: the wrapper runs the new helper, the config names the new socket and key.
        let wrapper = String(decoding: try Data(contentsOf: claude.appendingPathComponent("clepso/statusline.sh")), as: UTF8.self)
        #expect(wrapper.contains("CLEPSO_SHIM='/Applications/Clepso.app/Contents/Helpers/clepso-statusline'"))
        let config = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: claude.appendingPathComponent("clepso/config.json"))) as? [String: Any])
        #expect(config["socket"] as? String == model.environment.socketPath)
        #expect(config["hmac_key_file"] as? String == claude.appendingPathComponent("clepso/session.key").path)
        #expect(config["original_command"] as? String == "~/bin/my-line.sh")
        let hook = String(decoding: try Data(contentsOf: claude.appendingPathComponent("clepso/hook.sh")), as: UTF8.self)
        #expect(hook.contains("CLEPSO_SHIM='/Applications/Clepso.app/Contents/Helpers/clepso-statusline'"))

        #expect(send(model.environment.socketPath, try frameBytes(at: clock.now(), fiveHour: 47)))
        #expect(await eventually { model.snapshot.provider?.pools.first?.model.used.value == 47 })

        #expect(await model.uninstall() == .restoredExactly)
        #expect(try Data(contentsOf: box.settings) == Self.original)
    }

    @Test("Delete all from the moved layout leaves nothing: no data folder (old or new), no helper folder, original settings")
    func deleteAllAfterMove() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        try await writeOldDataFolder(box, into: legacyData(box))
        try installOldClaudeLayout(box)
        let model = AppModel(environment: environment(box, clock: TestClock()))
        await model.start()
        let report = await model.deleteAll(includeBackups: true, relaunch: false)
        #expect(report == AppModel.DeleteReport(failure: nil, leftovers: [], backupsRemoved: true))
        #expect(!fm.fileExists(atPath: currentData(box).path) && !fm.fileExists(atPath: legacyData(box).path))
        #expect(Sandbox.inventory(box.home.appendingPathComponent(".claude")) == ["settings.json"])
        #expect(try Data(contentsOf: box.settings) == Self.original)
    }

    @Test("Delete all when the old layout couldn't move (both folders existed): both go, settings restored exactly")
    func deleteAllFromOldLayout() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        try await writeOldDataFolder(box, into: legacyData(box))
        try installOldClaudeLayout(box)
        let claude = box.home.appendingPathComponent(".claude")
        try fm.createDirectory(at: claude.appendingPathComponent("clepso"), withIntermediateDirectories: false)
        try fm.createDirectory(at: currentData(box), withIntermediateDirectories: false)
        let model = AppModel(environment: environment(box, clock: TestClock()))
        await model.start()
        #expect(fm.fileExists(atPath: claude.appendingPathComponent("pulse/install-state.json").path), "kept: both existed")
        let report = await model.deleteAll(includeBackups: true, relaunch: false)
        #expect(report == AppModel.DeleteReport(failure: nil, leftovers: [], backupsRemoved: true))
        #expect(!fm.fileExists(atPath: currentData(box).path) && !fm.fileExists(atPath: legacyData(box).path),
                "left: \(Sandbox.inventory(legacyData(box)))")
        #expect(Sandbox.inventory(claude) == ["settings.json"])
        #expect(try Data(contentsOf: box.settings) == Self.original)
    }

    @Test("Remove from the old layout when it couldn't move: settings.json back to the original bytes")
    func removeFromOldLayout() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        try installOldClaudeLayout(box)
        try fm.createDirectory(at: box.home.appendingPathComponent(".claude/clepso"), withIntermediateDirectories: false)
        let model = AppModel(environment: environment(box, clock: TestClock()))
        await model.start(); defer { model.stop() }
        #expect(await model.uninstall() == .restoredExactly)
        #expect(try Data(contentsOf: box.settings) == Self.original)
        #expect(!fm.fileExists(atPath: box.home.appendingPathComponent(".claude/pulse").path))
    }
}
