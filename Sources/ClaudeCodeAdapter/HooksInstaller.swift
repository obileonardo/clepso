import Darwin
import Domain
import Foundation

/// Agents per task (increment 1.9): adds four entries to `hooks` in Claude Code's settings.json and takes them
/// out again, with the guarantees of `SettingsInstaller` (backup first, compare-and-swap, verify, exact restore).
///
/// Each entry runs `~/.claude/clepso/hook.sh` in the background (`async`), which execs the signed helper in hook
/// mode. The command itself checks the script is there and always ends `exit 0`, so a removed app can never make
/// a hook fail or block Claude Code. Hooks the user already has are left as they are: Clepso's entry is appended to
/// an event's list, and only that entry is removed later. Requires the status-line connection (its config,
/// socket and session key).
public struct HooksInstaller: Sendable {
    public enum InstallError: Error, Equatable {
        case connectionNotInstalled
        case alreadyInstalled
        case settingsInvalidJSON
        case unsupportedExistingHooks
        case settingsChangedDuringInstall
        case verificationFailed
        case io(String)
    }

    public enum UninstallOutcome: Sendable, Equatable {
        case notInstalled
        case restoredExactly                         // settings.json is byte-identical to before the hooks were added
        case removedEntries(formattingChanged: Bool) // the user edited settings since; only Clepso's entries were taken out
        case entriesAlreadyGone                      // nothing of Clepso's was left in settings.json
    }

    public let paths: SettingsInstaller.Paths
    public let shimPath: String
    let now: @Sendable () -> Date
    let beforeSettingsWrite: (@Sendable () -> Void)?

    public init(paths: SettingsInstaller.Paths, shimPath: String, now: @escaping @Sendable () -> Date = { SystemClock().now() }) {
        self.init(paths: paths, shimPath: shimPath, now: now, beforeSettingsWrite: nil)
    }

    init(paths: SettingsInstaller.Paths, shimPath: String, now: @escaping @Sendable () -> Date, beforeSettingsWrite: (@Sendable () -> Void)?) {
        self.paths = paths
        self.shimPath = shimPath
        self.now = now
        self.beforeSettingsWrite = beforeSettingsWrite
    }

    public static let events = ["UserPromptSubmit", "SubagentStart", "SubagentStop", "Stop"]

    var script: URL { paths.clepsoDir.appendingPathComponent("hook.sh") }
    var recordURL: URL { paths.clepsoDir.appendingPathComponent("hooks-state.json") }

    /// The shell command in each entry. `~` is expanded by the shell, so it is left unquoted (the path has no spaces);
    /// a custom config folder is quoted instead.
    public var commandValue: String {
        let path = paths.commandValue.hasPrefix("~/") ? "~/.claude/\(paths.folderName)/hook.sh"
            : SettingsInstaller.singleQuoted(paths.clepsoDir.appendingPathComponent("hook.sh").path)
        return "[ -x \(path) ] && exec \(path); exit 0"
    }

    /// One entry, as written: no matcher (every agent type), in the background, ten seconds at most.
    var entryBytes: [UInt8] {
        Array("{\"hooks\": [{\"type\": \"command\", \"command\": \(JSONObjectLayout.quoted(commandValue)), \"async\": true, \"timeout\": 10}]}".utf8)
    }
    var entryObject: [String: Any] { FileOps.jsonObject(entryBytes) ?? [:] }

    public var isInstalled: Bool { loadRecord() != nil }

    // MARK: - Record

    struct Record: Codable {
        var h0: String              // settings.json before the hooks
        var h1: String              // settings.json with them
        var backupPath: String
        var createdHooksKey: Bool
        var createdEvents: [String]
        var originalMode: UInt16
    }

    func loadRecord() -> Record? {
        guard let bytes = FileOps.readBytes(recordURL) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: Data(bytes))
    }

    func save(_ record: Record) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileOps.atomicReplace(recordURL, with: Array(try encoder.encode(record)), mode: 0o600)
    }

    // MARK: - Install

    /// What the consent sheet shows before any write: the file and the exact entry added under each event.
    public var previewEntry: String { String(decoding: entryBytes, as: UTF8.self) }

    public func install() throws {
        guard FileOps.readBytes(paths.record).flatMap(FileOps.jsonObject)?["state"] as? String == "verified" else {
            throw InstallError.connectionNotInstalled
        }
        guard !isInstalled else { throw InstallError.alreadyInstalled }
        guard let original = try FileOps.readNoFollow(paths.settings), let originalObject = FileOps.jsonObject(original.bytes),
              JSONObjectLayout.parseDocument(original.bytes) != nil else { throw InstallError.settingsInvalidJSON }
        try Self.validateHooks(original.bytes, object: originalObject)

        // Backup and the hook script before settings.json is touched.
        let h0 = FileOps.sha256(original.bytes)
        try FileOps.ensureRealDirectory(paths.backupsDir, mode: 0o700)
        let backup = paths.backupsDir.appendingPathComponent("settings.json.\(FileOps.basicISO8601(now())).\(h0.prefix(12)).pre-hooks.bak")
        try FileOps.writeExclusive(backup, bytes: original.bytes, mode: 0o600)
        try writeScript()

        let hooks = originalObject["hooks"] as? [String: Any]
        let created = Self.events.filter { hooks?[$0] == nil }
        let newBytes = try compose(original.bytes)

        beforeSettingsWrite?()
        guard try FileOps.readNoFollow(paths.settings).map({ FileOps.sha256($0.bytes) }) == h0 else {
            try? FileManager.default.removeItem(at: script)
            throw InstallError.settingsChangedDuringInstall
        }
        try FileOps.atomicReplace(paths.settings, with: newBytes, mode: original.mode)
        guard verifyInstalled(originalObject: originalObject) else {
            try FileOps.atomicReplace(paths.settings, with: original.bytes, mode: original.mode)
            try? FileManager.default.removeItem(at: script)
            throw InstallError.verificationFailed
        }
        try save(Record(h0: h0, h1: FileOps.sha256(newBytes), backupPath: backup.path, createdHooksKey: hooks == nil,
                        createdEvents: created, originalMode: original.mode))
    }

    /// `hooks` must be absent or one object, and each of our events absent or an array the scanner can edit.
    static func validateHooks(_ bytes: [UInt8], object: [String: Any]) throws {
        guard let value = object["hooks"] else { return }
        guard let hooks = value as? [String: Any], let layout = JSONObjectLayout.parseDocument(bytes),
              layout.members(named: "hooks").count == 1, let member = layout.members(named: "hooks").first else {
            throw InstallError.unsupportedExistingHooks
        }
        var i = member.valueStart
        guard let inner = JSONObjectLayout.parseObject(bytes, at: &i) else { throw InstallError.unsupportedExistingHooks }
        for event in events where hooks[event] != nil {
            guard hooks[event] is [Any], inner.members(named: event).count == 1, let eventMember = inner.members(named: event).first else {
                throw InstallError.unsupportedExistingHooks
            }
            var j = eventMember.valueStart
            guard JSONArrayLayout.parse(bytes, at: &j) != nil else { throw InstallError.unsupportedExistingHooks }
        }
    }

    /// Settings bytes with Clepso's entry added under each event. Every other byte is the original's.
    func compose(_ original: [UInt8]) throws -> [UInt8] {
        var bytes = original
        guard let document = JSONObjectLayout.parseDocument(bytes) else { throw InstallError.settingsInvalidJSON }
        let newline = document.newline
        guard !document.members(named: "hooks").isEmpty else {
            // No hooks yet: one new member holding all four events, indented like the file.
            let indent = document.memberIndent
            let lines = Self.events.map { "\(JSONObjectLayout.quoted($0)): [" + String(decoding: entryBytes, as: UTF8.self) + "]" }
            let value = indent.map { "{\(newline)\($0)\($0)" + lines.joined(separator: ",\(newline)\($0)\($0)") + "\(newline)\($0)}" }
                ?? "{" + lines.joined(separator: ", ") + "}"
            return document.appendingMember(key: "hooks", value: Array(value.utf8))
        }
        for event in Self.events {
            guard let layout = JSONObjectLayout.parseDocument(bytes), let member = layout.members(named: "hooks").first else {
                throw InstallError.unsupportedExistingHooks
            }
            var i = member.valueStart
            guard let hooks = JSONObjectLayout.parseObject(bytes, at: &i) else { throw InstallError.unsupportedExistingHooks }
            if let eventMember = hooks.members(named: event).first {
                var j = eventMember.valueStart
                guard let array = JSONArrayLayout.parse(bytes, at: &j) else { throw InstallError.unsupportedExistingHooks }
                bytes = array.appendingElement(entryBytes, newline: newline)
            } else {
                bytes = hooks.appendingMember(key: event, value: Array("[".utf8) + entryBytes + Array("]".utf8))
            }
        }
        return bytes
    }

    /// Every key but `hooks` unchanged; under `hooks`, each of our events is the original list plus our entry, and
    /// every other event is unchanged.
    func verifyInstalled(originalObject: [String: Any]) -> Bool {
        guard let written = try? FileOps.readNoFollow(paths.settings), let object = FileOps.jsonObject(written.bytes),
              let hooks = object["hooks"] as? [String: Any] else { return false }
        guard Set(object.keys) == Set(originalObject.keys).union(["hooks"]) else { return false }
        for (key, value) in originalObject where key != "hooks" {
            guard let other = object[key], (value as AnyObject).isEqual(other) else { return false }
        }
        let before = originalObject["hooks"] as? [String: Any] ?? [:]
        guard Set(hooks.keys) == Set(before.keys).union(Self.events) else { return false }
        for (event, value) in hooks {
            let expected: [Any] = Self.events.contains(event) ? ((before[event] as? [Any]) ?? []) + [entryObject] : (before[event] as? [Any] ?? [])
            guard (value as AnyObject).isEqual(expected) else { return false }
        }
        return true
    }

    // MARK: - Uninstall

    public func uninstall() throws -> UninstallOutcome {
        guard let record = loadRecord() else { return .notInstalled }
        let current = try FileOps.readNoFollow(paths.settings)
        let hc = current.map { FileOps.sha256($0.bytes) }

        if hc == record.h1 {
            guard let bytes = try FileOps.readNoFollow(URL(fileURLWithPath: record.backupPath))?.bytes, FileOps.sha256(bytes) == record.h0 else {
                throw InstallError.io("backup missing or altered")
            }
            try FileOps.atomicReplace(paths.settings, with: bytes, mode: record.originalMode)
            guard try FileOps.readNoFollow(paths.settings).map({ FileOps.sha256($0.bytes) }) == record.h0 else { throw InstallError.verificationFailed }
            removeFiles()
            return .restoredExactly
        }

        guard let current, let object = FileOps.jsonObject(current.bytes) else {
            removeFiles()
            return .entriesAlreadyGone
        }
        guard let (newBytes, formattingChanged) = removingEntries(current.bytes, object: object, record: record) else {
            removeFiles()
            return .entriesAlreadyGone
        }
        guard try FileOps.readNoFollow(paths.settings).map({ FileOps.sha256($0.bytes) }) == hc else {
            throw InstallError.settingsChangedDuringInstall
        }
        try FileOps.atomicReplace(paths.settings, with: newBytes, mode: current.mode)
        guard let after = FileOps.jsonObject(newBytes), !containsEntry(after),
              Set(after.keys.filter { $0 != "hooks" }) == Set(object.keys.filter { $0 != "hooks" }) else {
            throw InstallError.verificationFailed
        }
        removeFiles()
        return .removedEntries(formattingChanged: formattingChanged)
    }

    func isOurs(_ element: Any) -> Bool {
        ((element as? [String: Any])?["hooks"] as? [Any])?.contains { ($0 as? [String: Any])?["command"] as? String == commandValue } ?? false
    }

    func containsEntry(_ object: [String: Any]) -> Bool {
        guard let hooks = object["hooks"] as? [String: Any] else { return false }
        return Self.events.contains { (hooks[$0] as? [Any])?.contains(where: isOurs) ?? false }
    }

    /// Settings without Clepso's entries, editing bytes in place when the scanner can, else reformatting (and saying
    /// so). Events and the `hooks` key Clepso created go too once empty. Nil when no entry of ours is left.
    func removingEntries(_ original: [UInt8], object: [String: Any], record: Record) -> ([UInt8], Bool)? {
        guard containsEntry(object) else { return nil }
        var bytes = original
        var inPlace = true
        edit: for event in Self.events {
            while true {
                guard let layout = JSONObjectLayout.parseDocument(bytes), layout.members(named: "hooks").count == 1,
                      let member = layout.members(named: "hooks").first else { inPlace = false; break edit }
                var i = member.valueStart
                guard let hooks = JSONObjectLayout.parseObject(bytes, at: &i) else { inPlace = false; break edit }
                guard let eventMember = hooks.members(named: event).first else { break }
                var j = eventMember.valueStart
                guard let array = JSONArrayLayout.parse(bytes, at: &j) else { inPlace = false; break edit }
                if let position = array.elements.firstIndex(where: { element in
                    (try? JSONSerialization.jsonObject(with: Data(bytes[element.start..<element.end]))).map(isOurs) ?? false
                }) {
                    bytes = array.removingElement(at: position)
                    continue
                }
                if array.elements.isEmpty, record.createdEvents.contains(event) {
                    bytes = hooks.removingMember(eventMember)
                }
                break
            }
        }
        if inPlace, let layout = JSONObjectLayout.parseDocument(bytes), let member = layout.members(named: "hooks").first,
           record.createdHooksKey, (FileOps.jsonObject(bytes)?["hooks"] as? [String: Any])?.isEmpty == true {
            bytes = layout.removingMember(member)
        }
        if inPlace, let after = FileOps.jsonObject(bytes), !containsEntry(after) { return (bytes, false) }

        // Fallback: rebuild from the parsed object.
        var updated = object
        var hooks = object["hooks"] as? [String: Any] ?? [:]
        for event in Self.events {
            guard let list = hooks[event] as? [Any] else { continue }
            let kept = list.filter { !isOurs($0) }
            hooks[event] = kept.isEmpty && record.createdEvents.contains(event) ? nil : kept
        }
        updated["hooks"] = hooks.isEmpty && record.createdHooksKey ? nil : hooks
        return (FileOps.serialize(updated, pretty: true) + Array("\n".utf8), true)
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: script)
        try? FileManager.default.removeItem(at: recordURL)
    }

    // MARK: - Script

    func writeScript() throws {
        try FileOps.ensureRealDirectory(paths.clepsoDir, mode: 0o700)
        try FileOps.atomicReplace(script, with: Array(scriptText().utf8), mode: 0o700)
    }

    /// Regenerates the script when the app moved. settings.json is neither read nor written.
    public func repair() throws {
        guard isInstalled else { return }
        try writeScript()
    }

    public func needsRepair() -> Bool {
        guard isInstalled else { return false }
        let text = FileOps.readBytes(script).map { String(decoding: $0, as: UTF8.self) } ?? ""
        return !text.contains("CLEPSO_SHIM=\(SettingsInstaller.singleQuoted(shimPath))\n")
    }

    func scriptText() -> String {
        """
        #!/bin/sh
        # Clepso hook wrapper v1. Generated \(FileOps.basicISO8601(now())). Do not edit; Clepso regenerates it.
        # Counts subagents per task: sends the event name, hashed ids and a built-in agent type, never content.
        CLEPSO_SHIM=\(SettingsInstaller.singleQuoted(shimPath))
        if [ -x "$CLEPSO_SHIM" ]; then
          exec "$CLEPSO_SHIM" --hook
        fi
        exit 0

        """
    }
}
