import Foundation
import Testing
import ShimProtocol
import FixtureTools

/// The exact increment 0.6 sequence, rehearsed in a throwaway HOME: `clepso install` (preview, then
/// confirm), capture shim → real helper → listener, scrub, `clepso uninstall`. The real run differs only
/// in HOME and in who sends the status-line events (Claude Code instead of this test).
@Suite("0.6 rehearsal in a throwaway home", .serialized)
struct CaptureRehearsalTests {
    static let clepsoURL = ShimHarness.shimURL.deletingLastPathComponent().appendingPathComponent("clepso")

    func clepso(_ arguments: [String], home: URL) throws -> (String, Int32) {
        let process = Process()
        process.executableURL = Self.clepsoURL
        process.arguments = arguments
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (text, process.terminationStatus)
    }

    @Test("Preview touches nothing; capture, scrub and uninstall leave settings byte-identical")
    func rehearsal() throws {
        let h = try ShimHarness(); defer { h.cleanUp() }
        let fm = FileManager.default
        try fm.removeItem(at: h.home.appendingPathComponent(".claude/clepso"))
        let settings = h.home.appendingPathComponent(".claude/settings.json")
        // Shaped like this Mac's real settings: valid JSON, no statusLine.
        let original = Data("{\n  \"model\": \"opus\",\n  \"permissions\": {\n    \"allow\": [\"Bash(git status)\"]\n  }\n}\n".utf8)
        try original.write(to: settings)

        // 1. Capture shim around the real helper.
        let captures = h.home.appendingPathComponent(".clepso/captures")
        let captureShim = h.home.appendingPathComponent(".clepso/capture-shim.sh")
        try fm.createDirectory(at: captureShim.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(CaptureShim.script(helper: ShimHarness.shimURL.path, captureDirectory: captures.path).utf8).write(to: captureShim)
        chmod(captureShim.path, 0o700)

        // 2. Preview changes nothing.
        let (preview, previewStatus) = try clepso(["install", "--shim", captureShim.path, "--socket", h.socketPath], home: h.home)
        #expect(previewStatus == 0 && preview.contains("Preview only"))
        #expect(try Data(contentsOf: settings) == original)
        #expect(!fm.fileExists(atPath: h.home.appendingPathComponent(".claude/clepso").path))
        #expect(!fm.fileExists(atPath: h.home.appendingPathComponent(".claude/clepso-backups").path))

        // 3. Confirmed install.
        let (installed, installStatus) = try clepso(["install", "--shim", captureShim.path, "--socket", h.socketPath, "--confirm"], home: h.home)
        #expect(installStatus == 0 && installed.contains("Installed"), "\(installed)")

        // 4. Listener in the background, two status-line events through the installed wrapper.
        let listener = try FrameListener(socketPath: h.socketPath, outputDirectory: h.home.appendingPathComponent(".clepso/frames"))
        let box = FrameBox()
        let thread = Thread { listener.run(limit: 2, onFrame: { box.add($0.frame) }) }
        thread.start()
        let wrapper = h.home.appendingPathComponent(".claude/clepso/statusline.sh")
        for _ in 0..<2 {
            let result = try h.run(stdin: f08Stdin, executable: URL(fileURLWithPath: "/bin/sh"), arguments: [wrapper.path])
            #expect(result.text == "[Opus] · ctx 41% · 5h 80% · 7d 20%\n", "no original status line: the helper prints its own")
            #expect(result.status == 0)
        }
        try waitUntil { box.count == 2 }
        #expect(box.frames.allSatisfy { $0.lookup(["rate_limits", "five_hour", "used_pct"]) == .value(.number(80)) })

        // 5. Raw captures: private, exact copies of what Claude Code sent.
        let raws = try fm.contentsOfDirectory(atPath: captures.path).sorted()
        #expect(raws.count == 2)
        let rawURL = captures.appendingPathComponent(raws[0])
        #expect(try Data(contentsOf: rawURL) == f08Stdin)
        #expect(try fm.attributesOfItem(atPath: rawURL.path)[.posixPermissions] as? Int == 0o600)

        // 6. Scrub into a fixture folder; nothing identifying survives.
        let fixtureDir = h.home.appendingPathComponent("C99-rehearsal")
        _ = try CaptureScrubber.writeFixture(raw: try Data(contentsOf: rawURL), to: fixtureDir, id: "C99", label: "rehearsal", capturedAt: Date())
        let scrubbed = String(decoding: try Data(contentsOf: fixtureDir.appendingPathComponent("stdin/01-rehearsal.json")), as: UTF8.self)
        #expect(!scrubbed.contains("app-one") && !scrubbed.contains("fixture-f08-session-a") && !scrubbed.contains("transcript.jsonl"))
        #expect(scrubbed.contains("\"used_percentage\" : 80"))

        // 7. Uninstall restores the exact bytes.
        let (removed, removeStatus) = try clepso(["uninstall", "--confirm"], home: h.home)
        #expect(removeStatus == 0 && removed.contains("restoredExactly"), "\(removed)")
        #expect(try Data(contentsOf: settings) == original)
        #expect(!fm.fileExists(atPath: h.home.appendingPathComponent(".claude/clepso").path))
    }
}

final class FrameBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [JSONValue] = []
    func add(_ frame: JSONValue) { lock.withLock { stored.append(frame) } }
    var frames: [JSONValue] { lock.withLock { stored } }
    var count: Int { frames.count }
}
