import Darwin
import Foundation

/// Fixed-location, bounded, read-only scanner. No configuration/credential files, arbitrary paths or networking.
public struct GeminiReader: Sendable {
    public static let maxFiles = 16
    public static let maxCandidates = 512
    struct Cached: Sendable { let size: Int; let modified: Date; let result: GeminiRecording.Result? }
    var cache: [String: Cached] = [:]
    public init() {}
    public static func roots(home: URL) -> [URL] {
        [home.appendingPathComponent(".gemini/tmp"), home.appendingPathComponent(".cache/.gemini/tmp")]
    }
    public static func isPresent(home: URL) -> Bool { roots(home: home).contains { FileManager.default.fileExists(atPath: $0.path) } }

    public mutating func scan(home: URL, now: Date) -> RecordedUsage? {
        let fm = FileManager.default
        var candidates: [(URL, Int, Date)] = [], incomplete = false
        var totalVisited = 0
        rootsLoop: for root in Self.roots(home: home) {
            // Resolve provider-controlled directories only when they contain no symlink components below HOME.
            guard safe(root, home: home), let projects = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            if projects.count > 256 { incomplete = true }
            for project in projects.sorted(by: { $0.path < $1.path }).prefix(256) {
                let chats = project.appendingPathComponent("chats")
                guard safe(chats, home: home), let walker = fm.enumerator(at: chats, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { continue }
                var visited = 0
                for case let file as URL in walker {
                    visited += 1
                    totalVisited += 1
                    if totalVisited > 4096 { incomplete = true; break rootsLoop }
                    guard visited <= Self.maxCandidates else { incomplete = true; break }
                    let relativeDepth = file.pathComponents.count - chats.pathComponents.count
                    if relativeDepth > 2 { walker.skipDescendants(); continue }
                    guard let info = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]), info.isSymbolicLink != true else { walker.skipDescendants(); continue }
                    guard info.isRegularFile == true, ["json", "jsonl"].contains(file.pathExtension),
                          relativeDepth == 2 || file.lastPathComponent.hasPrefix("session-") else { continue }
                    // A migrated JSONL recording supersedes its old JSON counterpart.
                    if file.pathExtension == "json", fm.fileExists(atPath: file.path + "l") { continue }
                    guard let size = info.fileSize, size <= GeminiRecording.maxBytes, let at = info.contentModificationDate else { incomplete = true; continue }
                    candidates.append((file, size, at))
                }
            }
        }
        candidates.sort { ($0.2, $1.0.path) > ($1.2, $0.0.path) }
        if candidates.count > Self.maxFiles { incomplete = true }
        var next: [String: Cached] = [:], records: [GeminiRecording.Result] = []
        for (file, size, modified) in candidates.prefix(Self.maxFiles) {
            let cached: Cached
            if let old = cache[file.path], old.size == size, old.modified == modified { cached = old }
            else {
                let result = read(file, home: home).flatMap { GeminiRecording.parse($0, legacy: file.pathExtension == "json", now: now) }
                cached = Cached(size: size, modified: modified, result: result)
            }
            next[file.path] = cached
            if let result = cached.result { records.append(result) } else { incomplete = true }
        }
        cache = next
        return GeminiRecording.project(records, incomplete: incomplete)
    }

    func safe(_ path: URL, home: URL) -> Bool {
        let expected = path.standardizedFileURL.path
        let base = home.standardizedFileURL.path
        guard expected.hasPrefix(base + "/") else { return false }
        // HOME itself may legitimately be on an external volume; resolve it as the trusted root.
        let actual = path.resolvingSymlinksInPath().path
        let relative = String(expected.dropFirst(base.count))
        return actual == home.resolvingSymlinksInPath().path + relative
    }
    func read(_ file: URL, home: URL) -> Data? {
        let components = file.standardizedFileURL.pathComponents.dropFirst(home.standardizedFileURL.pathComponents.count)
        guard let leaf = components.last else { return nil }
        var directory = Darwin.open(home.resolvingSymlinksInPath().path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard directory >= 0 else { return nil }
        defer { Darwin.close(directory) }
        for component in components.dropLast() {
            let next = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { return nil }
            Darwin.close(directory); directory = next
        }
        let descriptor = openat(directory, leaf, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG,
              status.st_uid == getuid(), status.st_size >= 0, status.st_size <= GeminiRecording.maxBytes else { return nil }
        var output = Data(), buffer = [UInt8](repeating: 0, count: 32 * 1024)
        while output.count <= GeminiRecording.maxBytes {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count == 0 { return output }
            if count < 0 { if errno == EINTR { continue }; return nil }
            output.append(contentsOf: buffer.prefix(count))
        }
        return nil
    }
}
