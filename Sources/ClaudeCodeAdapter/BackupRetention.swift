import Foundation

/// Backups are kept for 30 days after a successful disconnect. Cleanup happens on a later launch of Clepso: no
/// background process survives an uninstall. Only the exact files recorded here, still byte-identical, are removed.
public struct BackupRetention: Sendable {
    public let paths: SettingsInstaller.Paths
    public init(paths: SettingsInstaller.Paths) { self.paths = paths }
    private var marker: URL { paths.backupsDir.appendingPathComponent("expiry.json") }
    private struct Entry: Codable { let name: String; let hash: String }
    private struct Record: Codable { let expiresAt: Date; let entries: [Entry] }

    public func markDisconnected(at now: Date) throws {
        guard FileOps.isRealDirectory(paths.backupsDir) else { return }
        let names = try FileManager.default.contentsOfDirectory(atPath: paths.backupsDir.path)
        let entries = names.sorted().compactMap { name -> Entry? in
            guard Self.ownedName(name), let bytes = try? FileOps.readNoFollow(paths.backupsDir.appendingPathComponent(name))?.bytes else { return nil }
            return Entry(name: name, hash: FileOps.sha256(bytes))
        }
        let data = try JSONEncoder().encode(Record(expiresAt: now.addingTimeInterval(30 * 86_400), entries: entries))
        // Refuse a symlink before writing, then use the same atomic writer as the settings installer.
        _ = try FileOps.readNoFollow(marker)
        try FileOps.atomicReplace(marker, with: Array(data), mode: 0o600)
    }

    @discardableResult
    public func purgeExpired(at now: Date) throws -> Int {
        // A new connection may need any backup in this folder. Even a broken helper-folder symlink blocks cleanup.
        guard (try? FileManager.default.attributesOfItem(atPath: paths.clepsoDir.path)) == nil,
              FileOps.isRealDirectory(paths.backupsDir),
              let bytes = try FileOps.readNoFollow(marker)?.bytes,
              let record = try? JSONDecoder().decode(Record.self, from: Data(bytes)),
              record.expiresAt <= now else { return 0 }
        var removed = 0
        for entry in record.entries where Self.ownedName(entry.name) {
            let file = paths.backupsDir.appendingPathComponent(entry.name)
            guard let actual = try? FileOps.readNoFollow(file)?.bytes, FileOps.sha256(actual) == entry.hash else { continue }
            try FileManager.default.removeItem(at: file)
            removed += 1
        }
        try FileManager.default.removeItem(at: marker)
        if (try? FileManager.default.contentsOfDirectory(atPath: paths.backupsDir.path))?.isEmpty == true {
            try FileManager.default.removeItem(at: paths.backupsDir)
        }
        return removed
    }

    private static func ownedName(_ name: String) -> Bool {
        name == "manifest.jsonl" || (name.hasPrefix("settings.json.") && name.hasSuffix(".bak")
            && name.utf8.count < 200 && name.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-").contains($0) })
    }
}
