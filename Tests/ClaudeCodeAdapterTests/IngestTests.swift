import Darwin
import Domain
import Foundation
import ShimProtocol
import Testing
@testable import ClaudeCodeAdapter

let connection = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
let t0 = Date(timeIntervalSince1970: 1_792_159_200)

func frame(_ json: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)) }

let fullFrame = #"""
{"v":1,"kind":"claude_code.statusline","emitted_at_ms":1792159200000,"shim_version":"0.1.0","source_version":"2.1.302",
 "session_ref":"0123456789abcdef","model":{"id":"claude-opus-5-5","display_name":"Opus 5.5"},
 "context":{"window_size":1000000,"used_pct":73,"total_input_tokens":729769,
   "current_usage":{"input_tokens":2,"output_tokens":386,"cache_read_input_tokens":729359,"cache_creation_input_tokens":408}},
 "rate_limits":{"five_hour":{"used_pct":14,"resets_at":1792199400},"seven_day":{"used_pct":23.5,"resets_at":1792641600}},
 "cost_usd_estimate":0.0412,"health":{"scrub_count":0,"unknown_top_level_keys":1}}
"""#

func values(_ batch: IngestBatch, _ subject: SubjectKey, _ kind: MetricKind) -> [MetricValue] {
    batch.observations.filter { $0.subject == subject && $0.kind == kind }.map(\.value)
}
let fiveHour = SubjectKey.pool(providerPoolKey: "claude-code.rate_limits.five_hour")
let sevenDay = SubjectKey.pool(providerPoolKey: "claude-code.rate_limits.seven_day")

@Suite("FrameMapper: frame v1 to observations (DATA_MODEL §5.1)")
struct FrameMapperTests {
    @Test("A full frame maps every row of the table, with exact decimals")
    func fullFrameMaps() throws {
        let batch = try #require(FrameMapper.map(try frame(fullFrame), connectionID: connection, receivedAt: t0.addingTimeInterval(1)))
        let session = SubjectKey.session(sessionRef: "0123456789abcdef")
        #expect(values(batch, fiveHour, .quotaUsedPct) == [.percent(14)])
        #expect(values(batch, fiveHour, .resetAt) == [.instant(Date(timeIntervalSince1970: 1_792_199_400))])
        #expect(values(batch, sevenDay, .quotaUsedPct) == [.percent(Decimal(string: "23.5")!)])
        #expect(values(batch, session, .contextUsedPct) == [.percent(73)])
        #expect(values(batch, session, .contextTokens) == [.tokens(729_769)])
        #expect(values(batch, session, .contextWindowSize) == [.tokens(1_000_000)])
        #expect(values(batch, session, .cacheReadTokens) == [.tokens(729_359)])
        #expect(values(batch, session, .apiCostUSD) == [.usd(Decimal(string: "0.0412")!)], "money must not pick up float noise")
        #expect(batch.observations.count == 12)
        #expect(batch.observations.allSatisfy { $0.observedAt == t0 && $0.sourceVersion == "2.1.302" && $0.modelID == "claude-opus-5-5" })
        #expect(batch.observations.first { $0.kind == .apiCostUSD }?.quality == .estimated)
        #expect(batch.observations.first { $0.kind == .quotaUsedPct }?.quality == .reported)
        #expect(batch.unknownTopLevelKeys == 1 && !batch.skewFlagged)
    }

    @Test("Missing rate limits become recorded absences, never 0 (F06)")
    func absentRateLimits() throws {
        let batch = try #require(FrameMapper.map(try frame(#"{"v":1,"kind":"claude_code.statusline","emitted_at_ms":1792159200000,"session_ref":"s"}"#),
                                                 connectionID: connection, receivedAt: t0))
        for pool in [fiveHour, sevenDay] {
            #expect(values(batch, pool, .quotaUsedPct) == [.absent(.providerOmitted)])
            #expect(values(batch, pool, .resetAt) == [.absent(.providerOmitted)])
        }
        #expect(batch.observations.allSatisfy { $0.quality == .unknown })
        #expect(!batch.observations.contains { if case .percent(0) = $0.value { true } else { false } })
    }

    @Test("A provider null and a missing key stay different")
    func nullVersusMissing() throws {
        let batch = try #require(FrameMapper.map(try frame(#"""
            {"v":1,"kind":"claude_code.statusline","emitted_at_ms":1792159200000,"session_ref":"s",
             "context":{"used_pct":null,"current_usage":null},"rate_limits":{"five_hour":{"used_pct":null}}}
            """#), connectionID: connection, receivedAt: t0))
        let session = SubjectKey.session(sessionRef: "s")
        #expect(values(batch, fiveHour, .quotaUsedPct) == [.absent(.providerNull)])
        #expect(values(batch, fiveHour, .resetAt) == [.absent(.providerOmitted)])
        #expect(values(batch, session, .contextUsedPct) == [.absent(.providerNull)])
        #expect(values(batch, session, .requestInputTokens) == [.absent(.providerNull)])
        #expect(values(batch, session, .contextTokens).isEmpty, "a missing session field emits nothing")
    }

    @Test("Without a session reference, session observations are dropped and counted")
    func noSessionRef() throws {
        let batch = try #require(FrameMapper.map(try frame(#"""
            {"v":1,"kind":"claude_code.statusline","emitted_at_ms":1792159200000,"context":{"used_pct":40,"window_size":200000}}
            """#), connectionID: connection, receivedAt: t0))
        #expect(batch.droppedSessionObservations == 2)
        #expect(batch.observations.allSatisfy { if case .pool = $0.subject { true } else { false } })
    }

    @Test("Gateway spend limit is its own pool, only when present")
    func spendLimit() throws {
        let batch = try #require(FrameMapper.map(try frame(#"""
            {"v":1,"kind":"claude_code.statusline","emitted_at_ms":1792159200000,"rate_limits":{"spend_limit":{"used_pct":62.8,"resets_at":1792199400}}}
            """#), connectionID: connection, receivedAt: t0))
        let spend = SubjectKey.pool(providerPoolKey: "claude-code.rate_limits.spend_limit")
        #expect(values(batch, spend, .quotaUsedPct) == [.percent(Decimal(string: "62.8")!)])
        let plain = try #require(FrameMapper.map(try frame(fullFrame), connectionID: connection, receivedAt: t0))
        #expect(!plain.observations.contains { $0.subject == spend })
    }

    @Test("Dedupe keys: identical for a replayed frame, different when value, time or connection differ")
    func dedupeKeys() throws {
        let a = try #require(FrameMapper.map(try frame(fullFrame), connectionID: connection, receivedAt: t0))
        let replay = try #require(FrameMapper.map(try frame(fullFrame), connectionID: connection, receivedAt: t0.addingTimeInterval(30)))
        #expect(a.observations.map(\.dedupeKey) == replay.observations.map(\.dedupeKey), "receivedAt is not part of identity")
        let later = try #require(FrameMapper.map(try frame(fullFrame.replacingOccurrences(of: "1792159200000", with: "1792159201000")),
                                                 connectionID: connection, receivedAt: t0))
        #expect(Set(a.observations.map(\.dedupeKey)).isDisjoint(with: later.observations.map(\.dedupeKey)))
        let other = try #require(FrameMapper.map(try frame(fullFrame), connectionID: UUID(), receivedAt: t0))
        #expect(Set(a.observations.map(\.dedupeKey)).isDisjoint(with: other.observations.map(\.dedupeKey)))
        #expect(Set(a.observations.map(\.dedupeKey)).count == a.observations.count, "keys are unique within a frame")
    }

    @Test("Clock skew beyond 5 minutes is flagged")
    func skew() throws {
        let f = try frame(fullFrame)
        #expect(try #require(FrameMapper.map(f, connectionID: connection, receivedAt: t0.addingTimeInterval(299))).skewFlagged == false)
        #expect(try #require(FrameMapper.map(f, connectionID: connection, receivedAt: t0.addingTimeInterval(301))).skewFlagged)
        #expect(try #require(FrameMapper.map(f, connectionID: connection, receivedAt: t0.addingTimeInterval(-301))).skewFlagged)
    }
}

@Suite("Token bucket")
struct TokenBucketTests {
    @Test("20 per second: a burst of 20 passes, the 21st waits, refills over time")
    func rate() {
        var bucket = TokenBucket()
        func burst(_ n: Int, at time: TimeInterval) -> Int {
            var passed = 0
            for _ in 0..<n where bucket.take(at: time) { passed += 1 }
            return passed
        }
        #expect(burst(21, at: 100) == 20, "a burst of 20 passes, the 21st does not")
        #expect(burst(11, at: 100.5) == 10, "ten tokens refill in half a second")
        #expect(burst(25, at: 200) == 20, "refill is capped at the capacity")
    }
}

/// Writes raw bytes to a Unix socket the way a client would.
func sendRaw(_ path: String, _ bytes: Data) -> Bool { deliver(path, bytes) == .sent }

enum Delivery { case refused, connectedButWriteFailed, sent }

/// Like `sendRaw`, but says whether the connection was made: once connected, the listener has seen (and counted)
/// the frame even if it closed before our write landed, so only a refused connection may be retried.
func deliver(_ path: String, _ bytes: Data) -> Delivery {
    var address = sockaddr_un()
    let p = Array(path.utf8)
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { raw in raw.copyBytes(from: p); raw[p.count] = 0 }
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    defer { close(fd) }
    // Like the real helper: a peer that hangs up mid-write must not kill this process with SIGPIPE.
    var on: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    let ok = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard ok == 0 else { return .refused }
    return bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) } == bytes.count ? .sent : .connectedButWriteFailed
}

func waitFor(_ timeout: Double = 2, _ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
}

struct SocketSandbox {
    let dir: URL
    var path: String { dir.appendingPathComponent("run/agent.sock").path }
    init() { dir = FileManager.default.temporaryDirectory.appendingPathComponent("tk-ing-\(UUID().uuidString.prefix(8))") }
    func cleanUp() { try? FileManager.default.removeItem(at: dir) }
}

final class Collector: IngestSink, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [IngestBatch] = []
    func ingest(_ batch: IngestBatch) async { lock.withLock { stored.append(batch) } }
    var batches: [IngestBatch] { lock.withLock { stored } }
}

@Suite("IngestSocket", .serialized)
struct IngestSocketTests {
    @Test("Folder 0700 and socket 0600; a valid frame is received")
    func receivesFrame() throws {
        let box = SocketSandbox(); defer { box.cleanUp() }
        let socket = try IngestSocket(path: box.path, wallClock: { t0 })
        socket.start()
        let mode = { (p: String) -> Int in (try? FileManager.default.attributesOfItem(atPath: p)[.posixPermissions] as? Int) ?? -1 }
        #expect(mode((box.path as NSString).deletingLastPathComponent) == 0o700)
        #expect(mode(box.path) == 0o600)
        #expect(sendRaw(box.path, try FrameCodec.encode(try frame(fullFrame))))
        waitFor { socket.currentHealth.accepted == 1 }
        #expect(socket.currentHealth == IngestSocket.Health(accepted: 1))
    }

    @Test("Oversize, malformed and wrong-version frames are counted and dropped")
    func rejects() throws {
        let box = SocketSandbox(); defer { box.cleanUp() }
        let socket = try IngestSocket(path: box.path)
        socket.start()
        // 8 KiB: the app stops reading after 4 KiB and hangs up, so this write is cut short by design.
        _ = sendRaw(box.path, Data([0, 0, 0x20, 0]) + Data(repeating: 0x20, count: 8192))
        #expect(sendRaw(box.path, Data("garbage, not a frame".utf8)))
        #expect(sendRaw(box.path, try FrameCodec.encode(.object(["v": .number(2), "kind": .string(FrameBuilder.kind)]))))
        waitFor { socket.currentHealth.oversize + socket.currentHealth.rejectedFrame == 3 }
        #expect(socket.currentHealth.accepted == 0)
        #expect(socket.currentHealth.oversize == 1)
        #expect(socket.currentHealth.rejectedFrame == 2)
    }

    @Test("A flood is rate limited: with time frozen, exactly 20 of 60 frames are accepted")
    func flood() throws {
        let box = SocketSandbox(); defer { box.cleanUp() }
        let socket = try IngestSocket(path: box.path, uptime: { 100 })      // frozen: the bucket never refills
        socket.start()
        let wire = try FrameCodec.encode(try frame(fullFrame))
        for _ in 0..<60 {
            // A connection refused because the accept queue is momentarily full is retried; the real
            // helper would simply skip that frame and fail open. A connection that was made is never
            // retried: a rate-limited one is closed unread, and our write may lose that race.
            var attempts = 0
            while deliver(box.path, wire) == .refused && attempts < 200 { attempts += 1; Thread.sleep(forTimeInterval: 0.001) }
        }
        waitFor { let h = socket.currentHealth; return h.accepted + h.rateLimited == 60 }
        #expect(socket.currentHealth == IngestSocket.Health(accepted: 20, rateLimited: 40))
    }

    @Test("A symlink or a regular file at the socket path is refused; a stale socket is replaced")
    func pathSafety() throws {
        let box = SocketSandbox(); defer { box.cleanUp() }
        let run = (box.path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: run, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        let target = box.dir.appendingPathComponent("target").path
        FileManager.default.createFile(atPath: target, contents: Data("keep".utf8))
        try FileManager.default.createSymbolicLink(atPath: box.path, withDestinationPath: target)
        #expect(throws: IngestSocket.SocketError.unsafeSocketPath(box.path)) { try IngestSocket(path: box.path) }
        #expect(FileManager.default.contents(atPath: target) == Data("keep".utf8))
        try FileManager.default.removeItem(atPath: box.path)

        FileManager.default.createFile(atPath: box.path, contents: Data("file".utf8))
        #expect(throws: IngestSocket.SocketError.unsafeSocketPath(box.path)) { try IngestSocket(path: box.path) }
        try FileManager.default.removeItem(atPath: box.path)

        do { _ = try IngestSocket(path: box.path) }                      // leaves no socket after deinit
        let first = try IngestSocket(path: box.path)                    // a socket file now exists
        _ = first
        let second = try IngestSocket(path: box.path)                   // stale socket replaced, not refused
        second.start()
        #expect(sendRaw(box.path, try FrameCodec.encode(try frame(fullFrame))))
        waitFor { second.currentHealth.accepted == 1 }
        #expect(second.currentHealth.accepted == 1)
    }

    @Test("A symlinked socket folder is refused")
    func folderSafety() throws {
        let box = SocketSandbox(); defer { box.cleanUp() }
        try FileManager.default.createDirectory(at: box.dir.appendingPathComponent("real"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: box.dir.appendingPathComponent("run"), withDestinationURL: box.dir.appendingPathComponent("real"))
        #expect(throws: IngestSocket.SocketError.self) { try IngestSocket(path: box.path) }
    }

    @Test("Ingestor maps received frames and hands batches to the sink")
    func ingestorFlow() async throws {
        let box = SocketSandbox(); defer { box.cleanUp() }
        let socket = try IngestSocket(path: box.path, wallClock: { t0 })
        let collector = Collector()
        let ingestor = Ingestor(connectionID: connection, sink: collector)
        socket.start()
        let task = Task { await ingestor.consume(socket.frames) }
        #expect(sendRaw(box.path, try FrameCodec.encode(try frame(fullFrame))))
        waitFor { collector.batches.count == 1 }
        socket.stop()
        await task.value
        let batch = try #require(collector.batches.first)
        #expect(values(batch, fiveHour, .quotaUsedPct) == [.percent(14)])
        #expect(await ingestor.counters.batches == 1)
    }
}
