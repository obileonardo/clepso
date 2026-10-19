import Darwin
import Foundation
import ShimProtocol

/// The status-line helper's run loop (ARCHITECTURE §3).
///
/// Order matters: the user's original command starts before any parsing, its stdout is inherited
/// directly (never buffered or rewritten), and every failure in the frame path falls through to
/// waiting for the child. No disk writes, no network, no Swift concurrency runtime.
public enum StatusLineShim {
    public static let version = "0.1.0"
    static let stdinCeiling = 1 << 20                   // read at most 1 MiB; the rest never reaches the child
    static let parseDeadlineNs: UInt64 = 10_000_000     // T0 + 10 ms
    static let connectBudgetNs: UInt64 = 20_000_000     // ≤ 20 ms for connect
    static let connectCeilingNs: UInt64 = 45_000_000    // and never past T0 + 45 ms
    static let writeCeilingNs: UInt64 = 48_000_000      // T0 + 48 ms

    struct Config: Decodable {
        let v: Int
        let socket: String
        let originalCommand: String?
        let forwardCost: Bool?
        let hmacKeyFile: String?
        /// Custom agent names the user approved in Settings (hook mode only). A missing or malformed list is empty, never
        /// a reason to drop the whole config: the status line must keep working whatever this field holds.
        let approvedAgentTypes: [String]

        enum CodingKeys: String, CodingKey {
            case v, socket
            case originalCommand = "original_command"
            case forwardCost = "forward_cost"
            case hmacKeyFile = "hmac_key_file"
            case approvedAgentTypes = "approved_agent_types"
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            v = try c.decode(Int.self, forKey: .v)
            socket = try c.decode(String.self, forKey: .socket)
            originalCommand = try c.decodeIfPresent(String.self, forKey: .originalCommand)
            forwardCost = try c.decodeIfPresent(Bool.self, forKey: .forwardCost)
            hmacKeyFile = try c.decodeIfPresent(String.self, forKey: .hmacKeyFile)
            approvedAgentTypes = (try? c.decodeIfPresent([String].self, forKey: .approvedAgentTypes)) ?? []
        }
    }

    /// Returns the process exit status. `environment` is injectable for tests.
    public static func main(environment: [String: String] = ProcessInfo.processInfo.environment) -> Int32 {
        let t0 = now()
        signal(SIGPIPE, SIG_IGN)
        installForwardingHandlers()

        let config = environment["HOME"].flatMap { loadConfig(home: $0) }
        let (stdin, truncated) = readStdin(ceiling: stdinCeiling)

        var child: pid_t = 0
        if let command = config?.originalCommand {
            child = spawnOriginal(command, stdin: stdin, environment: environment) ?? 0
            childPIDForSignals = child
        }

        // Everything below runs while the child produces its output; nothing here may block it.
        var frame: JSONValue?
        if let config {
            let key = config.hmacKeyFile.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
            let options = FrameBuilder.Options(shimVersion: version, forwardCost: config.forwardCost ?? true,
                                               hmacKey: key?.count == 32 ? key : nil,
                                               originalPresent: config.originalCommand != nil, truncated: truncated)
            let scale = budgetScale(environment)
            if case .frame(let built) = FrameBuilder.build(stdin: stdin, now: wallClock(environment), options: options),
               now() - t0 <= parseDeadlineNs * scale {
                frame = built
                if let wire = try? FrameCodec.encode(built) {
                    _ = send(wire, socketPath: config.socket, t0: t0, scale: scale)
                }
            }
        }

        if child > 0 { return waitForChild(child) }
        if config != nil, config?.originalCommand == nil, let frame {
            writeStdout(ownLine(frame, columns: Int(environment["COLUMNS"] ?? "") ?? 80))
        }
        return 0
    }

    // MARK: - Hook mode (increment 1.9)

    /// One Claude Code hook event: read stdin to the end (so Claude Code never sees a broken pipe), send the
    /// allowlisted frame, and exit 0 with nothing on stdout or stderr. A hook's output can change what Claude Code
    /// does (exit 2 blocks; stdout can become context), so this path has no other outcome, whatever happens.
    public static func hookMain(environment: [String: String] = ProcessInfo.processInfo.environment) -> Int32 {
        signal(SIGPIPE, SIG_IGN)
        let (stdin, truncated) = readStdin(ceiling: HookFrame.maxParsedStdinBytes)
        if truncated { drainStdin() }
        guard !truncated, let config = environment["HOME"].flatMap({ loadConfig(home: $0) }) else { return 0 }
        let key = config.hmacKeyFile.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
        let approved = Set(config.approvedAgentTypes.prefix(HookFrame.maxApprovedAgentNames))
        if case .frame(let frame) = HookFrame.build(stdin: stdin, now: wallClock(environment), shimVersion: version,
                                                    hmacKey: key?.count == 32 ? key : nil, approvedAgentTypes: approved),
           let wire = try? FrameCodec.encode(frame) {
            _ = send(wire, socketPath: config.socket, t0: now(), scale: budgetScale(environment))   // budget starts once parsed
        }
        return 0
    }

    /// Reads and discards whatever is left on stdin.
    static func drainStdin() {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = read(STDIN_FILENO, &buffer, buffer.count)
            if n > 0 { continue }
            if n < 0 && errno == EINTR { continue }
            return
        }
    }

    // MARK: - Config and stdin

    static func loadConfig(home: String) -> Config? {
        let url = URL(fileURLWithPath: home).appendingPathComponent(".claude/clepso/config.json")
        guard let data = try? Data(contentsOf: url), let config = try? JSONDecoder().decode(Config.self, from: data),
              config.v == 1 else { return nil }
        return config
    }

    static func readStdin(ceiling: Int) -> (Data, truncated: Bool) {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while data.count <= ceiling {
            let n = read(STDIN_FILENO, &buffer, buffer.count)
            if n > 0 {
                data.append(buffer, count: n)
            } else if n < 0 && errno == EINTR {
                continue
            } else {
                break
            }
        }
        if data.count > ceiling { return (data.prefix(ceiling), true) }
        return (data, false)
    }

    // MARK: - Child process

    /// Starts `/bin/sh -c command` with the raw stdin bytes on a pipe. stdout and stderr are inherited,
    /// so the child's output reaches Claude Code exactly as if we were not here.
    static func spawnOriginal(_ command: String, stdin: Data, environment: [String: String]) -> pid_t? {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { return nil }
        let (readEnd, writeEnd) = (fds[0], fds[1])

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, readEnd, STDIN_FILENO)
        posix_spawn_file_actions_addclose(&actions, readEnd)
        posix_spawn_file_actions_addclose(&actions, writeEnd)

        // The child gets the default SIGPIPE disposition, as it would under Claude Code directly.
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var defaults = sigset_t()
        sigemptyset(&defaults)
        sigaddset(&defaults, SIGPIPE)
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGDEF))

        // Typed explicitly: Swift 6.3 (CodeQL's newest supported compiler) can't infer the element type of `map + [nil]`.
        let arguments: [String] = ["/bin/sh", "-c", command]
        let argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, "/bin/sh", &actions, &attributes, argv, envp)
        close(readEnd)
        guard rc == 0 else {
            close(writeEnd)
            return nil
        }

        // An empty pipe takes 16 KiB without blocking; larger inputs go through a thread so a child
        // that never reads stdin cannot stall us.
        if stdin.count <= 16 * 1024 {
            writeAll(stdin, to: writeEnd)
            close(writeEnd)
        } else {
            let thread = Thread {
                writeAll(stdin, to: writeEnd)
                close(writeEnd)
            }
            thread.start()
        }
        return pid
    }

    static func writeAll(_ data: Data, to fd: Int32) {
        data.withUnsafeBytes { raw in
            guard var pointer = raw.baseAddress else { return }
            var remaining = raw.count
            while remaining > 0 {
                let n = write(fd, pointer, remaining)
                if n > 0 {
                    pointer += n
                    remaining -= n
                } else if n < 0 && errno == EINTR {
                    continue
                } else {
                    return                                   // EPIPE: the child stopped reading
                }
            }
        }
    }

    static func waitForChild(_ pid: pid_t) -> Int32 {
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0 {
            if errno != EINTR { return 0 }
        }
        let signal = status & 0x7f
        return signal == 0 ? (status >> 8) & 0xff : 128 + signal
    }

    // MARK: - Socket

    /// Non-blocking connect and write within the ARCHITECTURE §3 budget. Never reads a reply, never retries.
    @discardableResult
    static func send(_ wire: Data, socketPath: String, t0: UInt64, scale: UInt64 = 1) -> Bool {
        var info = stat()
        guard lstat(socketPath, &info) == 0, (info.st_mode & S_IFMT) == S_IFSOCK else { return false }

        var address = sockaddr_un()
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return false }
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
            raw[pathBytes.count] = 0
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if connected != 0 {
            guard errno == EINPROGRESS else { return false }
            let connectDeadline = min(now() + connectBudgetNs * scale, t0 + connectCeilingNs * scale)
            guard waitWritable(fd, until: connectDeadline) else { return false }
            var error: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0, error == 0 else { return false }
        }

        return wire.withUnsafeBytes { raw -> Bool in
            guard var pointer = raw.baseAddress else { return false }
            var remaining = raw.count
            while remaining > 0 {
                let n = write(fd, pointer, remaining)
                if n > 0 {
                    pointer += n
                    remaining -= n
                } else if n < 0 && (errno == EAGAIN || errno == EINTR) {
                    guard waitWritable(fd, until: t0 + writeCeilingNs * scale) else { return false }
                } else {
                    return false
                }
            }
            return true
        }
    }

    static func waitWritable(_ fd: Int32, until deadline: UInt64) -> Bool {
        while true {
            let current = now()
            guard current < deadline else { return false }
            var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let timeoutMs = Int32(max(1, (deadline - current) / 1_000_000))
            let ready = poll(&descriptor, 1, timeoutMs)
            if ready > 0 { return descriptor.revents & Int16(POLLOUT) != 0 }
            if ready == 0 { return false }
            if errno != EINTR { return false }
        }
    }

    // MARK: - Own line when the user had no status line (§2.2)

    static func ownLine(_ frame: JSONValue, columns: Int) -> String {
        func percent(_ path: [String]) -> String? {
            switch frame.lookup(path) {
            case .value(.number(let n)): n.rounded() == n ? "\(Int(n))%" : String(format: "%.1f%%", n)
            case .null: "—"
            default: nil
            }
        }
        var parts: [String] = []
        if case .value(.string(let model)) = frame.lookup(["model", "display_name"]) { parts.append("[\(model)]") }
        parts.append("ctx \(percent(["context", "used_pct"]) ?? "—")")
        if let fiveHour = percent(["rate_limits", "five_hour", "used_pct"]) { parts.append("5h \(fiveHour)") }
        if let sevenDay = percent(["rate_limits", "seven_day", "used_pct"]) { parts.append("7d \(sevenDay)") }
        if let spend = percent(["rate_limits", "spend_limit", "used_pct"]) { parts.append("spend \(spend)") }
        let line = parts.joined(separator: " · ")
        return String(line.prefix(max(columns, 1))) + "\n"
    }

    static func writeStdout(_ text: String) {
        writeAll(Data(text.utf8), to: STDOUT_FILENO)   // EPIPE (Claude Code cancelled us) is ignored
    }

    static func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }

    /// Wall clock for `emitted_at_ms` and the `resets_at` transport bound. Debug builds accept
    /// `CLEPSO_SHIM_NOW_MS` so fixtures with fixed dates stay valid; release builds ignore it.
    static func wallClock(_ environment: [String: String]) -> Date {
        #if DEBUG
        if let ms = environment["CLEPSO_SHIM_NOW_MS"].flatMap(Double.init) {
            return Date(timeIntervalSince1970: ms / 1000)
        }
        #endif
        return Date()
    }

    /// Multiplies every deadline above. Debug builds accept `CLEPSO_SHIM_RELAXED_BUDGET=1` (×100: parse 1 s, write 4.8 s)
    /// so tests about what a frame carries don't fail when a busy host misses the real-time budget; the tests about the
    /// budget itself and every release build use the real one.
    static func budgetScale(_ environment: [String: String]) -> UInt64 {
        #if DEBUG
        if environment["CLEPSO_SHIM_RELAXED_BUDGET"] == "1" { return 100 }
        #endif
        return 1
    }
}

// MARK: - Signal forwarding (§5)

/// Read only from the signal handler; written once, before any signal can be forwarded.
nonisolated(unsafe) var childPIDForSignals: pid_t = 0

private func forwardSignalAndExit(_ signal: Int32) {
    let pid = childPIDForSignals
    if pid > 0 { kill(pid, signal) }
    _exit(128 + signal)
}

private func installForwardingHandlers() {
    for sig in [SIGTERM, SIGINT, SIGHUP] { signal(sig, forwardSignalAndExit) }
}
