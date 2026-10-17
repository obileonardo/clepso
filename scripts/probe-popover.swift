// Developer tool: drives the popover timing probe (Sources/PulseApp/Debug/PopoverProbe.swift).
// Posts real mouse clicks on Pulse's status item through the HID event tap (needs the terminal to have
// Accessibility permission; checked first, never prompted), notes the system uptime of each click, and reads the
// uptime at which the app saw its popover become visible. Both are the same system-wide monotonic clock, so the
// difference is click → popover on screen. Before every click it makes sure the popover is closed, and it times
// only an open it can attribute to that click. Then it asks for the overview, detail and inspector pages
// (through a `page` file the app follows) and lets the app screenshot each.
// Puts the pointer back where it was. Writes popover-open-ms.txt and prints p50/p95/max.
// usage: swift scripts/probe-popover.swift <probe dir> <timed opens>
import ApplicationServices
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3, let timed = Int(arguments[2]) else { print("usage: probe-popover.swift <dir> <timed opens>"); exit(2) }
let folder = URL(fileURLWithPath: arguments[1])
guard AXIsProcessTrusted() else { print("This terminal lacks Accessibility permission; clicks would be dropped."); exit(1) }

func state() -> [String: Double] {
    guard let text = try? String(contentsOf: folder.appendingPathComponent("state"), encoding: .utf8) else { return [:] }
    var values: [String: Double] = [:]
    for pair in text.split(whereSeparator: \.isWhitespace) {
        let parts = pair.split(separator: "=")
        if parts.count == 2, let value = Double(parts[1]) { values[String(parts[0])] = value }
    }
    return values
}

func waitFor(_ seconds: Double, _ condition: ([String: Double]) -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition(state()) { return true }
        usleep(10_000)
    }
    return false
}

func click(at point: CGPoint) {
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(20_000)
    }
}

guard waitFor(20, { $0["x"] != nil && $0["x"] != 0 }) else { print("the app never reported its status item"); exit(1) }
let home = CGEvent(source: nil)?.location ?? .zero
defer { CGWarpMouseCursorPosition(home) }

func setPage(_ page: String) {
    try? page.write(to: folder.appendingPathComponent("page"), atomically: true, encoding: .utf8)
    usleep(150_000)                                       // the app applies it while the popover is closed
}

func screenshot(_ name: String, at point: CGPoint) {
    let shot = Process()
    shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    shot.arguments = ["-x", "-R\(Int(point.x) - 300),0,600,400", folder.appendingPathComponent("\(name).png").path]
    try? shot.run(); shot.waitUntilExit()
}

/// Closes the popover if it is open, so every timed click starts from the same state.
func ensureClosed() {
    let s = state()
    guard (s["opens"] ?? 0) > (s["closes"] ?? 0) else { return }
    click(at: CGPoint(x: s["x"] ?? 0, y: s["y"] ?? 0))
    _ = waitFor(3) { ($0["closes"] ?? 0) >= ($0["opens"] ?? 0) }
}

/// One click → one open. Returns click-to-visible in ms only when the open is unambiguously this click's.
func openOnce(settle: UInt32) -> Double? {
    ensureClosed()
    let s = state()
    let base = s["opens"] ?? 0
    let point = CGPoint(x: s["x"] ?? 0, y: s["y"] ?? 0)
    let clickedAt = ProcessInfo.processInfo.systemUptime
    click(at: point)
    guard waitFor(3, { ($0["opens"] ?? 0) > base }) else {
        screenshot("miss-\(Int(base))", at: point)
        return nil
    }
    let after = state()
    let latency = (after["opens"] ?? 0) == base + 1 ? ((after["visible"] ?? 0) - clickedAt) * 1000 : nil
    usleep(settle)
    ensureClosed()
    usleep(200_000)
    return latency.flatMap { $0 > 0 ? $0 : nil }        // a non-positive span means the open was not this click's
}

var misses = 0
var samples: [Double] = []
setPage("time")
var attempts = 0
while samples.count < timed && attempts < timed * 2 {
    attempts += 1
    if let ms = openOnce(settle: 300_000) { samples.append(ms) } else { misses += 1; print("attempt \(attempts): no attributable open") }
}
for page in ["overview", "detail", "inspector"] {
    setPage("shoot:\(page)")
    if openOnce(settle: 1_200_000) == nil { print("screenshot \(page): no attributable open") }
}
setPage("time")
FileManager.default.createFile(atPath: folder.appendingPathComponent("driver-done").path, contents: nil)
CGWarpMouseCursorPosition(home)
try? samples.map { String(format: "%.3f", $0) }.joined(separator: "\n").appending("\n")
    .write(to: folder.appendingPathComponent("popover-open-ms.txt"), atomically: true, encoding: .utf8)
let sorted = samples.sorted()
func percentile(_ p: Double) -> Double { sorted.isEmpty ? .nan : sorted[min(sorted.count - 1, Int((p * Double(sorted.count)).rounded(.up)) - 1)] }
print(String(format: "driver: %d timed opens, %d misses · p50 %.1f ms · p95 %.1f ms · max %.1f ms · first %.1f ms",
             samples.count, misses, percentile(0.5), percentile(0.95), sorted.last ?? .nan, samples.first ?? .nan))
