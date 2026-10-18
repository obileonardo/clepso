import Darwin
import Foundation

/// The rename from Pulse to Clepso moved the data folder, `~/Library/Application Support/Pulse` →
/// `.../Clepso`, and the database in it, `pulse.sqlite` (with `-wal`, `-shm`, `-journal` and the schema-migration
/// backups `pulse.sqlite.pre-*.bak`) → `clepso.sqlite`. Runs at launch before anything opens a file in the folder: the
/// database, the diagnostics log or the socket.
///
/// Every step is a `rename(2)` within one folder (one volume), so each file moves whole or not at all, and every step is
/// repeated at the next launch until it is done, so an interrupted launch is finished by the next one. Nothing is ever
/// renamed over an existing file: when the new folder already exists, the old one is left as it is (`keptBoth`); when
/// `clepso.sqlite` exists beside `pulse.sqlite`, both stay.
///
/// The database's companions move before the database itself: until the last rename `pulse.sqlite` is still there and
/// the next launch carries on. If a step fails the store must not be opened (`blocksStore`): a fresh `clepso.sqlite`
/// next to a moved `-wal` would read another database's log.
struct LegacyDataMigration {
    static let databaseName = "clepso.sqlite"
    static let legacyDatabaseName = "pulse.sqlite"
    static let companions = ["-wal", "-shm", "-journal"]

    enum Outcome: String, Sendable, Equatable {
        case nothingToDo
        case migrated            // the folder and/or the database files moved
        case keptBoth            // both folders exist: the new one is used, the old one is left in place
        case keptBothDatabases   // pulse.sqlite and clepso.sqlite are both in the folder: clepso.sqlite is used
        case legacyInUse         // another copy of the app still listens in the old folder: nothing moved, nothing opened
        case failed              // a rename failed: nothing more moved, and the store isn't opened

        /// The store stays closed this launch (the folder is in use or half-moved).
        var blocksStore: Bool { self == .legacyInUse || self == .failed }
    }

    let legacy: URL?
    let current: URL

    func run() -> Outcome {
        var outcome = Outcome.nothingToDo
        if let legacy, Self.isOwnDirectory(legacy) {
            if Self.exists(current) {
                outcome = .keptBoth
            } else {
                if Self.isListening(legacy.appendingPathComponent("run/agent.sock").path) { return .legacyInUse }
                try? FileManager.default.createDirectory(at: current.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard rename(legacy.path, current.path) == 0 else { return .failed }
                Self.syncDirectory(current.deletingLastPathComponent())
                outcome = .migrated
            }
        }
        switch renameDatabase() {
        case .migrated: return outcome == .keptBoth ? .keptBoth : .migrated
        case .nothingToDo: return outcome
        case let other: return other
        }
    }

    /// `pulse.sqlite*` → `clepso.sqlite*` inside the current folder.
    func renameDatabase() -> Outcome {
        let fm = FileManager.default
        let old = current.appendingPathComponent(Self.legacyDatabaseName), new = current.appendingPathComponent(Self.databaseName)
        var moved = false
        if Self.exists(old) {
            if Self.exists(new) { return .keptBothDatabases }
            for suffix in Self.companions where Self.exists(URL(fileURLWithPath: old.path + suffix)) {
                // A companion already at the new name belongs to a database that isn't there yet: never overwrite it.
                guard !Self.exists(URL(fileURLWithPath: new.path + suffix)) else { return .failed }
                guard rename(old.path + suffix, new.path + suffix) == 0 else { return .failed }
            }
            guard rename(old.path, new.path) == 0 else { return .failed }
            moved = true
        }
        // Schema-migration backups: `pulse.sqlite.pre-<migration>.bak`, which the store prunes by its own file name.
        let prefix = Self.legacyDatabaseName + ".pre-"
        for name in ((try? fm.contentsOfDirectory(atPath: current.path)) ?? []).sorted() where name.hasPrefix(prefix) && name.hasSuffix(".bak") {
            let target = current.appendingPathComponent(Self.databaseName + name.dropFirst(Self.legacyDatabaseName.count))
            guard !Self.exists(target) else { continue }
            guard rename(current.appendingPathComponent(name).path, target.path) == 0 else { return .failed }
            moved = true
        }
        if moved { Self.syncDirectory(current) }
        return moved ? .migrated : .nothingToDo
    }

    /// A real directory (not a symlink) owned by this user.
    static func isOwnDirectory(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR && info.st_uid == getuid()
    }

    static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    /// Whether an app is listening on the socket: a connect that succeeds. Sends nothing; a stale socket file refuses.
    static func isListening(_ path: String) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFSOCK else { return false }
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return false }
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        } == 0
    }

    static func syncDirectory(_ url: URL) {
        let fd = open(url.path, O_RDONLY)
        if fd >= 0 { fsync(fd); close(fd) }
    }
}
