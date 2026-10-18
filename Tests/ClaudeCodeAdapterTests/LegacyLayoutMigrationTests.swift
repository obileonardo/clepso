import Darwin
import Foundation
import Testing
@testable import ClaudeCodeAdapter

/// The rename from Pulse to Clepso: an install in `~/.claude/pulse` (+ `pulse-backups`), with settings.json pointing at
/// it, becomes the same install in `~/.claude/clepso`. Every test runs in a throwaway HOME.
@Suite("Old layout (~/.claude/pulse) moves to ~/.claude/clepso", .serialized)
struct LegacyLayoutMigrationTests {
    static let oldStatus = "~/.claude/pulse/statusline.sh"
    static let newStatus = "~/.claude/clepso/statusline.sh"
    static let oldHook = "[ -x ~/.claude/pulse/hook.sh ] && exec ~/.claude/pulse/hook.sh; exit 0"
    static let newHook = "[ -x ~/.claude/clepso/hook.sh ] && exec ~/.claude/clepso/hook.sh; exit 0"

    func legacyStatusLine(_ box: Sandbox) -> SettingsInstaller {
        SettingsInstaller(paths: .legacy(home: box.home), shimPath: "/Applications/Clepso.app/Contents/Helpers/pulse-statusline",
                          socketPath: "/Users/x/Library/Application Support/Pulse/run/agent.sock", forwardCost: true,
                          now: { Sandbox.fixedNow }, beforeSettingsWrite: nil)
    }

    func legacyHooks(_ box: Sandbox) -> HooksInstaller {
        HooksInstaller(paths: .legacy(home: box.home), shimPath: "/Applications/Clepso.app/Contents/Helpers/pulse-statusline",
                       now: { Sandbox.fixedNow }, beforeSettingsWrite: nil)
    }

    func hooks(_ box: Sandbox) -> HooksInstaller {
        HooksInstaller(paths: .init(home: box.home), shimPath: Sandbox.shim, now: { Sandbox.fixedNow }, beforeSettingsWrite: nil)
    }

    func migration(_ box: Sandbox, beforeMove: (@Sendable () -> Void)? = nil, beforeWrite: (@Sendable () -> Void)? = nil) -> LegacyLayoutMigration {
        LegacyLayoutMigration(current: .init(home: box.home), legacy: .legacy(home: box.home), now: { Sandbox.fixedNow.addingTimeInterval(86_400) },
                              beforeFolderMove: beforeMove, beforeSettingsWrite: beforeWrite)
    }

    /// Installs the way the app did before the rename, then makes the generated files read exactly as that app wrote
    /// them (record key, wrapper variable and comment). Returns the settings bytes the old install left.
    @discardableResult
    func installOldLayout(_ box: Sandbox, hooks withHooks: Bool) throws -> [UInt8] {
        _ = try legacyStatusLine(box).install()
        if withHooks { try legacyHooks(box).install() }
        let old = box.claude.appendingPathComponent("pulse")
        for (file, pairs) in [("install-state.json", [("createdByClepso", "createdByPulse")]),
                              ("statusline.sh", [("CLEPSO_SHIM", "PULSE_SHIM"), ("# Clepso", "# Pulse")]),
                              ("hook.sh", [("CLEPSO_SHIM", "PULSE_SHIM"), ("# Clepso", "# Pulse"), ("Clepso regenerates", "Pulse regenerates")])] {
            let url = old.appendingPathComponent(file)
            guard var text = box.bytes(url).map({ String(decoding: $0, as: UTF8.self) }) else { continue }
            for (new, legacy) in pairs { text = text.replacingOccurrences(of: new, with: legacy) }
            try Data(text.utf8).write(to: url)
        }
        let manifest = box.claude.appendingPathComponent("pulse-backups/manifest.jsonl")
        if let text = box.bytes(manifest).map({ String(decoding: $0, as: UTF8.self) }) {
            try Data(text.replacingOccurrences(of: "created_by_clepso", with: "created_by_pulse").utf8).write(to: manifest)
        }
        #expect(box.exists(old.appendingPathComponent("install-state.json")))
        return try settingsBytes(box)
    }

    struct Missing: Error {}
    func settingsBytes(_ box: Sandbox) throws -> [UInt8] {
        guard let bytes = box.bytes(box.settings) else { throw Missing() }
        return bytes
    }

    /// The independent check that only Clepso's command strings changed: putting the old strings back gives the old
    /// file byte for byte.
    func onlyCommandsChanged(old: [UInt8], new: [UInt8]) throws -> Bool {
        var text = String(decoding: new, as: UTF8.self)
        text = text.replacingOccurrences(of: try literal(Self.newStatus), with: try literal(Self.oldStatus))
        text = text.replacingOccurrences(of: try literal(Self.newHook), with: try literal(Self.oldHook))
        return Array(text.utf8) == old
    }

    @Test("Across the settings corpus: status line and hooks move, only Clepso's commands change, Remove restores the original exactly",
          arguments: Sandbox.installable)
    func corpus(file: String) throws {
        let box = try Sandbox(settingsFixture: file); defer { box.cleanUp() }
        let original = try settingsBytes(box)
        let old = try installOldLayout(box, hooks: true)

        #expect(migration(box).run() == .migrated, "\(file)")
        #expect(!box.exists(box.claude.appendingPathComponent("pulse")) && !box.exists(box.claude.appendingPathComponent("pulse-backups")))
        for name in ["statusline.sh", "hook.sh", "config.json", "session.key", "install-state.json", "hooks-state.json"] {
            #expect(box.exists(box.claude.appendingPathComponent("clepso/\(name)")), "\(file): \(name) missing")
        }
        let migrated = try settingsBytes(box)
        #expect(try onlyCommandsChanged(old: old, new: migrated), "\(file): bytes other than Clepso's commands changed")
        let object = try #require(jsonObject(migrated))
        #expect((object["statusLine"] as? [String: Any])?["command"] as? String == Self.newStatus)
        #expect(!String(decoding: migrated, as: UTF8.self).contains("~/.claude/pulse/"), "\(file): old folder still named")
        #expect(box.mode(box.settings) == 0o640, "\(file): mode changed")
        #expect(box.bytes(box.claude.appendingPathComponent("clepso-backups").appendingPathComponent(
            "settings.json.20261017T140000Z.\(sha(old).prefix(12)).pre-rename.bak")) == old, "\(file): no backup of the replaced bytes")

        // Launch repair re-points the generated files at the new helper and socket.
        let statusLine = box.installer()
        #expect(statusLine.needsRepair() && hooks(box).needsRepair())
        try statusLine.repair()
        try hooks(box).repair()
        #expect(!statusLine.needsRepair() && !hooks(box).needsRepair())

        // A second launch finds nothing to do and changes nothing.
        #expect(migration(box).run() == .nothingToDo)
        #expect(box.bytes(box.settings) == migrated)

        #expect(try hooks(box).uninstall() == .restoredExactly, "\(file)")
        #expect(try statusLine.uninstall() == .restoredExactly, "\(file)")
        #expect(box.bytes(box.settings) == original, "\(file): not the original bytes after Remove")
    }

    @Test("Status line only (no hooks): moved, then restored byte for byte")
    func statusLineOnly() throws {
        let box = try Sandbox(settingsFixture: "existing-statusline.json"); defer { box.cleanUp() }
        let original = try settingsBytes(box)
        let old = try installOldLayout(box, hooks: false)
        #expect(migration(box).run() == .migrated)
        #expect(try onlyCommandsChanged(old: old, new: try settingsBytes(box)))
        // The old record (`createdByPulse`) still reads, and its backup path now points into clepso-backups.
        let record = try #require(box.installer().loadRecord())
        #expect(record.backupPath?.contains("/.claude/clepso-backups/") == true && record.state == .verified)
        #expect(try box.installer().uninstall() == .restoredExactly)
        #expect(box.bytes(box.settings) == original)
    }

    @Test("Entries that aren't Clepso's stay byte for byte, even ones that mention the old folder")
    func othersUntouched() throws {
        let box = try Sandbox(); defer { box.cleanUp() }
        let text = """
        {
          "model": "opus",
          "hooks": {
            "Stop": [{"hooks": [{"type": "command", "command": "echo ~/.claude/pulse/hook.sh"}]}],
            "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "\(Self.oldHook)"}]}]
          },
          "note": "~/.claude/pulse/statusline.sh"
        }

        """
        try Data(text.utf8).write(to: box.settings)
        chmod(box.settings.path, 0o640)
        let original = try settingsBytes(box)
        let old = try installOldLayout(box, hooks: true)
        #expect(migration(box).run() == .migrated)
        let migrated = try settingsBytes(box)
        #expect(try onlyCommandsChanged(old: old, new: migrated))
        let object = try #require(jsonObject(migrated))
        let hooks = try #require(object["hooks"] as? [String: Any])
        // Not one of Clepso's events: left as the user wrote it.
        let pre = try #require(((hooks["PreToolUse"] as? [Any])?.first as? [String: Any])?["hooks"] as? [Any])
        #expect((pre.first as? [String: Any])?["command"] as? String == Self.oldHook)
        #expect(object["note"] as? String == Self.oldStatus)
        let stop = try #require(hooks["Stop"] as? [Any])
        #expect(((stop.first as? [String: Any])?["hooks"] as? [[String: Any]])?.first?["command"] as? String == "echo ~/.claude/pulse/hook.sh")
        #expect(try self.hooks(box).uninstall() == .restoredExactly)
        #expect(try box.installer().uninstall() == .restoredExactly)
        #expect(box.bytes(box.settings) == original)
    }

    @Test("Both ~/.claude/pulse and ~/.claude/clepso exist: neither is touched")
    func keptBoth() throws {
        let box = try Sandbox(settingsFixture: "existing-statusline.json"); defer { box.cleanUp() }
        let old = try installOldLayout(box, hooks: true)
        try FileManager.default.createDirectory(at: box.claude.appendingPathComponent("clepso"), withIntermediateDirectories: false)
        try Data("mine".utf8).write(to: box.claude.appendingPathComponent("clepso/note"))
        let before = Sandbox.inventoryOf(box.claude)
        #expect(migration(box).run() == .keptBoth)
        #expect(Sandbox.inventoryOf(box.claude) == before)
        #expect(box.bytes(box.settings) == old)
    }

    @Test("settings.json names the old folder but can't be edited safely: nothing moves")
    func unreadableSettings() throws {
        let box = try Sandbox(settingsFixture: "existing-statusline.json"); defer { box.cleanUp() }
        let old = try installOldLayout(box, hooks: false)
        // Foundation still reads it (and finds the old command), the byte scanner refuses it: a trailing comma.
        var broken = String(decoding: old, as: UTF8.self)
        broken = broken.replacingOccurrences(of: "\n}", with: ",\n}", options: .backwards, range: broken.range(of: "\n}", options: .backwards))
        try Data(broken.utf8).write(to: box.settings)
        #expect(migration(box).run() == .settingsUnreadable)
        #expect(box.exists(box.claude.appendingPathComponent("pulse/statusline.sh")))
        #expect(!box.exists(box.claude.appendingPathComponent("clepso")))
        #expect(box.bytes(box.settings) == Array(broken.utf8))

        // A symlinked settings.json is refused the same way.
        let real = box.home.appendingPathComponent("real-settings.json")
        try FileManager.default.moveItem(at: box.settings, to: real)
        try Data(old).write(to: real)
        try FileManager.default.createSymbolicLink(at: box.settings, withDestinationURL: real)
        #expect(migration(box).run() == .settingsUnreadable)
        #expect(box.exists(box.claude.appendingPathComponent("pulse")) && !box.exists(box.claude.appendingPathComponent("clepso")))
    }

    @Test("Interrupted after the folder moved (settings.json and backups not yet): the next launch finishes, exact restore")
    func resumeAfterFolderMove() throws {
        let box = try Sandbox(settingsFixture: "tabs.json"); defer { box.cleanUp() }
        let original = try settingsBytes(box)
        let old = try installOldLayout(box, hooks: true)
        // What a crash right after rename(2) leaves: the folder is new, everything else is as before.
        #expect(rename(box.claude.appendingPathComponent("pulse").path, box.claude.appendingPathComponent("clepso").path) == 0)
        #expect(box.bytes(box.settings) == old)
        #expect(migration(box).run() == .migrated)
        #expect(!box.exists(box.claude.appendingPathComponent("pulse-backups")))
        #expect(try onlyCommandsChanged(old: old, new: try settingsBytes(box)))
        #expect(try hooks(box).uninstall() == .restoredExactly)
        #expect(try box.installer().uninstall() == .restoredExactly)
        #expect(box.bytes(box.settings) == original)
    }

    @Test("Interrupted after the records were updated, before settings.json was written: the next launch finishes, exact restore")
    func resumeAfterRecords() throws {
        let box = try Sandbox(settingsFixture: "existing-statusline.json"); defer { box.cleanUp() }
        let original = try settingsBytes(box)
        let old = try installOldLayout(box, hooks: true)
        // The compare-and-swap sees a change and stops after the records were saved; putting the bytes back leaves
        // exactly what a crash at that point leaves.
        let settings = box.settings
        let outcome = migration(box, beforeWrite: { try? Data("{}".utf8).write(to: settings) }).attempt()
        #expect(outcome == .settingsChanged)
        try Data(old).write(to: box.settings)
        #expect(migration(box).run() == .migrated)
        #expect(migration(box).run() == .nothingToDo)
        #expect(try onlyCommandsChanged(old: old, new: try settingsBytes(box)))
        #expect(try hooks(box).uninstall() == .restoredExactly)
        #expect(try box.installer().uninstall() == .restoredExactly)
        #expect(box.bytes(box.settings) == original)
    }

    @Test("The user edits settings.json between launches: the edit stays, Remove takes out only Clepso's entries")
    func userEditBetween() throws {
        let box = try Sandbox(settingsFixture: "existing-statusline.json"); defer { box.cleanUp() }
        let old = try installOldLayout(box, hooks: true)
        let settings = box.settings
        #expect(migration(box, beforeWrite: {
            var text = String(decoding: (try? Data(contentsOf: settings)) ?? Data(), as: UTF8.self)
            text = text.replacingOccurrences(of: "{", with: "{\n  \"theme\": \"dark\",", options: [], range: text.range(of: "{"))
            try? Data(text.utf8).write(to: settings)
        }).attempt() == .settingsChanged)
        let edited = try settingsBytes(box)
        #expect(edited != old)
        #expect(migration(box).run() == .migrated)
        #expect(try onlyCommandsChanged(old: edited, new: try settingsBytes(box)))
        #expect(try hooks(box).uninstall() == .removedEntries(formattingChanged: false))
        guard case .restoredStatusLineOnly = try box.installer().uninstall() else { Issue.record("status line not restored"); return }
        let object = try #require(jsonObject(try settingsBytes(box)))
        #expect(object["theme"] as? String == "dark")
        #expect((object["statusLine"] as? [String: Any])?["command"] as? String != Self.newStatus)
        #expect(!String(decoding: try settingsBytes(box), as: UTF8.self).contains(".claude/clepso"))
    }

    @Test("Claude Code writes settings.json during the move: the same launch tries again and keeps that write")
    func raceRetried() throws {
        let box = try Sandbox(settingsFixture: "existing-statusline.json"); defer { box.cleanUp() }
        let old = try installOldLayout(box, hooks: true)
        let settings = box.settings
        let once = OnceFlag()
        #expect(migration(box, beforeWrite: {
            guard once.first() else { return }
            var text = String(decoding: (try? Data(contentsOf: settings)) ?? Data(), as: UTF8.self)
            text = text.replacingOccurrences(of: "{", with: "{\n  \"theme\": \"dark\",", options: [], range: text.range(of: "{"))
            try? Data(text.utf8).write(to: settings)
        }).run() == .migrated)
        let migrated = try settingsBytes(box)
        #expect(jsonObject(migrated)?["theme"] as? String == "dark")
        #expect(!String(decoding: migrated, as: UTF8.self).contains("~/.claude/pulse/"))
        #expect(migrated != old)
    }

    @Test("Backups merge into an existing clepso-backups without overwriting a file")
    func backupsMerge() throws {
        let box = try Sandbox(settingsFixture: "existing-statusline.json"); defer { box.cleanUp() }
        try installOldLayout(box, hooks: false)
        let newBackups = box.claude.appendingPathComponent("clepso-backups")
        try FileManager.default.createDirectory(at: newBackups, withIntermediateDirectories: false)
        try Data("newer".utf8).write(to: newBackups.appendingPathComponent("manifest.jsonl"))
        let oldManifest = try #require(box.bytes(box.claude.appendingPathComponent("pulse-backups/manifest.jsonl")))
        #expect(migration(box).run() == .migrated)
        #expect(box.bytes(newBackups.appendingPathComponent("manifest.jsonl")) == Array("newer".utf8))
        #expect(box.bytes(box.claude.appendingPathComponent("pulse-backups/manifest.jsonl")) == oldManifest, "kept where it was")
        let record = try #require(box.installer().loadRecord())
        #expect(record.backupPath?.hasPrefix(newBackups.path + "/") == true)
        #expect(record.backupPath.flatMap { box.bytes(URL(fileURLWithPath: $0)) } != nil)
    }

    @Test("No old layout: nothing happens, settings.json isn't even rewritten")
    func nothingToDo() throws {
        let box = try Sandbox(settingsFixture: "existing-statusline.json"); defer { box.cleanUp() }
        _ = try box.installer().install()
        let installed = try settingsBytes(box)
        #expect(migration(box).run() == .nothingToDo)
        #expect(box.bytes(box.settings) == installed)
    }
}

extension Sandbox {
    /// Every path under `url` with its bytes' hash: the before/after evidence that nothing changed.
    static func inventoryOf(_ url: URL) -> [String: String] {
        var result: [String: String] = [:]
        let walker = FileManager.default.enumerator(atPath: url.path)
        while let path = walker?.nextObject() as? String {
            let data = (try? Data(contentsOf: url.appendingPathComponent(path))).map { sha(Array($0)) } ?? "dir"
            result[path] = data
        }
        return result
    }
}

/// True the first time only.
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func first() -> Bool { lock.withLock { defer { used = true }; return !used } }
}
