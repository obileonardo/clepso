import Darwin
import Foundation

/// The rename from Pulse to Clepso moved the app's folders inside Claude Code's settings folder,
/// `~/.claude/pulse` → `~/.claude/clepso` and `~/.claude/pulse-backups` → `~/.claude/clepso-backups`, and with them the
/// commands settings.json runs: `statusLine.command` and the four agents-per-task hook entries.
///
/// `run()` is called at every launch, before anything reads the install. Each step is idempotent and safe to repeat, so
/// a launch that was interrupted (crash, power loss) is finished by the next one:
///
/// 1. Folders: `rename(2)` within `~/.claude`, so each folder moves whole or not at all. When both the old and the new
///    folder exist nothing is touched (`keptBoth`). When settings.json names the old folder but can't be edited safely,
///    nothing moves either (`settingsUnreadable`): Claude Code must never be left calling a script that isn't there.
///    Backups go file by file into an existing `clepso-backups`, never over a file of the same name.
/// 2. Install records: backup paths re-pointed to the moved files.
/// 3. settings.json, only when it still names the old folder: the old command strings, and nothing else, are replaced
///    in place (every other byte stays), the same discipline as an install: the records are updated first, the current
///    bytes are backed up, then compare-and-swap and an atomic rename, then read back. The records' hashes move with
///    the bytes they describe, so Remove still restores the user's original file byte for byte.
///
/// The wrapper scripts and config inside the folder still name the old helper and socket; the app's launch repair
/// (`SettingsInstaller.repair()`, `HooksInstaller.repair()`) regenerates them right after.
public struct LegacyLayoutMigration: Sendable {
    public enum Outcome: String, Sendable, Equatable {
        case nothingToDo            // no old layout left
        case migrated               // folders moved and/or settings.json and the records updated
        case keptBoth               // `~/.claude/pulse` and `~/.claude/clepso` both exist: neither was touched
        case settingsUnreadable     // settings.json names the old folder but can't be edited safely: nothing was moved
        case settingsChanged        // settings.json changed while it was being rewritten; the next launch tries again
        case failed                 // a file operation failed; the next launch tries again
    }

    enum Failure: Error { case unreadable, changed, io }

    public let current: SettingsInstaller.Paths
    public let legacy: SettingsInstaller.Paths
    let now: @Sendable () -> Date
    /// Test hooks: run just before the folder moves, and between reading settings.json and the compare-and-swap write.
    let beforeFolderMove: (@Sendable () -> Void)?
    let beforeSettingsWrite: (@Sendable () -> Void)?

    public init(home: URL, claudeConfigDir: URL? = nil, now: @escaping @Sendable () -> Date) {
        self.init(current: .init(home: home, claudeConfigDir: claudeConfigDir), legacy: .legacy(home: home, claudeConfigDir: claudeConfigDir),
                  now: now, beforeFolderMove: nil, beforeSettingsWrite: nil)
    }

    init(current: SettingsInstaller.Paths, legacy: SettingsInstaller.Paths, now: @escaping @Sendable () -> Date,
         beforeFolderMove: (@Sendable () -> Void)?, beforeSettingsWrite: (@Sendable () -> Void)?) {
        self.current = current
        self.legacy = legacy
        self.now = now
        self.beforeFolderMove = beforeFolderMove
        self.beforeSettingsWrite = beforeSettingsWrite
    }

    /// True when anything of the old layout is still on disk (a folder the migration left, for whatever reason).
    public var legacyLayoutPresent: Bool {
        FileOps.isRealDirectory(legacy.clepsoDir) || FileOps.isRealDirectory(legacy.backupsDir)
    }

    public func run() -> Outcome {
        do {
            return try migrate()
        } catch Failure.unreadable {
            return .settingsUnreadable
        } catch Failure.changed {
            return .settingsChanged
        } catch {
            return .failed
        }
    }

    func migrate() throws -> Outcome {
        var changed = false
        if FileOps.isRealDirectory(legacy.clepsoDir) {
            if Self.exists(current.clepsoDir) { return .keptBoth }
            // Checked before the move: once the folder has moved, settings.json must be able to follow it.
            if let settings = try readSettings(), references(settings.bytes), rewrite(settings.bytes) == nil {
                return .settingsUnreadable
            }
            beforeFolderMove?()
            guard rename(legacy.clepsoDir.path, current.clepsoDir.path) == 0 else { throw Failure.io }
            Self.syncDirectory(current.claudeDir)
            changed = true
        }
        if FileOps.isRealDirectory(legacy.backupsDir) {
            try moveBackups()
            changed = true
        }
        // From here on, everything is keyed on what the current folder holds, so a launch that stopped after the move
        // (or after updating the records) picks up here.
        guard FileOps.readBytes(current.record) != nil else { return changed ? .migrated : .nothingToDo }
        if try repointRecords() { changed = true }
        if try rewriteSettings() { changed = true }
        return changed ? .migrated : .nothingToDo
    }

    // MARK: - Folders

    /// The whole folder in one rename when there is no `clepso-backups` yet; otherwise each file that isn't already
    /// there. The old folder goes once empty; anything left (a name both folders have) stays where it was.
    func moveBackups() throws {
        if !Self.exists(current.backupsDir) {
            guard rename(legacy.backupsDir.path, current.backupsDir.path) == 0 else { throw Failure.io }
            Self.syncDirectory(current.claudeDir)
            return
        }
        guard FileOps.isRealDirectory(current.backupsDir) else { throw Failure.io }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: legacy.backupsDir.path)) ?? []
        for name in names.sorted() {
            let target = current.backupsDir.appendingPathComponent(name)
            guard !Self.exists(target) else { continue }
            guard rename(legacy.backupsDir.appendingPathComponent(name).path, target.path) == 0 else { throw Failure.io }
        }
        Self.syncDirectory(current.backupsDir)
        rmdir(legacy.backupsDir.path)                     // only succeeds when empty
    }

    // MARK: - Install records

    var statusLine: SettingsInstaller { SettingsInstaller(paths: current, shimPath: "", socketPath: "", forwardCost: true, now: now, beforeSettingsWrite: nil) }
    var hooks: HooksInstaller { HooksInstaller(paths: current, shimPath: "", now: now, beforeSettingsWrite: nil) }
    var legacyHooks: HooksInstaller { HooksInstaller(paths: legacy, shimPath: "", now: now, beforeSettingsWrite: nil) }

    /// A backup path inside the old backups folder, re-pointed to the same file in the new one once it is there.
    func repointed(_ path: String?) -> String? {
        let prefix = legacy.backupsDir.path + "/"
        guard let path, path.hasPrefix(prefix) else { return nil }
        let moved = current.backupsDir.appendingPathComponent(String(path.dropFirst(prefix.count)))
        return FileOps.readBytes(moved) != nil ? moved.path : nil
    }

    func repointRecords() throws -> Bool {
        var changed = false
        if var record = statusLine.loadRecord(), let moved = repointed(record.backupPath) {
            record.backupPath = moved
            try save { try statusLine.save(record) }
            changed = true
        }
        if var record = hooks.loadRecord(), let moved = repointed(record.backupPath) {
            record.backupPath = moved
            try save { try hooks.save(record) }
            changed = true
        }
        return changed
    }

    // MARK: - settings.json

    /// Reads settings.json without following a symlink. nil when there is none; throws when it exists but can't be read
    /// safely (a symlink, not a regular file), which the installer would have refused too.
    func readSettings() throws -> FileOps.Contents? {
        do {
            return try FileOps.readNoFollow(current.settings)
        } catch {
            throw Failure.unreadable
        }
    }

    func rewriteSettings() throws -> Bool {
        guard let settings = try readSettings(), references(settings.bytes) else { return false }
        guard let renamed = rewrite(settings.bytes) else { throw Failure.unreadable }
        let before = FileOps.sha256(settings.bytes), after = FileOps.sha256(renamed)
        let stamp = FileOps.basicISO8601(now())
        try save { try FileOps.ensureRealDirectory(current.backupsDir, mode: 0o700) }

        // The records first: a launch that stops after this finds settings.json unchanged and does it again, and the
        // mapping below leaves an already updated record as it is.
        var hashes = [before: after]
        var hooksRecord = hooks.loadRecord()
        if var record = hooksRecord, let backup = FileOps.readBytes(URL(fileURLWithPath: record.backupPath)),
           FileOps.sha256(backup) == record.h0, references(backup) {
            // The bytes from before the hooks went in carry the status line, which names the old folder too.
            guard let renamedBackup = rewrite(backup) else { throw Failure.unreadable }
            let hash = FileOps.sha256(renamedBackup)
            let url = current.backupsDir.appendingPathComponent("settings.json.\(stamp).\(hash.prefix(12)).pre-hooks.bak")
            try writeBackup(url, renamedBackup)
            hashes[record.h0] = hash
            record.h0 = hash
            record.backupPath = url.path
            hooksRecord = record
        }
        if var record = hooksRecord {
            if record.h1 == before { record.h1 = after }   // settings.json as the hooks left it
            try save { try hooks.save(record) }
        }
        if var record = statusLine.loadRecord(), let h1 = record.h1, let mapped = hashes[h1] {
            record.h1 = mapped
            try save { try statusLine.save(record) }
        }

        // Then settings.json itself: backup, compare-and-swap, atomic rename, read back.
        try writeBackup(current.backupsDir.appendingPathComponent("settings.json.\(stamp).\(before.prefix(12)).pre-rename.bak"), settings.bytes)
        beforeSettingsWrite?()
        guard (try? FileOps.readNoFollow(current.settings)).flatMap({ $0 }).map({ FileOps.sha256($0.bytes) }) == before else {
            throw Failure.changed
        }
        try save { try FileOps.atomicReplace(current.settings, with: renamed, mode: settings.mode) }
        guard FileOps.readBytes(current.settings).map(FileOps.sha256) == after else { throw Failure.io }
        return true
    }

    /// Exclusive create; a file of the same name with the same bytes (a repeated launch within the same second) is fine.
    func writeBackup(_ url: URL, _ bytes: [UInt8]) throws {
        if let existing = FileOps.readBytes(url) {
            guard existing == bytes else { throw Failure.io }
            return
        }
        try save { try FileOps.writeExclusive(url, bytes: bytes, mode: 0o600) }
    }

    func save(_ body: () throws -> Void) throws {
        do { try body() } catch { throw Failure.io }
    }

    /// Whether the settings still run anything from the old folder: the status line or one of the hook entries.
    func references(_ bytes: [UInt8]) -> Bool {
        guard let object = FileOps.jsonObject(bytes) else { return false }
        return !NSDictionary(dictionary: object).isEqual(to: renamed(object))
    }

    /// The parsed settings with the old commands replaced, for checking the byte edit against.
    func renamed(_ object: [String: Any]) -> [String: Any] {
        var object = object
        if var statusLine = object["statusLine"] as? [String: Any], statusLine["command"] as? String == legacy.commandValue {
            statusLine["command"] = current.commandValue
            object["statusLine"] = statusLine
        }
        guard var hookEvents = object["hooks"] as? [String: Any] else { return object }
        let old = legacyHooks.commandValue, new = hooks.commandValue
        for event in HooksInstaller.events {
            guard let entries = hookEvents[event] as? [Any] else { continue }
            hookEvents[event] = entries.map { entry -> Any in
                guard var entry = entry as? [String: Any], let handlers = entry["hooks"] as? [Any] else { return entry }
                entry["hooks"] = handlers.map { handler -> Any in
                    guard var handler = handler as? [String: Any], handler["command"] as? String == old else { return handler }
                    handler["command"] = new
                    return handler
                }
                return entry
            }
        }
        object["hooks"] = hookEvents
        return object
    }

    /// settings.json with each old command string replaced in place: `statusLine.command` and the `command` of hook
    /// handlers under Clepso's four events. Every other byte is the original's. nil when the file can't be edited this
    /// way or the result doesn't check out (then nothing is written).
    func rewrite(_ bytes: [UInt8]) -> [UInt8]? {
        guard let layout = JSONObjectLayout.parseDocument(bytes), let object = FileOps.jsonObject(bytes) else { return nil }
        var edits: [(range: Range<Int>, value: [UInt8])] = []
        func replace(in container: JSONObjectLayout, _ old: String, with new: String) {
            for member in container.members(named: "command") where Self.string(bytes, member.valueStart..<member.valueEnd) == old {
                edits.append((member.valueStart..<member.valueEnd, Array(JSONObjectLayout.quoted(new).utf8)))
            }
        }
        let statusLines = layout.members(named: "statusLine"), hookSections = layout.members(named: "hooks")
        guard statusLines.count <= 1, hookSections.count <= 1 else { return nil }
        if let member = statusLines.first {
            var i = member.valueStart
            if let inner = JSONObjectLayout.parseObject(bytes, at: &i) { replace(in: inner, legacy.commandValue, with: current.commandValue) }
        }
        if let member = hookSections.first {
            var i = member.valueStart
            if let events = JSONObjectLayout.parseObject(bytes, at: &i) {
                for event in HooksInstaller.events {
                    for eventMember in events.members(named: event) {
                        var j = eventMember.valueStart
                        guard let entries = JSONArrayLayout.parse(bytes, at: &j) else { continue }
                        for element in entries.elements {
                            var k = element.start
                            guard let entry = JSONObjectLayout.parseObject(bytes, at: &k) else { continue }
                            for handlersMember in entry.members(named: "hooks") {
                                var m = handlersMember.valueStart
                                guard let handlers = JSONArrayLayout.parse(bytes, at: &m) else { continue }
                                for handler in handlers.elements {
                                    var n = handler.start
                                    guard let fields = JSONObjectLayout.parseObject(bytes, at: &n) else { continue }
                                    replace(in: fields, legacyHooks.commandValue, with: hooks.commandValue)
                                }
                            }
                        }
                    }
                }
            }
        }
        var result = bytes
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            result.replaceSubrange(edit.range, with: edit.value)
        }
        // Checked from the outside: the result parses, equals the original with only the old commands replaced, and
        // names the old folder nowhere Clepso writes.
        guard let after = FileOps.jsonObject(result), JSONObjectLayout.parseDocument(result) != nil,
              NSDictionary(dictionary: after).isEqual(to: renamed(object)), !references(result) else { return nil }
        return result
    }

    static func string(_ bytes: [UInt8], _ range: Range<Int>) -> String? {
        guard range.lowerBound < bytes.count, bytes[range.lowerBound] == UInt8(ascii: "\"") else { return nil }
        return try? JSONDecoder().decode(String.self, from: Data(bytes[range]))
    }

    static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    static func syncDirectory(_ url: URL) {
        let fd = open(url.path, O_RDONLY)
        if fd >= 0 { fsync(fd); close(fd) }
    }
}
