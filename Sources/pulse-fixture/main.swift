import Darwin
import FixtureTools
import Foundation

// Developer tool for the fixture corpus (TEST_PLAN.md §12). Never shipped in the app.

let usage = """
usage: pulse-fixture listen --socket <path> --out <dir> [--count N]
       pulse-fixture capture-shim --helper <helper path> --captures <dir> --script <output path>
       pulse-fixture scrub --raw <capture file> --fixture <fixture dir> --id <C01> --label <slug>
"""

let arguments = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
    return arguments[i + 1]
}
setvbuf(stdout, nil, _IOLBF, 0)   // one line per frame, visible immediately when run in the background

switch arguments.first {
case "listen":
    guard let socket = option("--socket"), let out = option("--out") else { print(usage); exit(2) }
    let count = option("--count").flatMap(Int.init) ?? 10
    do {
        let listener = try FrameListener(socketPath: socket, outputDirectory: URL(fileURLWithPath: out))
        print("listening on \(socket); saving up to \(count) frames to \(out)")
        listener.run(limit: count, onFrame: { print("frame \($0.index): \(FrameListener.summary($0.frame))") },
                     onRejected: { print("rejected: \($0)") })
        print("done")
    } catch {
        print("cannot listen: \(error)"); exit(1)
    }

case "capture-shim":
    guard let helper = option("--helper"), let captures = option("--captures"), let script = option("--script") else {
        print(usage); exit(2)
    }
    let body = CaptureShim.script(helper: helper, captureDirectory: captures)
    try? FileManager.default.createDirectory(atPath: (script as NSString).deletingLastPathComponent,
                                             withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    guard FileManager.default.createFile(atPath: script, contents: Data(body.utf8), attributes: [.posixPermissions: 0o700]) else {
        print("cannot write \(script)"); exit(1)
    }
    print("capture shim written to \(script); raw captures will go to \(captures)")

case "scrub":
    guard let raw = option("--raw"), let fixture = option("--fixture"), let id = option("--id"), let label = option("--label") else {
        print(usage); exit(2)
    }
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: raw))
        // The capture time is the raw file's modification time, so the fixture clock matches the payload.
        let capturedAt = (try? FileManager.default.attributesOfItem(atPath: raw)[.modificationDate] as? Date) ?? nil
        let result = try CaptureScrubber.writeFixture(raw: data, to: URL(fileURLWithPath: fixture), id: id, label: label,
                                                      capturedAt: capturedAt ?? Date())
        print("scrubbed \(data.count) bytes: \(result.scrubCount) values redacted; top-level keys: \(result.topLevelKeys.joined(separator: ", "))")
        print("wrote \(fixture)/meta.json and stdin/01-\(label).json; write expected.json by hand")
    } catch {
        print("scrub failed: \(error). Nothing was written to the fixture folder."); exit(1)
    }

default:
    print(usage)
    exit(arguments.isEmpty ? 0 : 2)
}
