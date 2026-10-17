import Foundation
import Testing
@testable import FixtureTools

/// Assembled from two pieces so no secret-shaped literal exists in the source (the CI secret scan).
let fakeToken = "sk-" + "ant-api03-xxxx"

/// A raw capture shaped like a real one, with the kinds of personal data a real session carries.
let rawCapture = Data(#"""
{"cwd":"/Users/someone/projects/secret-app","session_id":"abc-123-raw","transcript_path":"/Users/someone/.claude/projects/x.jsonl",
 "session_name":"Fix login bug","model":{"id":"claude-opus-5-5","display_name":"Opus"},
 "workspace":{"current_dir":"/Users/someone/p","project_dir":"/Users/someone/p","added_dirs":["/Users/someone/q"],
   "repo":{"host":"github.com","owner":"someone","name":"secret-app"}},
 "pr":{"number":12,"url":"https://github.com/someone/secret-app/pull/12"},"version":"2.1.302",
 "context_window":{"used_percentage":null,"current_usage":null,"context_window_size":200000,"total_input_tokens":0},
 "rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1792167300}},"vim":{"mode":"NORMAL"},
 "note":"contact me@example.com","token":"\#(fakeToken)","exceeds_200k_tokens":false}
"""#.utf8)

func keyPaths(_ value: Any, _ prefix: String = "") -> Set<String> {
    guard let object = value as? [String: Any] else { return [prefix] }
    return object.reduce(into: Set([prefix])) { $0.formUnion(keyPaths($1.value, prefix + "." + $1.key)) }
}

@Suite("Capture scrubber")
struct CaptureScrubberTests {
    let key = Data(repeating: 9, count: 32)

    @Test("Every key, type and null survives; only identifying strings change")
    func shapePreserved() throws {
        let result = try CaptureScrubber.scrub(rawCapture, key: key)
        let original = try #require(try JSONSerialization.jsonObject(with: rawCapture) as? [String: Any])
        let s = result.scrubbed
        #expect(keyPaths(s) == keyPaths(original), "the payload's key set is the evidence; it must not change")
        let context = try #require(s["context_window"] as? [String: Any])
        #expect(context["used_percentage"] is NSNull && context["current_usage"] is NSNull)
        #expect(context["context_window_size"] as? Int == 200_000)
        #expect((s["rate_limits"] as? [String: Any]).flatMap { $0["five_hour"] as? [String: Any] }?["used_percentage"] as? Double == 23.5)
        #expect(s["exceeds_200k_tokens"] as? Bool == false)
        #expect((s["model"] as? [String: Any])?["id"] as? String == "claude-opus-5-5")
        #expect(s["version"] as? String == "2.1.302")
        #expect((s["vim"] as? [String: Any])?["mode"] as? String == "NORMAL")
        #expect((s["pr"] as? [String: Any])?["number"] as? Int == 12)
    }

    @Test("Paths, names, repo identity, emails and secrets are replaced and counted")
    func identifyingDataRemoved() throws {
        let result = try CaptureScrubber.scrub(rawCapture, key: key)
        let text = String(decoding: try JSONSerialization.data(withJSONObject: result.scrubbed, options: .sortedKeys), as: UTF8.self)
        for leaked in ["someone", "secret-app", "Fix login", "me@example.com", "sk-ant", "abc-123-raw", "github.com", "/Users/"] {
            #expect(!text.contains(leaked), "\(leaked) survived scrubbing")
        }
        #expect(result.scrubbed["cwd"] as? String == "/fixture/path")
        #expect((result.scrubbed["workspace"] as? [String: Any])?["added_dirs"] as? [String] == ["/fixture/path"])
        #expect(result.scrubCount == 12)
        #expect(CaptureScrubber.lintFindings(text).isEmpty)
    }

    @Test("The session id becomes a keyed hash: stable for one key, different across keys")
    func sessionHash() throws {
        let a = try CaptureScrubber.scrub(rawCapture, key: key).scrubbed["session_id"] as? String
        let b = try CaptureScrubber.scrub(rawCapture, key: key).scrubbed["session_id"] as? String
        let c = try CaptureScrubber.scrub(rawCapture, key: Data(repeating: 1, count: 32)).scrubbed["session_id"] as? String
        #expect(a == b && a != c)
        #expect(a?.hasPrefix("capture-") == true && a?.count == "capture-".count + 16)
    }

    @Test("Lint catches anything that would identify this Mac")
    func lint() {
        #expect(CaptureScrubber.lintFindings("/Users/x") == ["/Users/"])
        #expect(CaptureScrubber.lintFindings("a@b").contains("@"))
        #expect(CaptureScrubber.lintFindings("{\"model\":\"Opus\"}").isEmpty)
    }

    @Test("writeFixture produces a captured, scrubbed fixture and never an expected file")
    func writeFixture() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tk-fx-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try CaptureScrubber.writeFixture(raw: rawCapture, to: dir, id: "C99", label: "rehearsal", capturedAt: Date(timeIntervalSince1970: 1_792_159_200))
        let meta = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("meta.json"))) as? [String: Any])
        #expect(meta["origin"] as? String == "captured" && meta["scrubbed"] as? Bool == true)
        #expect((meta["capture"] as? [String: Any])?["rawStdinBytes"] as? Int == rawCapture.count)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("stdin/01-rehearsal.json").path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("expected.json").path))
    }
}

@Suite("Capture shim script")
struct CaptureShimTests {
    @Test("Saves raw stdin privately and passes it to the helper unchanged")
    func teesAndExecs() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tk-cs-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let helper = dir.appendingPathComponent("fake-helper")
        try Data("#!/bin/sh\nprintf 'helper got: '; cat\n".utf8).write(to: helper)
        chmod(helper.path, 0o755)
        let captures = dir.appendingPathComponent("captures").path
        let script = dir.appendingPathComponent("capture.sh")
        try Data(CaptureShim.script(helper: helper.path, captureDirectory: captures).utf8).write(to: script)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: Data("{\"x\":1}".utf8))
        try input.fileHandleForWriting.close()
        let out = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        #expect(out == "helper got: {\"x\":1}")
        let files = try FileManager.default.contentsOfDirectory(atPath: captures)
        #expect(files.count == 1)
        let saved = URL(fileURLWithPath: captures).appendingPathComponent(files[0])
        #expect(try Data(contentsOf: saved) == Data("{\"x\":1}".utf8))
        let attrs = try FileManager.default.attributesOfItem(atPath: saved.path)
        #expect((attrs[.posixPermissions] as? Int) == 0o600)
        #expect((try FileManager.default.attributesOfItem(atPath: captures)[.posixPermissions] as? Int) == 0o700)
    }
}
