import Darwin
import Foundation

/// Runs the real `clepso-statusline` binary as Claude Code would: stdin JSON in, stdout captured,
/// with HOME pointed at a throwaway folder so the real ~/.claude is never read or written.
struct ShimHarness {
    let home: URL
    let socketPath: String

    static let shimURL: URL = {
        if let bundle = Bundle.allBundles.first(where: { $0.bundlePath.hasSuffix(".xctest") }) {
            let candidate = bundle.bundleURL.deletingLastPathComponent().appendingPathComponent("clepso-statusline")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        // Swift Testing runs without the .xctest bundle in `allBundles`: take the helper built in this test run's
        // configuration, so `make perf` (release) times the release helper, not a stale debug one.
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/\(configuration)/clepso-statusline")
    }()

    /// A short directory name keeps the socket path under the 104-byte `sun_path` limit.
    init() throws {
        signal(SIGPIPE, SIG_IGN)
        let short = String(UUID().uuidString.prefix(8))
        home = FileManager.default.temporaryDirectory.appendingPathComponent("tk-\(short)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude/clepso"),
                                                withIntermediateDirectories: true)
        socketPath = home.appendingPathComponent("a.sock").path
    }

    func cleanUp() { try? FileManager.default.removeItem(at: home) }

    /// `approvedAgentTypes`: the `approved_agent_types` value as written (any JSON, to test malformed ones); nil leaves it out.
    func writeConfig(originalCommand: String?, forwardCost: Bool = true, withKey: Bool = true, approvedAgentTypes: Any? = nil) throws {
        let keyPath = home.appendingPathComponent(".claude/clepso/session.key").path
        if withKey { try Data(repeating: 7, count: 32).write(to: URL(fileURLWithPath: keyPath)) }
        var config: [String: Any] = ["v": 1, "socket": socketPath, "forward_cost": forwardCost, "hmac_key_file": keyPath]
        config["original_command"] = originalCommand ?? NSNull()
        if let approvedAgentTypes { config["approved_agent_types"] = approvedAgentTypes }
        let data = try JSONSerialization.data(withJSONObject: config)
        try data.write(to: home.appendingPathComponent(".claude/clepso/config.json"))
    }

    struct Result {
        let stdout: Data
        let status: Int32
        let seconds: Double
        var text: String { String(decoding: stdout, as: UTF8.self) }
    }

    /// `afterLaunch` runs once the process has started (used to send signals). `realBudget: false` (the default) relaxes
    /// the helper's real-time deadlines, so a busy host can't drop the frame a content test is waiting for; tests of the
    /// budget itself pass `true`.
    /// Fixture clock: 2026-10-16T14:00:00Z, so fixed reset times stay inside the transport bound.
    static let fixtureNowMs: Int64 = 1_792_159_200_000

    func run(stdin: Data, executable: URL = ShimHarness.shimURL, arguments: [String] = [],
             nowMs: Int64 = ShimHarness.fixtureNowMs, realBudget: Bool = false,
             afterLaunch: ((Process) -> Void)? = nil) throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin", "COLUMNS": "80", "CLEPSO_SHIM_NOW_MS": String(nowMs)]
            .merging(realBudget ? [:] : ["CLEPSO_SHIM_RELAXED_BUDGET": "1"]) { $1 }
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let start = DispatchTime.now().uptimeNanoseconds
        try process.run()
        afterLaunch?(process)
        let writer = Thread {
            try? input.fileHandleForWriting.write(contentsOf: stdin)   // EPIPE once the reader stops is expected
            try? input.fileHandleForWriting.close()
        }
        writer.start()
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        return Result(stdout: stdout, status: process.terminationStatus, seconds: seconds)
    }
}

/// Stand-in for the app's listener: accepts connections and records what each one sent.
final class FakeAgent: @unchecked Sendable {
    enum Mode { case readAll, acceptAndHang }

    private let lock = NSLock()
    private var received: [Data] = []
    private var held: [Int32] = []
    private let fd: Int32

    init(path: String, mode: Mode) throws {
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 8) == 0 else { throw POSIXError(.EADDRINUSE) }
        let listener = fd
        Thread { [self] in
            while true {
                let client = accept(listener, nil, nil)
                if client < 0 { return }
                switch mode {
                case .acceptAndHang:
                    lock.withLock { held.append(client) }
                case .readAll:
                    var data = Data()
                    var buffer = [UInt8](repeating: 0, count: 8192)
                    while true {
                        let n = read(client, &buffer, buffer.count)
                        if n <= 0 { break }
                        data.append(buffer, count: n)
                    }
                    close(client)
                    lock.withLock { received.append(data) }
                }
            }
        }.start()
    }

    var frames: [Data] { lock.withLock { received } }

    /// Whether `count` connections have been read within `timeout` seconds. Records no issue: callers decide.
    func waitForFrames(_ count: Int, timeout: Double) -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1e9)
        while frames.count < count {
            if DispatchTime.now().uptimeNanoseconds > deadline { return false }
            usleep(500)
        }
        return true
    }

    func stop() {
        close(fd)
        lock.withLock { held.forEach { close($0) } }
    }
}
