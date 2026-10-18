// Developer tool: reads the accessibility tree of a probe run of Clepso (Sources/PulseApp/Debug/PopoverProbe.swift),
// read-only, at each checkpoint the app announces with `-PulseProbeAX YES`. It never sets an attribute, performs an
// action or posts an event: it only reads AXRole, AXTitle, AXDescription, AXValue, AXEnabled, AXFocused and whether
// AXFocused is settable (the system's own "can take keyboard focus" answer), and writes one file per checkpoint.
//
// The app writes the checkpoint's name to `<dir>/ax-wait` and waits for `<dir>/ax-done-<name>`; this script writes
// `<dir>/ax-<name>.txt` (the tree, then a summary line) and then that file. Run it beside the probe driver:
//
//   swift scripts/probe-ax.swift <probe dir> &
//   swift scripts/probe-popover.swift <probe dir> 1
//
// It stops when the probe app quits (it writes probe.log last). Needs the terminal's Accessibility permission, like
// the driver. Summary keys: elements, buttons (AXButton, AXCheckBox, AXRadioButton, AXPopUpButton, AXTextField…),
// focusable (AXFocused settable; SwiftUI reports it only for some controls, and only while keyboard navigation is on),
// press (offers AXPress: Return/Space and VoiceOver can activate it), adjust (offers AXIncrement/AXDecrement), focused.
import ApplicationServices
import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 2 else { print("usage: probe-ax.swift <probe dir>"); exit(2) }
let folder = URL(fileURLWithPath: arguments[1])
guard AXIsProcessTrusted() else { print("This terminal lacks Accessibility permission."); exit(1) }

let controls: Set<String> = ["AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXTextField", "AXIncrementor",
                             "AXSlider", "AXMenuButton", "AXLink", "AXComboBox", "AXSegmentedControl", "AXDisclosureTriangle"]

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func text(_ element: AXUIElement, _ name: String) -> String? {
    guard let value = attribute(element, name) else { return nil }
    if let s = value as? String { return s.isEmpty ? nil : s }
    if let n = value as? NSNumber { return n.stringValue }
    return nil
}

func settable(_ element: AXUIElement, _ name: String) -> Bool {
    var result = DarwinBoolean(false)
    return AXUIElementIsAttributeSettable(element, name as CFString, &result) == .success && result.boolValue
}

struct Counts { var elements = 0, controls = 0, focusable = 0, controlsNotFocusable = 0, press = 0, adjust = 0; var focused: String? }

func describe(_ element: AXUIElement) -> String {
    let role = text(element, "AXRole") ?? "?"
    let subrole = text(element, "AXSubrole").map { "/" + $0 } ?? ""
    let name = [text(element, "AXTitle"), text(element, "AXDescription"), text(element, "AXValue").map { "=" + $0 }]
        .compactMap { $0 }.joined(separator: " ").replacingOccurrences(of: "\n", with: " ")
    return "\(role)\(subrole) \"\(name.prefix(90))\""
}

func walk(_ element: AXUIElement, depth: Int, lines: inout [String], counts: inout Counts) {
    guard depth < 60 else { return }
    counts.elements += 1
    let role = text(element, "AXRole") ?? "?"
    let focusable = settable(element, "AXFocused")
    let focused = (attribute(element, "AXFocused") as? Bool) ?? false
    let enabled = (attribute(element, "AXEnabled") as? Bool) ?? true
    if controls.contains(role) {
        counts.controls += 1
        if !focusable && enabled { counts.controlsNotFocusable += 1 }
    }
    if focusable { counts.focusable += 1 }
    var names: CFArray?
    let actions = AXUIElementCopyActionNames(element, &names) == .success ? (names as? [String] ?? []) : []
    let press = actions.contains("AXPress"), adjust = actions.contains("AXIncrement")
    if press { counts.press += 1 }
    if adjust { counts.adjust += 1 }
    if focused { counts.focused = describe(element) }
    let flags = [press ? "press" : nil, adjust ? "adjust" : nil, focusable ? "focusable" : nil, focused ? "FOCUSED" : nil, enabled ? nil : "disabled"].compactMap { $0 }
    lines.append(String(repeating: "  ", count: depth) + describe(element) + (flags.isEmpty ? "" : " [" + flags.joined(separator: ",") + "]"))
    for child in (attribute(element, "AXChildren") as? [AXUIElement]) ?? [] { walk(child, depth: depth + 1, lines: &lines, counts: &counts) }
}

/// The debug build the probe launched (never an installed copy). The list refreshes while the run loop runs.
func app() -> NSRunningApplication? {
    NSWorkspace.shared.runningApplications.first { $0.localizedName == "Clepso" && ($0.bundleURL?.path.contains("DerivedData") ?? false) }
}

func dump(_ name: String) {
    guard let running = app() else { return print("ERROR \(name): the probe app is not running") }
    let root = AXUIElementCreateApplication(running.processIdentifier)
    // A step of a focus walk: only which element holds keyboard focus.
    if name.hasPrefix("tab-") {
        let focused = attribute(root, "AXFocusedUIElement").flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
        let line = "FOCUS \(name): " + (focused.map(describe) ?? "none")
        let log = folder.appendingPathComponent("focus-walk.txt")
        if let handle = try? FileHandle(forWritingTo: log) { handle.seekToEndOfFile(); handle.write(Data((line + "\n").utf8)); try? handle.close() }
        else { try? (line + "\n").write(to: log, atomically: true, encoding: .utf8) }
        return
    }
    var lines: [String] = []
    var total = Counts()
    let windows = (attribute(root, "AXWindows") as? [AXUIElement]) ?? []
    for window in windows {
        var counts = Counts()
        walk(window, depth: 0, lines: &lines, counts: &counts)
        lines.append("WINDOW \(describe(window)): elements=\(counts.elements) controls=\(counts.controls) focusable=\(counts.focusable) "
                     + "controls-not-focusable=\(counts.controlsNotFocusable) press=\(counts.press) adjust=\(counts.adjust) focused=\(counts.focused ?? "none")")
        total.elements += counts.elements; total.controls += counts.controls; total.focusable += counts.focusable
        total.controlsNotFocusable += counts.controlsNotFocusable; total.press += counts.press; total.adjust += counts.adjust
    }
    // The menu bar the app installs (key equivalents such as ⌘W and ⌘, live here even though an agent app hides it).
    if let bar = attribute(root, "AXMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID() {
        let menuBar = bar as! AXUIElement
        func menus(_ element: AXUIElement, _ path: String) {
            for child in (attribute(element, "AXChildren") as? [AXUIElement]) ?? [] {
                let title = text(child, "AXTitle") ?? ""
                if let key = text(child, "AXMenuItemCmdChar") { lines.append("MENU \(path)\(title) ⌘\(key)") }
                menus(child, title.isEmpty ? path : path + title + " › ")
            }
        }
        for menu in (attribute(menuBar, "AXChildren") as? [AXUIElement]) ?? [] where text(menu, "AXTitle") != "Apple" {
            menus(menu, (text(menu, "AXTitle") ?? "") + " › ")
        }
    }
    lines.append("SUMMARY \(name): windows=\(windows.count) elements=\(total.elements) controls=\(total.controls) focusable=\(total.focusable) "
                 + "controls-not-focusable=\(total.controlsNotFocusable) press=\(total.press) adjust=\(total.adjust)")
    try? lines.joined(separator: "\n").appending("\n").write(to: folder.appendingPathComponent("ax-\(name).txt"), atomically: true, encoding: .utf8)
    print(lines.last!)
    fflush(stdout)
}

let wait = folder.appendingPathComponent("ax-wait")
var sawApp = false
while true {
    if app() != nil { sawApp = true } else if sawApp { break }
    if FileManager.default.fileExists(atPath: folder.appendingPathComponent("probe.log").path) { break }
    if let name = (try? String(contentsOf: wait, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
       !FileManager.default.fileExists(atPath: folder.appendingPathComponent("ax-done-\(name)").path) {
        dump(name)
        FileManager.default.createFile(atPath: folder.appendingPathComponent("ax-done-\(name)").path, contents: nil)
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))      // lets NSWorkspace see the app launch and quit
}
