import CryptoKit
import Darwin
import Domain
import Foundation

/// Reversible status-line install into Claude Code's user settings (PRIVACY_AND_SECURITY §7).
///
/// Only `statusLine.command` changes. The pre-install bytes are backed up first, every settings write is
/// compare-and-swap plus atomic rename, and the install state is recorded after each step so an
/// interrupted install can be recovered (`recover()`) without guessing.
public struct SettingsInstaller: Sendable {
    public struct Paths: Sendable {
        public let claudeDir: URL
        /// The value written into `statusLine.command`.
        public let commandValue: String
        /// The app's folder name inside `claudeDir`: `clepso`, or `pulse` in the layout from before the rename.
        public let folderName: String

        public var settings: URL { claudeDir.appendingPathComponent("settings.json") }
        public var clepsoDir: URL { claudeDir.appendingPathComponent(folderName) }
        public var backupsDir: URL { claudeDir.appendingPathComponent("\(folderName)-backups") }
        public var wrapper: URL { clepsoDir.appendingPathComponent("statusline.sh") }
        public var sidecar: URL { clepsoDir.appendingPathComponent("original-statusline.json") }
        public var config: URL { clepsoDir.appendingPathComponent("config.json") }
        public var key: URL { clepsoDir.appendingPathComponent("session.key") }
        public var record: URL { clepsoDir.appendingPathComponent("install-state.json") }

        /// `~/.claude` unless the user runs Claude Code with `CLAUDE_CONFIG_DIR`.
        public init(home: URL, claudeConfigDir: URL? = nil) {
            self.init(home: home, claudeConfigDir: claudeConfigDir, folderName: "clepso")
        }

        init(home: URL, claudeConfigDir: URL?, folderName: String) {
            self.folderName = folderName
            if let custom = claudeConfigDir {
                claudeDir = custom
                commandValue = custom.appendingPathComponent("\(folderName)/statusline.sh").path
            } else {
                claudeDir = home.appendingPathComponent(".claude")
                commandValue = "~/.claude/\(folderName)/statusline.sh"   // Claude Code expands `~` (doc example)
            }
        }

        /// Where installs made before the rename to Clepso live: `~/.claude/pulse` and `~/.claude/pulse-backups`, with
        /// `statusLine.command` = `~/.claude/pulse/statusline.sh`. Read only by `LegacyLayoutMigration`.
        public static func legacy(home: URL, claudeConfigDir: URL? = nil) -> Paths {
            Paths(home: home, claudeConfigDir: claudeConfigDir, folderName: "pulse")
        }
    }

    public enum InstallError: Error, Equatable {
        case claudeNotDetected
        case settingsInvalidJSON
        case unsupportedExistingStatusLine
        case alreadyInstalled(state: String)
        case settingsChangedDuringInstall
        case symlinkRefused(path: String)
        case verificationFailed
        case io(String)
    }

    public struct InstallReport: Sendable, Equatable {
        public let backupPath: String?          // nil when Clepso created settings.json
        public let createdSettingsFile: Bool
        public let hadExistingStatusLine: Bool
    }

    public enum UninstallOutcome: Sendable, Equatable {
        case notInstalled
        case restoredExactly                     // bytes and SHA-256 equal the pre-install file
        case deletedCreatedFile                  // Clepso had created settings.json; nothing else was added
        case restoredStatusLineOnly(backupPath: String?, formattingChanged: Bool)
        case leftUnchanged(reason: String)       // the user already replaced or removed our status line
    }

    public enum RecoveryOutcome: Sendable, Equatable {
        case nothingToRecover
        case cleanedUp                           // settings untouched; Clepso's partial files removed
        case completed                           // settings were written; verification now passed
        case rolledBack                          // settings were written but failed verification
        case needsUserDecision(backupPath: String?)
    }

    public let paths: Paths
    public let shimPath: String
    public let socketPath: String
    public let forwardCost: Bool
    let now: @Sendable () -> Date
    /// Test hook: runs between reading settings and the compare-and-swap write.
    let beforeSettingsWrite: (@Sendable () -> Void)?

    public init(paths: Paths, shimPath: String, socketPath: String, forwardCost: Bool = true,
                now: @escaping @Sendable () -> Date = { SystemClock().now() }) {
        self.init(paths: paths, shimPath: shimPath, socketPath: socketPath, forwardCost: forwardCost,
                  now: now, beforeSettingsWrite: nil)
    }

    init(paths: Paths, shimPath: String, socketPath: String, forwardCost: Bool,
         now: @escaping @Sendable () -> Date, beforeSettingsWrite: (@Sendable () -> Void)?) {
        self.paths = paths
        self.shimPath = shimPath
        self.socketPath = socketPath
        self.forwardCost = forwardCost
        self.now = now
        self.beforeSettingsWrite = beforeSettingsWrite
    }

    // MARK: - Install record

    enum State: String, Codable { case backupWritten = "backup_written", filesWritten = "files_written",
                                       settingsWritten = "settings_written", verified }

    struct Record: Codable {
        var state: State
        var h0: String?                          // sha256 of the pre-install bytes; nil if no file
        var h1: String?                          // sha256 of the bytes Clepso wrote
        var createdByClepso: Bool
        var backupPath: String?
        var originalMode: UInt16?

        enum CodingKeys: String, CodingKey { case state, h0, h1, createdByClepso, backupPath, originalMode }
        /// Records written before the rename to Clepso name the flag `createdByPulse`.
        enum LegacyKeys: String, CodingKey { case createdByPulse }

        init(state: State, h0: String?, h1: String?, createdByClepso: Bool, backupPath: String?, originalMode: UInt16?) {
            self.state = state
            self.h0 = h0
            self.h1 = h1
            self.createdByClepso = createdByClepso
            self.backupPath = backupPath
            self.originalMode = originalMode
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            state = try container.decode(State.self, forKey: .state)
            h0 = try container.decodeIfPresent(String.self, forKey: .h0)
            h1 = try container.decodeIfPresent(String.self, forKey: .h1)
            backupPath = try container.decodeIfPresent(String.self, forKey: .backupPath)
            originalMode = try container.decodeIfPresent(UInt16.self, forKey: .originalMode)
            if let flag = try container.decodeIfPresent(Bool.self, forKey: .createdByClepso) {
                createdByClepso = flag
            } else {
                createdByClepso = try decoder.container(keyedBy: LegacyKeys.self).decode(Bool.self, forKey: .createdByPulse)
            }
        }
    }

    func loadRecord() -> Record? {
        guard let data = FileOps.readBytes(paths.record) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: Data(data))
    }

    func save(_ record: Record) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try FileOps.atomicReplace(paths.record, with: Array(try encoder.encode(record)), mode: 0o600)
    }

    // MARK: - Validation and preview

    /// Install step 1 (PRIVACY_AND_SECURITY §7): read the settings file and refuse anything the editor cannot
    /// change safely. Writes nothing; `preview()` and `install()` share it so they cannot disagree.
    func readValidated() throws -> (FileOps.Contents?, [String: Any], [String: Any]?, JSONObjectLayout?) {
        let original = try FileOps.readNoFollow(paths.settings)
        var originalObject: [String: Any] = [:]
        var existingStatusLine: [String: Any]?
        if let original {
            guard let object = FileOps.jsonObject(original.bytes) else { throw InstallError.settingsInvalidJSON }
            originalObject = object
            if let value = object["statusLine"] {
                guard let statusLine = value as? [String: Any], statusLine["type"] as? String == "command",
                      statusLine["command"] is String else { throw InstallError.unsupportedExistingStatusLine }
                existingStatusLine = statusLine
            }
        }
        // Foundation's parser tolerates some invalid JSON (a trailing comma, for one), so the strict
        // scanner must accept the file too; otherwise it is refused rather than rewritten.
        let layout = original.flatMap { JSONObjectLayout.parseDocument($0.bytes) }
        if original != nil, layout == nil { throw InstallError.settingsInvalidJSON }
        if let layout {
            let statusLines = layout.members(named: "statusLine")
            guard statusLines.count <= 1 else { throw InstallError.unsupportedExistingStatusLine }
            if let member = statusLines.first {
                var i = member.valueStart
                guard let inner = JSONObjectLayout.parseObject(layout.bytes, at: &i),
                      inner.members(named: "command").count == 1 else { throw InstallError.unsupportedExistingStatusLine }
            }
        }
        return (original, originalObject, existingStatusLine, layout)
    }

    /// What the consent screen shows before any write: the real file, backup folder and
    /// current command, and whether install would refuse. Reads only.
    public struct Preview: Sendable, Equatable {
        public let claudeDetected: Bool
        public let settingsPath: String
        public let settingsExists: Bool
        public let backupsDir: String
        public let existingCommand: String?
        public let installed: Bool
        public let refusal: InstallError?
    }

    public func preview() -> Preview {
        let detected = FileOps.isRealDirectory(paths.claudeDir)
        var exists = false, command: String?, refusal: InstallError?
        if !detected {
            refusal = .claudeNotDetected
        } else {
            do {
                let (original, _, statusLine, _) = try readValidated()
                exists = original != nil
                command = statusLine?["command"] as? String
            } catch let error as InstallError {
                exists = FileManager.default.fileExists(atPath: paths.settings.path)
                refusal = error
            } catch {
                refusal = .io("\(error)")
            }
        }
        if refusal == nil, let record = loadRecord(), record.state != .verified { refusal = .alreadyInstalled(state: record.state.rawValue) }
        return Preview(claudeDetected: detected, settingsPath: paths.settings.path, settingsExists: exists,
                       backupsDir: paths.backupsDir.path, existingCommand: command, installed: isInstalled, refusal: refusal)
    }

    /// True once an install has been verified and not yet removed.
    public var isInstalled: Bool { loadRecord()?.state == .verified }

    // MARK: - Install

    public func install() throws -> InstallReport {
        guard FileOps.isRealDirectory(paths.claudeDir) else { throw InstallError.claudeNotDetected }
        if let record = loadRecord() { throw InstallError.alreadyInstalled(state: record.state.rawValue) }

        // 1. Read and validate before writing anything.
        let (original, originalObject, existingStatusLine, layout) = try readValidated()

        // 2. Backup.
        try FileOps.ensureRealDirectory(paths.backupsDir, mode: 0o700)
        try FileOps.ensureRealDirectory(paths.clepsoDir, mode: 0o700)
        let h0 = original.map { FileOps.sha256($0.bytes) }
        var backupPath: String?
        if let original, let h0 {
            let stamp = FileOps.basicISO8601(now())
            let backup = paths.backupsDir.appendingPathComponent("settings.json.\(stamp).\(h0.prefix(12)).bak")
            try FileOps.writeExclusive(backup, bytes: original.bytes, mode: 0o600)
            backupPath = backup.path
        }
        try appendManifest(hash: h0, mode: original?.mode, size: original?.bytes.count, createdByClepso: original == nil)
        var record = Record(state: .backupWritten, h0: h0, h1: nil, createdByClepso: original == nil,
                            backupPath: backupPath, originalMode: original?.mode)
        try save(record)

        // 3. Sidecar, config, key, wrapper.
        let originalCommand = existingStatusLine?["command"] as? String
        if let layout, let member = layout.members(named: "statusLine").first {
            try FileOps.atomicReplace(paths.sidecar, with: Array(layout.bytes[member.valueStart..<member.valueEnd]), mode: 0o600)
        } else if let existingStatusLine {
            try FileOps.atomicReplace(paths.sidecar, with: FileOps.serialize(existingStatusLine, pretty: false), mode: 0o600)
        }
        try writeConfig(originalCommand: originalCommand)
        if FileOps.readBytes(paths.key) == nil {
            var generator = SystemRandomNumberGenerator()
            try FileOps.atomicReplace(paths.key, with: (0..<32).map { _ in UInt8.random(in: 0...255, using: &generator) }, mode: 0o600)
        }
        try FileOps.atomicReplace(paths.wrapper, with: Array(wrapperScript(originalCommand: originalCommand).utf8), mode: 0o700)
        record.state = .filesWritten
        try save(record)

        // 4. Compose the new bytes.
        let newBytes = compose(layout: layout)

        // 5. Compare-and-swap write.
        beforeSettingsWrite?()
        let current = try FileOps.readNoFollow(paths.settings)
        guard current.map({ FileOps.sha256($0.bytes) }) == h0 else {
            try? FileManager.default.removeItem(at: paths.clepsoDir)
            throw InstallError.settingsChangedDuringInstall
        }
        try FileOps.atomicReplace(paths.settings, with: newBytes, mode: original?.mode ?? 0o644)
        record.state = .settingsWritten
        record.h1 = FileOps.sha256(newBytes)
        try save(record)

        // 6. Verify, or roll back.
        guard verifyInstalled(originalObject: originalObject, originalStatusLine: existingStatusLine) else {
            try rollBack(record)
            throw InstallError.verificationFailed
        }
        record.state = .verified
        try save(record)
        return InstallReport(backupPath: backupPath, createdSettingsFile: original == nil,
                             hadExistingStatusLine: existingStatusLine != nil)
    }

    /// New settings bytes: the `command` value replaced in place, or one `statusLine` member appended,
    /// or a new file when there was none. Every other byte is the original's.
    func compose(layout: JSONObjectLayout?) -> [UInt8] {
        let command = Array(JSONObjectLayout.quoted(paths.commandValue).utf8)
        guard let layout else {
            return Array("{\n  \"statusLine\": {\"type\": \"command\", \"command\": ".utf8) + command + Array("}\n}\n".utf8)
        }
        if let member = layout.members(named: "statusLine").first {
            var i = member.valueStart
            if let inner = JSONObjectLayout.parseObject(layout.bytes, at: &i),
               let commandMember = inner.members(named: "command").first {
                return inner.replacingValue(of: commandMember, with: command)
            }
        }
        let value = Array("{\"type\": \"command\", \"command\": ".utf8) + command + Array("}".utf8)
        return layout.appendingMember(key: "statusLine", value: value)
    }

    /// §3 step 6: every top-level key except `statusLine` is unchanged, and `statusLine` differs from the
    /// original only in `command`.
    func verifyInstalled(originalObject: [String: Any], originalStatusLine: [String: Any]?) -> Bool {
        guard let written = try? FileOps.readNoFollow(paths.settings), let object = FileOps.jsonObject(written.bytes),
              let statusLine = object["statusLine"] as? [String: Any] else { return false }
        guard Set(object.keys) == Set(originalObject.keys).union(["statusLine"]) else { return false }
        for (key, value) in originalObject where key != "statusLine" {
            guard let other = object[key], (value as AnyObject).isEqual(other) else { return false }
        }
        guard statusLine["command"] as? String == paths.commandValue else { return false }
        var expected = originalStatusLine ?? ["type": "command"]
        expected["command"] = paths.commandValue
        return (statusLine as NSDictionary).isEqual(to: expected)
    }

    func rollBack(_ record: Record) throws {
        if record.createdByClepso {
            unlink(paths.settings.path)
        } else if let backup = record.backupPath, let bytes = try FileOps.readNoFollow(URL(fileURLWithPath: backup))?.bytes {
            try FileOps.atomicReplace(paths.settings, with: bytes, mode: record.originalMode ?? 0o644)
        }
        try? FileManager.default.removeItem(at: paths.clepsoDir)
    }

    // MARK: - Uninstall (§3.2)

    public func uninstall() throws -> UninstallOutcome {
        guard let record = loadRecord() else { return .notInstalled }
        guard record.state == .verified || record.state == .settingsWritten else {
            _ = recover()
            return .notInstalled
        }
        let current = try FileOps.readNoFollow(paths.settings)
        let hc = current.map { FileOps.sha256($0.bytes) }

        if hc != nil, hc == record.h1 {
            if record.createdByClepso {
                unlink(paths.settings.path)
                try removeClepsoFiles()
                return .deletedCreatedFile
            }
            guard let backup = record.backupPath,
                  let bytes = try FileOps.readNoFollow(URL(fileURLWithPath: backup))?.bytes,
                  FileOps.sha256(bytes) == record.h0 else { throw InstallError.io("backup missing or altered") }
            try FileOps.atomicReplace(paths.settings, with: bytes, mode: record.originalMode ?? 0o644)
            guard try FileOps.readNoFollow(paths.settings).map({ FileOps.sha256($0.bytes) }) == record.h0 else {
                throw InstallError.verificationFailed
            }
            try removeClepsoFiles()
            return .restoredExactly
        }

        guard let current, let object = FileOps.jsonObject(current.bytes) else {
            try removeClepsoFiles()
            return .leftUnchanged(reason: current == nil ? "settings.json was removed" : "settings.json is not valid JSON")
        }
        guard (object["statusLine"] as? [String: Any])?["command"] as? String == paths.commandValue else {
            try removeClepsoFiles()
            return .leftUnchanged(reason: "the status line no longer points to this app")
        }

        // Surgical: put back the original statusLine (or remove ours), keep every other byte.
        let sidecar = try FileOps.readNoFollow(paths.sidecar)?.bytes
        var newBytes: [UInt8]
        var formattingChanged = false
        if let layout = JSONObjectLayout.parseDocument(current.bytes),
           let member = layout.members(named: "statusLine").first, layout.members(named: "statusLine").count == 1 {
            newBytes = sidecar.map { layout.replacingValue(of: member, with: $0) } ?? layout.removingMember(member)
        } else {
            var updated = object
            updated["statusLine"] = sidecar.flatMap { try? JSONSerialization.jsonObject(with: Data($0)) }
            newBytes = FileOps.serialize(updated, pretty: true) + Array("\n".utf8)
            formattingChanged = true
        }
        guard try FileOps.readNoFollow(paths.settings).map({ FileOps.sha256($0.bytes) }) == hc else {
            throw InstallError.settingsChangedDuringInstall
        }
        try FileOps.atomicReplace(paths.settings, with: newBytes, mode: current.mode)
        guard let restored = FileOps.jsonObject(newBytes),
              Set(restored.keys.filter { $0 != "statusLine" }) == Set(object.keys.filter { $0 != "statusLine" }) else {
            throw InstallError.verificationFailed
        }
        try removeClepsoFiles()
        return .restoredStatusLineOnly(backupPath: record.backupPath, formattingChanged: formattingChanged)
    }

    /// Removes `~/.claude/clepso/`. Backups stay for 30 days (PRIVACY_AND_SECURITY §6).
    func removeClepsoFiles() throws {
        if FileManager.default.fileExists(atPath: paths.clepsoDir.path) {
            try FileManager.default.removeItem(at: paths.clepsoDir)
        }
    }

    // MARK: - Recovery after an interrupted install (§3.4)

    public func recover() -> RecoveryOutcome {
        guard let record = loadRecord(), record.state != .verified else { return .nothingToRecover }
        let hc = FileOps.readBytes(paths.settings).map(FileOps.sha256)
        switch record.state {
        case .backupWritten, .filesWritten:
            guard hc == record.h0 else { return .needsUserDecision(backupPath: record.backupPath) }
            try? removeClepsoFiles()
            return .cleanedUp
        case .settingsWritten:
            guard hc != nil, hc == record.h1 else {
                guard hc == record.h0 else { return .needsUserDecision(backupPath: record.backupPath) }
                try? removeClepsoFiles()
                return .cleanedUp
            }
            let originalBytes = record.backupPath.flatMap { FileOps.readBytes(URL(fileURLWithPath: $0)) }
            let originalObject = originalBytes.flatMap(FileOps.jsonObject) ?? [:]
            if verifyInstalled(originalObject: originalObject, originalStatusLine: originalObject["statusLine"] as? [String: Any]) {
                var verified = record
                verified.state = .verified
                return (try? save(verified)) != nil ? .completed : .needsUserDecision(backupPath: record.backupPath)
            }
            return (try? rollBack(record)) != nil ? .rolledBack : .needsUserDecision(backupPath: record.backupPath)
        case .verified:
            return .nothingToRecover
        }
    }

    // MARK: - Repair (§3.3)

    /// True when the installed wrapper or config no longer points at this app's helper or socket.
    public func needsRepair() -> Bool {
        guard loadRecord()?.state == .verified else { return false }
        let wrapper = FileOps.readBytes(paths.wrapper).map { String(decoding: $0, as: UTF8.self) } ?? ""
        let config = FileOps.readBytes(paths.config).flatMap(FileOps.jsonObject)
        return !wrapper.contains("CLEPSO_SHIM=\(Self.singleQuoted(shimPath))\n") || config?["socket"] as? String != socketPath
    }

    /// Regenerates only the wrapper and config. settings.json is neither read nor written.
    public func repair() throws {
        guard loadRecord()?.state == .verified else { throw InstallError.io("not installed") }
        let config = FileOps.readBytes(paths.config).flatMap(FileOps.jsonObject)
        let originalCommand = config?["original_command"] as? String
        try writeConfig(originalCommand: originalCommand)
        try FileOps.atomicReplace(paths.wrapper, with: Array(wrapperScript(originalCommand: originalCommand).utf8), mode: 0o700)
    }

    // MARK: - Generated files

    func writeConfig(originalCommand: String?) throws {
        let config: [String: Any] = ["v": 1, "socket": socketPath, "original_command": originalCommand ?? NSNull(),
                                     "forward_cost": forwardCost, "hmac_key_file": paths.key.path]
        try FileOps.atomicReplace(paths.config, with: FileOps.serialize(config, pretty: true), mode: 0o600)
    }

    /// §1.1 exact form. The `[ -x ]` guard is what lets a missing app fall through to the original
    /// command; `exec shim || exec original` would not, because a failed exec ends the shell.
    func wrapperScript(originalCommand: String?) -> String {
        let fallback = originalCommand.map { "exec /bin/sh -c \(Self.singleQuoted($0))" } ?? "exit 0"
        return """
        #!/bin/sh
        # Clepso status-line wrapper v1. Generated \(FileOps.basicISO8601(now())). Do not edit; "Repair" regenerates it.
        CLEPSO_SHIM=\(Self.singleQuoted(shimPath))
        if [ -x "$CLEPSO_SHIM" ]; then
          exec "$CLEPSO_SHIM"
        fi
        # Fallback: the binary is missing (app moved or deleted). Run the user's original command unchanged.
        \(fallback)

        """
    }

    static func singleQuoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    func appendManifest(hash: String?, mode: UInt16?, size: Int?, createdByClepso: Bool) throws {
        let entry: [String: Any] = ["ts": FileOps.basicISO8601(now()), "hash": hash ?? NSNull(), "mode": mode.map { Int($0) } ?? NSNull(),
                                    "size": size ?? NSNull(), "created_by_clepso": createdByClepso]
        let line = FileOps.serialize(entry, pretty: false) + Array("\n".utf8)
        let manifest = paths.backupsDir.appendingPathComponent("manifest.jsonl")
        let fd = open(manifest.path, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw errno == ELOOP ? InstallError.symlinkRefused(path: manifest.path) : InstallError.io("manifest") }
        defer { close(fd) }
        guard line.withUnsafeBytes({ write(fd, $0.baseAddress, $0.count) }) == line.count else { throw InstallError.io("manifest write") }
    }
}

// MARK: - File operations

enum FileOps {
    struct Contents { let bytes: [UInt8]; let mode: UInt16 }

    /// Reads a file without following a symlink. nil when the file does not exist.
    static func readNoFollow(_ url: URL) throws -> Contents? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        if fd < 0 {
            if errno == ENOENT { return nil }
            if errno == ELOOP { throw SettingsInstaller.InstallError.symlinkRefused(path: url.path) }
            throw SettingsInstaller.InstallError.io("open \(url.lastPathComponent): errno \(errno)")
        }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            throw SettingsInstaller.InstallError.io("\(url.lastPathComponent) is not a regular file")
        }
        var bytes: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n > 0 { bytes.append(contentsOf: buffer[0..<n]) } else if n < 0 && errno == EINTR { continue } else { break }
        }
        return Contents(bytes: bytes, mode: UInt16(info.st_mode & 0o7777))
    }

    /// Whole-file bytes, or nil when the file is missing, a symlink or unreadable.
    static func readBytes(_ url: URL) -> [UInt8]? {
        guard let contents = try? readNoFollow(url) else { return nil }   // try? flattens: missing file is nil too
        return contents.bytes
    }

    static func writeExclusive(_ url: URL, bytes: [UInt8], mode: mode_t) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode)
        guard fd >= 0 else { throw SettingsInstaller.InstallError.io("create \(url.lastPathComponent): errno \(errno)") }
        defer { close(fd) }
        try writeAll(fd, bytes)
        guard fsync(fd) == 0 else { throw SettingsInstaller.InstallError.io("fsync") }
    }

    /// Temp file in the same directory (O_EXCL), fsync, chmod, rename(2), fsync the directory.
    static func atomicReplace(_ url: URL, with bytes: [UInt8], mode: UInt16) throws {
        let directory = url.deletingLastPathComponent()
        var template = Array(directory.appendingPathComponent(".\(url.lastPathComponent).clepso-XXXXXX").path.utf8CString)
        let fd = template.withUnsafeMutableBufferPointer { mkstemp($0.baseAddress!) }
        guard fd >= 0 else { throw SettingsInstaller.InstallError.io("temp file: errno \(errno)") }
        let tempPath = String(decoding: template.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        do {
            try writeAll(fd, bytes)
            guard fchmod(fd, mode_t(mode)) == 0, fsync(fd) == 0 else { throw SettingsInstaller.InstallError.io("fchmod/fsync") }
            close(fd)
            guard rename(tempPath, url.path) == 0 else { throw SettingsInstaller.InstallError.io("rename: errno \(errno)") }
        } catch {
            close(fd)
            unlink(tempPath)
            throw error
        }
        let dirFD = open(directory.path, O_RDONLY)
        if dirFD >= 0 { fsync(dirFD); close(dirFD) }
    }

    static func writeAll(_ fd: Int32, _ bytes: [UInt8]) throws {
        var offset = 0
        while offset < bytes.count {
            let n = bytes[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if n > 0 { offset += n } else if n < 0 && errno == EINTR { continue } else {
                throw SettingsInstaller.InstallError.io("write: errno \(errno)")
            }
        }
    }

    static func isRealDirectory(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
    }

    /// Creates the directory, or accepts an existing one only if it is a real directory owned by us.
    static func ensureRealDirectory(_ url: URL, mode: mode_t) throws {
        var info = stat()
        if lstat(url.path, &info) == 0 {
            if (info.st_mode & S_IFMT) == S_IFLNK { throw SettingsInstaller.InstallError.symlinkRefused(path: url.path) }
            guard (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == getuid() else {
                throw SettingsInstaller.InstallError.io("\(url.lastPathComponent) is not a directory owned by this user")
            }
            return
        }
        guard mkdir(url.path, mode) == 0 else { throw SettingsInstaller.InstallError.io("mkdir \(url.lastPathComponent): errno \(errno)") }
        chmod(url.path, mode)
    }

    static func jsonObject(_ bytes: [UInt8]) -> [String: Any]? {
        let body = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? Array(bytes.dropFirst(3)) : bytes
        return (try? JSONSerialization.jsonObject(with: Data(body), options: [.fragmentsAllowed])) as? [String: Any]
    }

    static func serialize(_ object: Any, pretty: Bool) -> [UInt8] {
        var options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
        if pretty { options.insert(.prettyPrinted) }
        return Array((try? JSONSerialization.data(withJSONObject: object, options: options)) ?? Data())
    }

    static func sha256(_ bytes: [UInt8]) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    static func basicISO8601(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }
}
