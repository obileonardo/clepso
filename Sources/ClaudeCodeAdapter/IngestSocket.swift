import Darwin
import Domain
import Foundation
import ShimProtocol

/// Token bucket for frames per second (ARCHITECTURE §3: 20/s). Pure; time is passed in.
public struct TokenBucket: Sendable {
    public let capacity: Double
    public let refillPerSecond: Double
    private var tokens: Double
    private var last: TimeInterval?

    public init(capacity: Double = 20, refillPerSecond: Double = 20) {
        self.capacity = capacity
        self.refillPerSecond = refillPerSecond
        self.tokens = capacity
    }

    /// `now` is a monotonic time in seconds. Returns false when the bucket is empty.
    public mutating func take(at now: TimeInterval) -> Bool {
        if let last { tokens = min(capacity, tokens + (now - last) * refillPerSecond) }
        last = now
        guard tokens >= 1 - 1e-9 else { return false }   // tolerate float drift in elapsed time
        tokens -= 1
        return true
    }
}

/// The app's end of the status-line socket (ARCHITECTURE §3, PRIVACY_AND_SECURITY §3).
///
/// All mutable state is confined to `queue`, a private serial queue; that is what makes the
/// `@unchecked Sendable` sound. Frames that pass every check are published on `frames`.
public final class IngestSocket: @unchecked Sendable {
    public struct Health: Sendable, Equatable {
        public var accepted = 0
        public var rejectedPeer = 0          // another user's process
        public var rejectedFrame = 0         // not a valid frame v1
        public var oversize = 0              // over 4 KiB
        public var rateLimited = 0           // over 20 frames per second
        public init(accepted: Int = 0, rejectedPeer: Int = 0, rejectedFrame: Int = 0, oversize: Int = 0, rateLimited: Int = 0) {
            self.accepted = accepted
            self.rejectedPeer = rejectedPeer
            self.rejectedFrame = rejectedFrame
            self.oversize = oversize
            self.rateLimited = rateLimited
        }
    }

    public struct ReceivedFrame: Sendable {
        public let frame: JSONValue
        public let receivedAt: Date
    }

    public enum SocketError: Error, Equatable {
        case unsafeDirectory(String), unsafeSocketPath(String), pathTooLong, bind(Int32)
    }

    public let path: String
    public let frames: AsyncStream<ReceivedFrame>
    private let continuation: AsyncStream<ReceivedFrame>.Continuation
    private let queue = DispatchQueue(label: "clepso.ingest-socket")
    private let listenFD: Int32
    private let boundInode: ino_t
    private let wallClock: @Sendable () -> Date
    private let uptime: @Sendable () -> TimeInterval
    private var source: DispatchSourceRead?
    private var bucket = TokenBucket()
    private var health = Health()

    /// Binds immediately so permission or path problems surface at startup, not on the first event.
    public init(path: String, wallClock: @escaping @Sendable () -> Date = { SystemClock().now() },
                uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) throws {
        self.path = path
        self.wallClock = wallClock
        self.uptime = uptime
        (frames, continuation) = AsyncStream.makeStream(of: ReceivedFrame.self, bufferingPolicy: .bufferingNewest(256))

        let directory = (path as NSString).deletingLastPathComponent
        var info = stat()
        if lstat(directory, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == getuid() else { throw SocketError.unsafeDirectory(directory) }
        } else {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        chmod(directory, 0o700)
        // Only a stale socket may be replaced; a symlink or file at the path means something is wrong.
        if lstat(path, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFSOCK else { throw SocketError.unsafeSocketPath(path) }
            unlink(path)
        }

        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { throw SocketError.pathTooLong }
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 16) == 0 else {
            let code = errno
            close(fd)
            throw SocketError.bind(code)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        listenFD = fd
        var bound_ = stat()
        boundInode = lstat(path, &bound_) == 0 ? bound_.st_ino : 0
    }

    deinit {
        source?.cancel()
        close(listenFD)
        // Remove the socket file only if it is still ours: a newer listener may have replaced it.
        var info = stat()
        if lstat(path, &info) == 0, info.st_ino == boundInode { unlink(path) }
        continuation.finish()
    }

    public func start() {
        queue.sync {
            guard source == nil else { return }
            let source = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: queue)
            source.setEventHandler { [weak self] in self?.acceptPending() }
            source.resume()
            self.source = source
        }
    }

    public func stop() {
        queue.sync {
            source?.cancel()
            source = nil
        }
        continuation.finish()
    }

    public var currentHealth: Health { queue.sync { health } }

    // MARK: - On `queue`

    private func acceptPending() {
        while true {
            let client = accept(listenFD, nil, nil)
            if client < 0 { return }                       // EAGAIN: nothing more to accept
            handle(client)
            close(client)
        }
    }

    private func handle(_ client: Int32) {
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { health.rejectedPeer += 1; return }
        guard bucket.take(at: uptime()) else { health.rateLimited += 1; return }

        // Blocking read with a short timeout: the helper writes once and closes.
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
        var timeout = timeval(tv_sec: 0, tv_usec: 100_000)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var on: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        let limit = FrameCodec.maxPayloadBytes + 4
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count <= limit {
            let n = read(client, &buffer, buffer.count)
            if n > 0 { data.append(buffer, count: n) } else if n < 0 && errno == EINTR { continue } else { break }
        }
        // Oversize means more bytes actually arrived than a frame may have; junk whose length prefix
        // merely claims a large size is a malformed frame.
        guard data.count <= limit else { health.oversize += 1; return }
        guard let frame = try? FrameCodec.decode(data) else { health.rejectedFrame += 1; return }
        health.accepted += 1
        continuation.yield(ReceivedFrame(frame: frame, receivedAt: wallClock()))
    }
}

/// Where mapped batches go: the store in increment 1.2, a collector in tests.
public protocol IngestSink: Sendable {
    func ingest(_ batch: IngestBatch) async
    /// A hook event (agents per task, increment 1.9). `at` is when it happened: the helper's time when plausible.
    func ingest(hook: HookFrame.Decoded, at: Date) async
}

extension IngestSink {
    public func ingest(hook: HookFrame.Decoded, at: Date) async {}
}

/// Consumes received frames, maps them (DATA_MODEL §5.1) and hands each batch to the sink.
public actor Ingestor {
    public struct Counters: Sendable, Equatable {
        public var batches = 0
        public var unmappable = 0
        public var droppedSessionObservations = 0
        public var skewFlagged = 0
        /// From the newest frame: how many limit windows Claude Code sent that Clepso does not read.
        public var unknownRateLimitWindows = 0
        /// Hook events received (agents per task) and hook frames that failed validation.
        public var hookEvents = 0
        public var unreadableHooks = 0
        public init() {}
    }

    let connectionID: UUID
    let sink: any IngestSink
    public private(set) var counters = Counters()

    public init(connectionID: UUID, sink: any IngestSink) {
        self.connectionID = connectionID
        self.sink = sink
    }

    /// Runs until the stream finishes.
    public func consume(_ frames: AsyncStream<IngestSocket.ReceivedFrame>) async {
        for await received in frames {
            await ingest(received)
        }
    }

    public func ingest(_ received: IngestSocket.ReceivedFrame) async {
        if received.frame["kind"] == .string(HookFrame.kind) {
            guard let hook = HookFrame.decode(received.frame) else { counters.unreadableHooks += 1; return }
            counters.hookEvents += 1
            // The helper's clock orders events that arrive together; one far from arrival time is not trusted.
            let at = abs(hook.emittedAt.timeIntervalSince(received.receivedAt)) <= 300 ? hook.emittedAt : received.receivedAt
            await sink.ingest(hook: hook, at: at)
            return
        }
        guard let batch = FrameMapper.map(received.frame, connectionID: connectionID, receivedAt: received.receivedAt) else {
            counters.unmappable += 1
            return
        }
        counters.batches += 1
        counters.droppedSessionObservations += batch.droppedSessionObservations
        if batch.skewFlagged { counters.skewFlagged += 1 }
        counters.unknownRateLimitWindows = batch.unknownRateLimitWindows
        await sink.ingest(batch)
    }
}
