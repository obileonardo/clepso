import Darwin
import Foundation
import ShimProtocol

/// Stand-in for the app's socket listener during the first capture (increment 0.6), before the app
/// exists. Same-user peers only, frames validated with the app's decoder, each saved as a file.
public final class FrameListener: @unchecked Sendable {   // immutable after init; run() owns the fd
    public enum ListenerError: Error, Equatable { case unsafePath(String), bind(Int32), pathTooLong }

    let socketPath: String
    let outputDirectory: URL
    private let fd: Int32

    /// Creates the socket's directory (0700) if needed, refuses symlinks, replaces only a stale socket.
    public init(socketPath: String, outputDirectory: URL) throws {
        self.socketPath = socketPath
        self.outputDirectory = outputDirectory
        let directory = (socketPath as NSString).deletingLastPathComponent
        var info = stat()
        if lstat(directory, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == getuid() else { throw ListenerError.unsafePath(directory) }
        } else {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        chmod(directory, 0o700)
        if lstat(socketPath, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFSOCK else { throw ListenerError.unsafePath(socketPath) }
            unlink(socketPath)
        }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])

        var address = sockaddr_un()
        let bytes = Array(socketPath.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { throw ListenerError.pathTooLong }
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 8) == 0 else { close(fd); throw ListenerError.bind(errno) }
        chmod(socketPath, 0o600)
    }

    deinit { close(fd); unlink(socketPath) }

    public struct Received {
        public let index: Int
        public let file: URL
        public let frame: JSONValue
    }

    /// Accepts connections until `limit` valid frames have been saved. Rejected connections are reported
    /// through `onRejected` and never saved.
    public func run(limit: Int, onFrame: (Received) -> Void, onRejected: (String) -> Void = { _ in }) {
        var saved = 0
        while saved < limit {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { if errno == EINTR { continue } else { return } }
            defer { close(client) }

            var uid: uid_t = 0, gid: gid_t = 0
            guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { onRejected("peer is another user"); continue }

            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while data.count <= FrameCodec.maxPayloadBytes + 4 {
                let n = read(client, &buffer, buffer.count)
                if n > 0 { data.append(buffer, count: n) } else if n < 0 && errno == EINTR { continue } else { break }
            }
            guard let frame = try? FrameCodec.decode(data) else { onRejected("invalid frame (\(data.count) bytes)"); continue }

            saved += 1
            let file = outputDirectory.appendingPathComponent(String(format: "frame-%03d.json", saved))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            if let body = try? encoder.encode(frame) {
                FileManager.default.createFile(atPath: file.path, contents: body + Data("\n".utf8),
                                               attributes: [.posixPermissions: 0o600])
            }
            onFrame(Received(index: saved, file: file, frame: frame))
        }
    }

    /// One readable line per frame for the terminal.
    public static func summary(_ frame: JSONValue) -> String {
        func show(_ path: [String], suffix: String = "%") -> String {
            switch frame.lookup(path) {
            case .value(.number(let n)): return (n.rounded() == n ? String(Int(n)) : String(format: "%.1f", n)) + suffix
            case .value(.string(let s)): return s
            case .null: return "null"
            case .absent: return "absent"
            default: return "?"
            }
        }
        return "model \(show(["model", "display_name"], suffix: "")) · ctx \(show(["context", "used_pct"])) · "
            + "5h \(show(["rate_limits", "five_hour", "used_pct"])) · 7d \(show(["rate_limits", "seven_day", "used_pct"])) · "
            + "claude code \(show(["source_version"], suffix: ""))"
    }
}

/// The capture shim (increment 0.6): saves the raw status-line stdin, then hands it to the unchanged
/// helper. It is a throwaway script, so no recording code ever exists in the shipped helper binary.
public enum CaptureShim {
    public static func script(helper: String, captureDirectory: String) -> String {
        func quoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        return """
        #!/bin/sh
        # Clepso capture shim (increment 0.6). Saves raw status-line stdin for one fixture capture, then runs
        # the helper. Raw captures contain paths and stay in this private folder; never commit them.
        umask 077
        mkdir -p \(quoted(captureDirectory))
        f=\(quoted(captureDirectory))/raw-$(date -u +%Y%m%dT%H%M%SZ)-$$.json
        tee "$f" | exec \(quoted(helper))

        """
    }
}
