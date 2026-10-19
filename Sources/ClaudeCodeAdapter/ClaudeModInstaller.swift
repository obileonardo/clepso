import Darwin
import Domain
import Foundation

/// Limits from the Claude desktop app's Code tab and the VS Code panel (v0.3, docs/specs/mod-bridge.md §9): installs
/// Clepso's Claude Code mod and takes it out again, with the guarantees of `SettingsInstaller` and `HooksInstaller`
/// (backup first, compare-and-swap, verify, exact restore).
///
/// Install copies the mod's marketplace from the app bundle into `~/.claude/clepso/claude-mod/`, writes the hand-off
/// script the mod runs (`mod-handoff.sh`, which execs the signed helper with `--mod`, or exits 0 if it's gone), and adds
/// two members to `settings.json`: `extraKnownMarketplaces.clepso` (a `directory` source naming that folder) and
/// `enabledPlugins["clepso-limits@clepso"]: true`. These are the documented keys Claude Code itself writes for a user-scope
/// install; Clepso writes them with its own byte-preserving scanner because `claude plugin install` re-serialises the
/// whole file (mod-bridge.md §2.2, experiment E-A). Requires the status-line connection (config, socket, session key).
public struct ClaudeModInstaller: Sendable {
    public enum InstallError: Error, Equatable {
        case connectionNotInstalled
        case alreadyInstalled
        case settingsInvalidJSON
        /// `extraKnownMarketplaces` or `enabledPlugins` has a shape the scanner can't edit safely (not one object).
        case unsupportedExistingEntries
        /// settings.json already names a `clepso` marketplace or the `clepso-limits@clepso` plugin, not from Clepso.
        case conflictingEntry
        /// `disableAllHooks` is true in settings.json: the mod couldn't run (and nor would the status line).
        case modsTurnedOff
        /// The mod isn't in the app bundle (a damaged or partial build).
        case bundleMissing
        case settingsChangedDuringInstall
        case verificationFailed
        case io(String)
    }

    public enum UninstallOutcome: Sendable, Equatable {
        case notInstalled
        case restoredExactly                         // settings.json is byte-identical to before the mod was added
        case removedEntries(formattingChanged: Bool) // the user edited settings since; only Clepso's two entries came out
        case entriesAlreadyGone                      // nothing of Clepso's was left in settings.json
    }

    public static let marketplaceName = "clepso"
    public static let pluginName = "clepso-limits"
    public static var pluginID: String { "\(pluginName)@\(marketplaceName)" }
    static let marketplacesKey = "extraKnownMarketplaces"
    static let marketplacesAlias = "additionalMarketplaces"     // the same key under its documented alias
    static let pluginsKey = "enabledPlugins"

    public let paths: SettingsInstaller.Paths
    public let shimPath: String
    /// The mod's marketplace folder in the app bundle (`Contents/Resources/claude-code`); tests pass the repo's `mod/claude-code`.
    public let bundledMod: URL
    let now: @Sendable () -> Date
    let beforeSettingsWrite: (@Sendable () -> Void)?

    public init(paths: SettingsInstaller.Paths, shimPath: String, bundledMod: URL, now: @escaping @Sendable () -> Date = { SystemClock().now() }) {
        self.init(paths: paths, shimPath: shimPath, bundledMod: bundledMod, now: now, beforeSettingsWrite: nil)
    }

    init(paths: SettingsInstaller.Paths, shimPath: String, bundledMod: URL, now: @escaping @Sendable () -> Date,
         beforeSettingsWrite: (@Sendable () -> Void)?) {
        self.paths = paths
        self.shimPath = shimPath
        self.bundledMod = bundledMod
        self.now = now
        self.beforeSettingsWrite = beforeSettingsWrite
    }

    public var marketplaceDir: URL { paths.clepsoDir.appendingPathComponent("claude-mod") }
    var script: URL { paths.clepsoDir.appendingPathComponent("mod-handoff.sh") }
    var recordURL: URL { paths.clepsoDir.appendingPathComponent("mod-state.json") }

    /// The value of `extraKnownMarketplaces.clepso`, as written.
    var marketplaceBytes: [UInt8] {
        Array("{\"source\": {\"source\": \"directory\", \"path\": \(JSONObjectLayout.quoted(marketplaceDir.path))}}".utf8)
    }
    var marketplaceObject: [String: Any] { FileOps.jsonObject(marketplaceBytes) ?? [:] }

    public var isInstalled: Bool { loadRecord() != nil }

    /// What the consent sheet shows before any write: the two entries, exactly as they go into settings.json.
    public var previewEntries: String {
        "\"\(Self.marketplacesKey)\": {\"\(Self.marketplaceName)\": \(String(decoding: marketplaceBytes, as: UTF8.self))}\n" +
        "\"\(Self.pluginsKey)\": {\"\(Self.pluginID)\": true}"
    }

    // MARK: - Record

    struct Record: Codable {
        var h0: String                  // settings.json before the mod
        var h1: String                  // settings.json with it
        var backupPath: String
        var createdMarketplacesKey: Bool
        var createdPluginsKey: Bool
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

    public func install() throws {
        guard FileOps.readBytes(paths.record).flatMap(FileOps.jsonObject)?["state"] as? String == "verified" else {
            throw InstallError.connectionNotInstalled
        }
        guard !isInstalled else { throw InstallError.alreadyInstalled }
        let files = try bundledFiles()
        guard let original = try FileOps.readNoFollow(paths.settings), let originalObject = FileOps.jsonObject(original.bytes),
              JSONObjectLayout.parseDocument(original.bytes) != nil else { throw InstallError.settingsInvalidJSON }
        try Self.validate(original.bytes, object: originalObject)

        // Backup, the mod and the hand-off script before settings.json is touched.
        let h0 = FileOps.sha256(original.bytes)
        try FileOps.ensureRealDirectory(paths.backupsDir, mode: 0o700)
        let backup = try writeBackup(original.bytes, h0: h0)
        do {
            try copyMod(files)
            try writeScript()
        } catch {
            removeFiles()
            throw error
        }

        let newBytes: [UInt8]
        do { newBytes = try compose(original.bytes) } catch { removeFiles(); throw error }
        beforeSettingsWrite?()
        guard try FileOps.readNoFollow(paths.settings).map({ FileOps.sha256($0.bytes) }) == h0 else {
            removeFiles()
            throw InstallError.settingsChangedDuringInstall
        }
        try FileOps.atomicReplace(paths.settings, with: newBytes, mode: original.mode)
        guard verifyInstalled(originalObject: originalObject) else {
            try FileOps.atomicReplace(paths.settings, with: original.bytes, mode: original.mode)
            removeFiles()
            throw InstallError.verificationFailed
        }
        try save(Record(h0: h0, h1: FileOps.sha256(newBytes), backupPath: backup.path,
                        createdMarketplacesKey: originalObject[Self.marketplacesKey] == nil,
                        createdPluginsKey: originalObject[Self.pluginsKey] == nil, originalMode: original.mode))
    }

    /// The backup of `bytes` (`FileOps.writeBackup`: an identical one from the same second is reused, otherwise the next
    /// free name).
    func writeBackup(_ bytes: [UInt8], h0: String) throws -> URL {
        let stem = "settings.json.\(FileOps.basicISO8601(now())).\(h0.prefix(12)).pre-mod"
        guard let url = try FileOps.writeBackup(bytes, in: paths.backupsDir, stem: stem) else {
            throw InstallError.io("no free backup name")
        }
        return url
    }

    /// Both keys absent or exactly one editable object each; neither may already name Clepso's marketplace or plugin;
    /// `disableAllHooks` must not be on.
    static func validate(_ bytes: [UInt8], object: [String: Any]) throws {
        if object["disableAllHooks"] as? Bool == true { throw InstallError.modsTurnedOff }
        guard let layout = JSONObjectLayout.parseDocument(bytes) else { throw InstallError.settingsInvalidJSON }
        for key in [marketplacesKey, pluginsKey] {
            guard let value = object[key] else { continue }
            guard value is [String: Any], layout.members(named: key).count == 1, let member = layout.members(named: key).first else {
                throw InstallError.unsupportedExistingEntries
            }
            var i = member.valueStart
            guard JSONObjectLayout.parseObject(bytes, at: &i) != nil else { throw InstallError.unsupportedExistingEntries }
        }
        let marketplaces = (object[marketplacesKey] as? [String: Any] ?? [:]).merging(object[marketplacesAlias] as? [String: Any] ?? [:]) { a, _ in a }
        if marketplaces[marketplaceName] != nil { throw InstallError.conflictingEntry }
        if (object[pluginsKey] as? [String: Any])?[pluginID] != nil { throw InstallError.conflictingEntry }
    }

    /// Settings bytes with Clepso's two members added. Every other byte is the original's.
    func compose(_ original: [UInt8]) throws -> [UInt8] {
        var bytes = original
        for (key, name, value) in [(Self.marketplacesKey, Self.marketplaceName, marketplaceBytes),
                                   (Self.pluginsKey, Self.pluginID, Array("true".utf8))] {
            guard let document = JSONObjectLayout.parseDocument(bytes) else { throw InstallError.settingsInvalidJSON }
            if let member = document.members(named: key).first {
                var i = member.valueStart
                guard let inner = JSONObjectLayout.parseObject(bytes, at: &i) else { throw InstallError.unsupportedExistingEntries }
                bytes = inner.appendingMember(key: name, value: value)
            } else {
                bytes = document.appendingMember(key: key, value: Array("{\(JSONObjectLayout.quoted(name)): ".utf8) + value + Array("}".utf8))
            }
        }
        return bytes
    }

    /// Every other top-level key unchanged; inside the two objects, every other member unchanged and Clepso's present.
    func verifyInstalled(originalObject: [String: Any]) -> Bool {
        guard let written = try? FileOps.readNoFollow(paths.settings), let object = FileOps.jsonObject(written.bytes) else { return false }
        guard Set(object.keys) == Set(originalObject.keys).union([Self.marketplacesKey, Self.pluginsKey]) else { return false }
        for (key, value) in originalObject where key != Self.marketplacesKey && key != Self.pluginsKey {
            guard let other = object[key], (value as AnyObject).isEqual(other) else { return false }
        }
        var marketplaces = originalObject[Self.marketplacesKey] as? [String: Any] ?? [:]
        marketplaces[Self.marketplaceName] = marketplaceObject
        var plugins = originalObject[Self.pluginsKey] as? [String: Any] ?? [:]
        plugins[Self.pluginID] = true
        return (object[Self.marketplacesKey] as AnyObject).isEqual(marketplaces) && (object[Self.pluginsKey] as AnyObject).isEqual(plugins)
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

        guard let current, let object = FileOps.jsonObject(current.bytes),
              let (newBytes, formattingChanged) = removingEntries(current.bytes, object: object, record: record) else {
            removeFiles()
            return .entriesAlreadyGone
        }
        guard try FileOps.readNoFollow(paths.settings).map({ FileOps.sha256($0.bytes) }) == hc else {
            throw InstallError.settingsChangedDuringInstall
        }
        try FileOps.atomicReplace(paths.settings, with: newBytes, mode: current.mode)
        let others = { (o: [String: Any]) in o.filter { $0.key != Self.marketplacesKey && $0.key != Self.pluginsKey } }
        guard let after = FileOps.jsonObject(newBytes), !containsEntries(after), (others(after) as NSDictionary).isEqual(to: others(object)) else {
            throw InstallError.verificationFailed
        }
        removeFiles()
        return .removedEntries(formattingChanged: formattingChanged)
    }

    /// The marketplace member is Clepso's only if it still names Clepso's folder; the plugin key is Clepso's whatever its value.
    func isOurMarketplace(_ value: Any?) -> Bool { (value as AnyObject?)?.isEqual(marketplaceObject) ?? false }

    func containsEntries(_ object: [String: Any]) -> Bool {
        isOurMarketplace((object[Self.marketplacesKey] as? [String: Any])?[Self.marketplaceName])
            || (object[Self.pluginsKey] as? [String: Any])?[Self.pluginID] != nil
    }

    /// Settings without Clepso's two members, editing bytes in place when the scanner can, else reformatting (and saying
    /// so). A key Clepso created goes too once empty. Nil when neither member is left.
    func removingEntries(_ original: [UInt8], object: [String: Any], record: Record) -> ([UInt8], Bool)? {
        guard containsEntries(object) else { return nil }
        var bytes = original
        var inPlace = true
        for (key, name, created) in [(Self.marketplacesKey, Self.marketplaceName, record.createdMarketplacesKey),
                                     (Self.pluginsKey, Self.pluginID, record.createdPluginsKey)] where inPlace {
            guard let document = JSONObjectLayout.parseDocument(bytes) else { inPlace = false; break }
            let members = document.members(named: key)
            guard !members.isEmpty else { continue }
            guard members.count == 1, let member = members.first else { inPlace = false; break }
            var i = member.valueStart
            guard let inner = JSONObjectLayout.parseObject(bytes, at: &i) else { inPlace = false; break }
            let ours = inner.members(named: name).filter { m in
                key == Self.pluginsKey || isOurMarketplace(FileOps.jsonObject(Array(bytes[m.valueStart..<m.valueEnd])))
            }
            guard ours.count <= 1 else { inPlace = false; break }
            if let entry = ours.first { bytes = inner.removingMember(entry) }
            if created, (FileOps.jsonObject(bytes)?[key] as? [String: Any])?.isEmpty == true,
               let doc = JSONObjectLayout.parseDocument(bytes), let emptied = doc.members(named: key).first {
                bytes = doc.removingMember(emptied)
            }
        }
        if inPlace, let after = FileOps.jsonObject(bytes), !containsEntries(after) { return (bytes, false) }

        // Fallback: rebuild from the parsed object.
        var updated = object
        for (key, name, created) in [(Self.marketplacesKey, Self.marketplaceName, record.createdMarketplacesKey),
                                     (Self.pluginsKey, Self.pluginID, record.createdPluginsKey)] {
            guard var inner = object[key] as? [String: Any] else { continue }
            if key == Self.pluginsKey || isOurMarketplace(inner[name]) { inner[name] = nil }
            updated[key] = inner.isEmpty && created ? nil : inner
        }
        return (FileOps.serialize(updated, pretty: true) + Array("\n".utf8), true)
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: marketplaceDir)
        try? FileManager.default.removeItem(at: script)
        try? FileManager.default.removeItem(at: recordURL)
    }

    // MARK: - The mod's files

    /// Every regular file of the bundled marketplace, by path relative to it. Links and anything else are refused, so
    /// what lands in Claude Code is exactly the reviewed source.
    func bundledFiles() throws -> [(path: String, bytes: [UInt8])] {
        guard FileOps.isRealDirectory(bundledMod),
              let walker = FileManager.default.enumerator(at: bundledMod, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey],
                                                          options: []) else { throw InstallError.bundleMissing }
        var files: [(String, [UInt8])] = []
        let base = bundledMod.resolvingSymlinksInPath().path
        for case let url as URL in walker {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey])
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true, values.isSymbolicLink != true, let bytes = FileOps.readBytes(url) else {
                throw InstallError.io("unexpected item in the bundled mod: \(url.lastPathComponent)")
            }
            let full = url.resolvingSymlinksInPath().path
            guard full.hasPrefix(base + "/") else { throw InstallError.bundleMissing }
            files.append((String(full.dropFirst(base.count + 1)), bytes))
        }
        let required = [".claude-plugin/marketplace.json", "plugins/\(Self.pluginName)/.claude-plugin/plugin.json",
                        "plugins/\(Self.pluginName)/hooks/hooks.json", "plugins/\(Self.pluginName)/hooks/register.js"]
        guard required.allSatisfy({ path in files.contains { $0.0 == path } }) else { throw InstallError.bundleMissing }
        return files.sorted { $0.0 < $1.0 }
    }

    /// A fresh copy of the marketplace: folders 0700, files 0600, then every file read back and compared.
    func copyMod(_ files: [(path: String, bytes: [UInt8])]) throws {
        try FileOps.ensureRealDirectory(paths.clepsoDir, mode: 0o700)
        if FileManager.default.fileExists(atPath: marketplaceDir.path) { try FileManager.default.removeItem(at: marketplaceDir) }
        try FileOps.ensureRealDirectory(marketplaceDir, mode: 0o700)
        for file in files {
            var directory = marketplaceDir
            for part in file.path.split(separator: "/").dropLast() {
                directory = directory.appendingPathComponent(String(part))
                try FileOps.ensureRealDirectory(directory, mode: 0o700)
            }
            try FileOps.atomicReplace(marketplaceDir.appendingPathComponent(file.path), with: file.bytes, mode: 0o600)
        }
        guard modMatchesBundle(files) else { throw InstallError.verificationFailed }
    }

    func modMatchesBundle(_ files: [(path: String, bytes: [UInt8])]) -> Bool {
        let installed = FileManager.default.enumerator(atPath: marketplaceDir.path)?.compactMap { $0 as? String }
            .filter { !FileOps.isRealDirectory(marketplaceDir.appendingPathComponent($0)) } ?? []
        return Set(installed) == Set(files.map(\.path))
            && files.allSatisfy { FileOps.readBytes(marketplaceDir.appendingPathComponent($0.path)) == $0.bytes }
    }

    func writeScript() throws {
        try FileOps.ensureRealDirectory(paths.clepsoDir, mode: 0o700)
        try FileOps.atomicReplace(script, with: Array(scriptText().utf8), mode: 0o700)
    }

    func scriptText() -> String {
        """
        #!/bin/sh
        # Clepso mod hand-off v1. Generated \(FileOps.basicISO8601(now())). Do not edit; Clepso regenerates it.
        # Run by Clepso's Claude Code mod in the desktop app and the VS Code panel: hands the helper limit and context
        # numbers on stdin; the helper checks every field and sends them to the app, never content.
        CLEPSO_SHIM=\(SettingsInstaller.singleQuoted(shimPath))
        if [ -x "$CLEPSO_SHIM" ]; then
          exec "$CLEPSO_SHIM" --mod
        fi
        exit 0

        """
    }

    // MARK: - Repair

    /// After the app moved, or an update brought a new version of the mod: rewrites the script and re-copies the mod.
    /// settings.json is neither read nor written (it names Clepso's folder, which doesn't move).
    public func repair() throws {
        guard isInstalled else { return }
        try writeScript()
        let files = try bundledFiles()
        if !modMatchesBundle(files) { try copyMod(files) }
    }

    public func needsRepair() -> Bool {
        guard isInstalled else { return false }
        let text = FileOps.readBytes(script).map { String(decoding: $0, as: UTF8.self) } ?? ""
        guard text.contains("CLEPSO_SHIM=\(SettingsInstaller.singleQuoted(shimPath))\n") else { return true }
        guard let files = try? bundledFiles() else { return false }      // no bundled copy to repair from
        return !modMatchesBundle(files)
    }
}
