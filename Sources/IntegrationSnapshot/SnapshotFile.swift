import Darwin
import Foundation

/// Private, fixed-name files. Directory descriptors prevent symlink substitution between validation and use.
public struct SnapshotFile: Sendable {
    public enum Failure: Error { case unsafeFile, unavailable, invalid }
    public let directory: URL
    public init(dataDirectory: URL) { directory = dataDirectory.appendingPathComponent("integrations", isDirectory: true) }
    public static func validClient(_ name: String) -> Bool {
        (1...48).contains(name.utf8.count) && name.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
    }
    private func openDirectory(create: Bool) throws -> Int32 {
        if create { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.unavailable }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { close(fd); throw Failure.unsafeFile }
        return fd
    }
    private func read(_ name: String) throws -> Data {
        let dir = try openDirectory(create: false); defer { close(dir) }
        let fd = openat(dir, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw Failure.unavailable }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
              info.st_mode & 0o077 == 0, info.st_size <= 131_072 else { throw Failure.unsafeFile }
        guard let data = try handle.read(upToCount: 131_073), data.count <= 131_072 else { throw Failure.invalid }
        return data
    }
    private func write(_ data: Data, name: String) throws {
        let dir = try openDirectory(create: true); defer { close(dir) }
        let temporary = ".\(UUID().uuidString).tmp"
        let fd = openat(dir, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Failure.unavailable }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { unlinkat(dir, temporary, 0) }
        try handle.write(contentsOf: data); try handle.synchronize()
        guard renameat(dir, temporary, dir, name) == 0 else { throw Failure.unavailable }
    }
    public func publish(_ snapshot: UsageSnapshot) throws {
        guard snapshot.valid else { throw Failure.invalid }
        try write(UsageSnapshot.encoder().encode(snapshot), name: "usage.v1.json")
    }
    public func load() throws -> UsageSnapshot {
        let snapshot = try UsageSnapshot.decoder().decode(UsageSnapshot.self, from: read("usage.v1.json"))
        guard snapshot.valid else { throw Failure.invalid }; return snapshot
    }
    public func setClients(_ names: [String]) throws {
        guard names.count <= 16, names.allSatisfy(Self.validClient) else { throw Failure.invalid }
        try write(JSONEncoder().encode(Array(Set(names)).sorted()), name: "mcp-clients.json")
    }
    public func allows(_ name: String) -> Bool {
        Self.validClient(name) && clients().contains(name)
    }
    public func clients() -> [String] {
        guard let data = try? read("mcp-clients.json"), let names = try? JSONDecoder().decode([String].self, from: data),
              names.count <= 16, names.allSatisfy(Self.validClient) else { return [] }
        return Array(Set(names)).sorted()
    }
    public func removeSnapshot() throws {
        var info = stat()
        if lstat(directory.path, &info) != 0, errno == ENOENT { return }
        let dir = try openDirectory(create: false); defer { close(dir) }
        if unlinkat(dir, "usage.v1.json", 0) != 0 && errno != ENOENT { throw Failure.unavailable }
    }
    public func revokeAndRemove() throws {
        try setClients([])
        try removeSnapshot()
    }
}
