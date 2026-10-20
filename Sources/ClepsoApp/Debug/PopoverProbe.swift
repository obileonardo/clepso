#if DEBUG
import AppKit
import CryptoKit
import enum Domain.Product
import ImageIO
import OSLog
import SwiftUI

/// Debug probe only: `-ClepsoProbeReduceMotion YES` runs every window as if System Settings › Accessibility › Display ›
/// Reduce motion were on (through `ReduceMotionRoot`), so screenshots can show what that setting does without
/// changing the Mac's own setting.
enum ProbeOverrides {
    static let reduceMotion = UserDefaults.standard.bool(forKey: "ClepsoProbeReduceMotion")
    /// `-ClepsoProbeScrollToEnd YES`: Dashboard pages open scrolled to their end, for screenshots of what's below the fold.
    static let scrollToEnd = UserDefaults.standard.bool(forKey: "ClepsoProbeScrollToEnd")
    /// `-ClepsoProbeAgentSuggestions YES`: Settings shows "Find my agents" as if clicked (reads the probe home's ~/.claude/agents).
    static let agentSuggestions = UserDefaults.standard.bool(forKey: "ClepsoProbeAgentSuggestions")
}

/// Verification harness, debug builds only (popover open ≤ 200 ms p95, trigger to first frame), and the source of the
/// screenshots in design/screens.
///
/// Launched with `-ClepsoProbeOutput <dir>` (plus `-ClepsoProbeDemo YES`, and optionally `-ClepsoProbeLight YES`,
/// `-ClepsoProbeTheme <name>`, `-ClepsoProbeName <name>`), then driven by `swift scripts/probe-popover.swift <dir> N [idle s]`,
/// which times N opens. The app reports the system uptime at which the
/// window server makes its popover window visible (and emits an OSSignposter event there). Clicks come from
/// `scripts/probe-popover.swift`, which posts real mouse events and notes the uptime of each click: since macOS 14
/// only a real click lets a menu bar app activate, so in-process clicks cannot open the popover, and the status
/// item's clicks never pass the app's event monitors. Both sides read the same system-wide monotonic clock, so
/// the driver computes click → visible. Opens after the first N show the overview, detail and inspector pages
/// for screenshots. When the driver is done, the app captures each Settings tab and onboarding step and quits.
///
/// Files in <dir>: `state` (opens, closes, last visible uptime, status-item point), `probe.log`, PNGs; the driver
/// adds `popover-open-ms.txt`.
///
/// Item 9 (keyboard and Reduce Motion): `-ClepsoProbeReduceMotion YES` runs every window as if Reduce Motion were on
/// (`ProbeOverrides`); `-ClepsoProbeAX YES` pauses on every captured page until `scripts/probe-ax.swift` has read the
/// accessibility tree (read-only); `-ClepsoProbeFlipFrames YES` captures the player card mid-flip;
/// `-ClepsoProbeFocusGallery YES` focuses each self-drawn control through `@FocusState`, then by Tab, Shift-Tab, Space,
/// Return and Escape, captures each and writes a verdict (see `focusGallery`). Key events are handed to the probe's own
/// windows in process (`NSApp.sendEvent`); none is ever posted to the system. (Buttons take focus only while the
/// Mac's Keyboard navigation setting is on, which the probe cannot turn on for itself: neither an
/// `-AppleKeyboardUIMode` argument nor answering `isFullKeyboardAccessEnabled` makes SwiftUI focus them, and
/// `selectNextKeyView` does not move SwiftUI's focus; a Tab key event does.)
@MainActor
enum PopoverProbe {
    static let signposter = OSSignposter(subsystem: "com.elvisobi.clepso", category: "popover")

    static func runIfRequested(model: AppModel, openWindow: () -> Void, openDetails: () -> Void) async -> Bool {
        let defaults = UserDefaults.standard
        guard let output = defaults.string(forKey: "ClepsoProbeOutput") else { return false }
        let folder = URL(fileURLWithPath: output)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let recorder = Recorder(folder: folder, model: model)
        defer {
            recorder.finish()
            NSApp.terminate(nil)
        }
        // Screenshots never show the Mac account's name: a neutral profile name unless the run names one.
        await model.setProfileName(defaults.string(forKey: "ClepsoProbeName") ?? "Sam")
        if defaults.bool(forKey: "ClepsoProbeDemo") { await model.setDemo(true) }
        if defaults.bool(forKey: "ClepsoProbeLight") { await model.setAppearance(.light) }
        if let theme = defaults.string(forKey: "ClepsoProbeTheme") { await model.setTheme(theme) }   // one colour theme per run
        if defaults.bool(forKey: "ClepsoProbeCodex") { await model.setCodexEnabled(true) }           // reads the probe home's ~/.codex
        // `-ClepsoProbeWhatsNew YES`: Home shows the newest What's new card, as after an update. The seen version it records
        // goes to this run's own data folder (a probe never runs on the installed app's), never the user's.
        if defaults.bool(forKey: "ClepsoProbeWhatsNew") { model.whatsNew = WhatsNew.entries.first }
        // `-ClepsoProbeApprovedAgents code-reviewer,db-helper`: approved agent names for the Settings screenshots.
        for name in defaults.string(forKey: "ClepsoProbeApprovedAgents")?.split(separator: ",") ?? [] { _ = await model.approveAgentName(String(name)) }
        if defaults.bool(forKey: "ClepsoProbeMenuBar") {
            await captureMenuBarRotation(folder, model: model)
            return true
        }
        PopoverWarmUp.run(model)          // as at a launch into this state (the app warms up after start, see ClepsoScenes)
        try? await Task.sleep(for: .seconds(1))
        guard let button = statusButton() else { recorder.log("ERROR no status item button"); return true }
        recorder.start(button)
        recorder.log("login item (this run's stand-in, never the Mac's): \(model.loginItemEnabled)")
        recorder.log("keyboard navigation (the Mac's setting): \(NSApp.isFullKeyboardAccessEnabled) · reduce motion override: \(ProbeOverrides.reduceMotion)")

        // An isolated, externally driven native form/Calendar session. The marker closes it cleanly.
        if defaults.bool(forKey: "ClepsoProbeInteractive") {
            await model.completeOnboarding()
            model.detailsSection = .limits
            openDetails()
            let done = folder.appendingPathComponent("interactive-done")
            for _ in 0..<9_000 where !FileManager.default.fileExists(atPath: done.path) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            recorder.log("interactive native QA session ended")
            return true
        }

        // The driver clicks; wait for it (at most twenty minutes: idle runs wait between clicks).
        let done = folder.appendingPathComponent("driver-done")
        for _ in 0..<12_000 where !FileManager.default.fileExists(atPath: done.path) { try? await Task.sleep(for: .milliseconds(100)) }

        // The Details window, each tab; Stats from the probe home's file (synthetic: scripts/probe-home.py).
        await model.setStatsEnabled(true)
        openDetails()
        try? await Task.sleep(for: .milliseconds(500))      // the window is up before the first page sizes it
        let pages: [(String, AppModel.DetailsSection, StatsSummary.Range, AppModel.ModelsView)] = [
            ("limits", .limits, .allTime, .arena), ("session", .session, .allTime, .arena),
            ("stats-overview", .overview, .allTime, .arena), ("stats-overview-30", .overview, .last30, .arena),
            ("stats-overview-7", .overview, .last7, .arena), ("stats-models", .models, .allTime, .chart),
            ("stats-models-30", .models, .last30, .chart), ("stats-arena", .models, .allTime, .arena),
            ("stats-arena-7", .models, .last7, .arena), ("stats-overview-prev-year", .overview, .allTime, .arena),
            ("stats-arena-tall", .models, .allTime, .arena),
            ("home", .home, .allTime, .arena), ("card", .card, .allTime, .arena), ("card-back", .card, .allTime, .arena),
            ("card-tilt", .card, .allTime, .arena), ("goals", .goals, .allTime, .arena),
            ("account", .account, .allTime, .arena), ("settings", .settings, .allTime, .arena), ("home-tall", .home, .allTime, .arena)]
        // `-ClepsoProbePages card,card-back` captures only those pages (a quicker loop while working on one screen).
        let only = defaults.string(forKey: "ClepsoProbePages").map { Set($0.split(separator: ",").map(String.init)) }
        for (name, section, range, view) in pages where only?.contains(name) ?? true {
            // The card's back, and its tilt with the pointer held near the top-right corner (hover can't be scripted).
            model.cardShowsBack = name == "card-back"
            model.cardTiltPreview = name == "card-tilt" ? CGSize(width: 0.8, height: -0.7) : .zero   // flat, wherever the mouse is
            model.statsYear = name.hasSuffix("prev-year") ? Calendar.current.component(.year, from: model.environment.clock.now()) - 1 : nil
            model.detailsSection = section
            model.statsRange = range
            model.modelsView = view
            // `-ClepsoProbeWidth <pt>`: every page at that window width (the minimum is 1100), the tall pages included,
            // full screen height. Without it, tall pages (and every page under `-ClepsoProbeTall YES`) are 1500 pt wide.
            // `-ClepsoProbeFromWidth <pt>` lays each page out at that width first, then narrows it to `-ClepsoProbeWidth`,
            // as a user dragging the window narrower (a calendar once kept its wider size: see `DetailsView`).
            let width = defaults.double(forKey: "ClepsoProbeWidth"), from = defaults.double(forKey: "ClepsoProbeFromWidth")
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.title == Product.name }), let screen = window.screen?.visibleFrame,
               width > 0, from > 0 {
                window.setFrame(NSRect(x: screen.minX, y: screen.minY, width: from, height: screen.height), display: true)
                try? await Task.sleep(for: .milliseconds(600))
            }
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.title == Product.name }), let screen = window.screen?.visibleFrame,
               width > 0 || name.hasSuffix("-tall") || defaults.bool(forKey: "ClepsoProbeTall") {
                // As tall as the screen allows, so content below the fold is captured too.
                window.setFrame(NSRect(x: screen.minX, y: screen.minY, width: width > 0 ? width : min(screen.width, 1500), height: screen.height),
                                display: true)
            }
            try? await Task.sleep(for: .milliseconds(name.hasPrefix("card") ? 1600 : 800))      // the card's flip settles
            await axCheckpoint(folder, "details-\(name)")
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.title == Product.name }) {
                recorder.log(shoot(window, folder, "details-\(name)"))
            } else {
                recorder.log("ERROR no details window")
            }
        }

        if defaults.bool(forKey: "ClepsoProbeFlipFrames") { await flipFrames(model, recorder, folder) }
        if defaults.bool(forKey: "ClepsoProbeFocusGallery") { await focusGallery(model, recorder, folder) }

        // The delete-all confirmation, a sheet on the Dashboard's Settings page (opened, captured, cancelled; nothing deleted).
        model.detailsSection = .settings
        try? await Task.sleep(for: .milliseconds(400))
        model.confirmingDeleteAll = true
        try? await Task.sleep(for: .milliseconds(800))
        await axCheckpoint(folder, "settings-delete-all-sheet")
        if let sheet = NSApp.windows.first(where: { $0.isVisible && $0.title == Product.name })?.attachedSheet {
            recorder.log(shoot(sheet, folder, "settings-delete-all-sheet"))
        } else {
            recorder.log("ERROR no delete-all sheet")
        }
        model.confirmingDeleteAll = false
        try? await Task.sleep(for: .milliseconds(300))

        // v0.3: the Claude Code mod's consent sheet (opened, captured, cancelled; nothing is written).
        if model.environment.features.claudeMod {
            model.confirmingClaudeMod = true
            try? await Task.sleep(for: .milliseconds(800))
            await axCheckpoint(folder, "settings-claude-mod-sheet")
            if let sheet = NSApp.windows.first(where: { $0.isVisible && $0.title == Product.name })?.attachedSheet {
                recorder.log(shoot(sheet, folder, "settings-claude-mod-sheet"))
            } else {
                recorder.log("ERROR no Claude Code mod sheet")
            }
            model.confirmingClaudeMod = false
            try? await Task.sleep(for: .milliseconds(300))
        }

        openWindow()
        for step in AppModel.OnboardingStep.allCases {
            model.onboardingStep = step
            try? await Task.sleep(for: .milliseconds(600))
            await axCheckpoint(folder, "onboarding-\(step.rawValue)-\(step)")
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.title.hasPrefix("Welcome to") }) {
                recorder.log(shoot(window, folder, "onboarding-\(step.rawValue)-\(step)"))
            } else {
                recorder.log("ERROR no onboarding window")
            }
        }
        return true
    }

    /// Watches real clicks and the popover window's visibility.
    @MainActor
    final class Recorder {
        let folder: URL
        let model: AppModel
        var opens = 0, closes = 0
        var lastVisible: TimeInterval = 0
        var lines: [String] = []
        weak var button: NSStatusBarButton?
        var observer: NSObjectProtocol?
        var moveObserver: NSObjectProtocol?

        init(folder: URL, model: AppModel) {
            self.folder = folder
            self.model = model
        }

        func log(_ line: String) { lines.append(line) }

        func start(_ button: NSStatusBarButton) {
            self.button = button
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] note in
                let now = ProcessInfo.processInfo.systemUptime
                nonisolated(unsafe) let object = note.object          // delivered on the main queue
                MainActor.assumeIsolated {
                    guard let self, let window = object as? NSWindow, String(describing: type(of: window)).contains("MenuBarExtra") else { return }
                    if window.isVisible && window.occlusionState.contains(.visible) { self.opened(window, at: now) }
                    else if !window.occlusionState.contains(.visible) { self.closed() }   // isVisible can lag the window server
                }
            }
            // Neighbouring menu bar items change width and push this one sideways; keep the click point current.
            moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: button.window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.writeState() }
            }
            followPages()
            writeState()
        }

        /// What the driver wants next: `time`, or `shoot:overview|detail|inspector`. Read from a file, so the page
        /// never depends on counting opens (a late first open once shifted every later one).
        func page() -> String {
            (try? String(contentsOf: folder.appendingPathComponent("page"), encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "time"
        }

        /// While the popover is closed, show the page the driver asked for on the next open.
        func followPages() {
            Task { @MainActor [weak self] in
                while let self, !FileManager.default.fileExists(atPath: self.folder.appendingPathComponent("driver-done").path) {
                    if popoverWindow() == nil {
                        // `-ClepsoProbeInspectorPool codex.rate_limits.five_hour` inspects that pool instead of Claude Code's first.
                        let firstPool = UserDefaults.standard.string(forKey: "ClepsoProbeInspectorPool")
                            ?? model.snapshot.provider?.pools.first?.poolKey ?? ""
                        let route: AppModel.PopoverRoute = switch page() {
                        case "shoot:detail": .detail
                        case "shoot:inspector": .inspector(poolKey: firstPool, fromDetail: false)
                        default: .overview
                        }
                        if model.popoverRoute != route { model.popoverRoute = route }
                    }
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        }

        func opened(_ window: NSWindow, at now: TimeInterval) {
            guard opens == closes else { return }                 // one report per open
            signposter.emitEvent("popover visible")
            opens += 1
            lastVisible = now
            let page = page()
            if page.hasPrefix("shoot:") {
                let name = "popover-" + page.dropFirst("shoot:".count)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    await axCheckpoint(self.folder, name)
                    self.log(shoot(window, self.folder, name))
                }
            }
            writeState()
        }

        func closed() {
            guard closes < opens else { return }
            closes += 1
            writeState()
        }

        /// Read by the driver: progress, plus where to click in global top-left coordinates.
        func writeState() {
            var rect = button?.window?.frame ?? .zero
            rect.origin.y = (NSScreen.screens.first?.frame.height ?? 0) - rect.maxY
            let text = "opens=\(opens) closes=\(closes) visible=\(lastVisible) x=\(Int(rect.midX)) y=\(Int(rect.midY))\n"
            try? text.write(to: folder.appendingPathComponent("state"), atomically: true, encoding: .utf8)
        }

        func finish() {
            for token in [observer, moveObserver].compactMap({ $0 }) { NotificationCenter.default.removeObserver(token) }
            log("opens \(opens), closes \(closes)")
            try? lines.joined(separator: "\n").appending("\n").write(to: folder.appendingPathComponent("probe.log"), atomically: true, encoding: .utf8)
        }
    }

    /// With `-ClepsoProbeAX YES`: names this page in `ax-wait` and waits (at most 5 s) until `scripts/probe-ax.swift`
    /// has read the accessibility tree and written `ax-done-<name>`.
    static func axCheckpoint(_ folder: URL, _ name: String) async {
        guard UserDefaults.standard.bool(forKey: "ClepsoProbeAX") else { return }
        let done = folder.appendingPathComponent("ax-done-\(name)")
        try? name.write(to: folder.appendingPathComponent("ax-wait"), atomically: true, encoding: .utf8)
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: done.path) { try? await Task.sleep(for: .milliseconds(50)) }
    }

    /// Each self-drawn control focused in turn through `@FocusState` (`FocusGallery`), captured, and judged: exactly one
    /// pixel ring (`PixelFocusRingCount`) and no system focus ring (pixels of the system's focus colour in the capture).
    /// Then the same window driven by key events handed to it in process (`NSApp.sendEvent`, nothing is posted to the
    /// system): Tab through every control, Shift-Tab back, Space, Return and Escape; then Tab on the Dashboard's Home.
    /// Ends with `focus gallery verdict: PASS` or `FAIL <controls>` (controls that did not take focus are not judged).
    static func focusGallery(_ model: AppModel, _ recorder: Recorder, _ folder: URL) async {
        let state = FocusGalleryState()
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Focus gallery"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: FocusGallery(state: state).themed(model))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(600))
        let hue = systemFocusHue()
        recorder.log("focus gallery: system focus ring hue \(Int(hue))°")
        var failures: [String] = [], judged = 0
        /// Key events reach the window only while it is key; another app taking over mid-run is noted and undone.
        func keepKey(_ step: String) {
            guard !window.isKeyWindow else { return }
            recorder.log("\(step): the gallery window had lost key status (another app activated); made key again")
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        /// Captures the window and judges what it shows for the control SwiftUI reports focused.
        func judge(_ capture: String, _ wanted: Int?) {
            let shot = shoot(window, folder, capture)
            let system = systemRingPixels(folder.appendingPathComponent("\(capture).png"), hue: hue)
            let name = state.reported.map { FocusGallery.names[$0] } ?? "none"
            var line = "\(capture): focused \(name), pixel rings \(state.rings), system-ring pixels \(system)"
            if !window.isKeyWindow {
                failures.append(capture)
                line += " · WRONG (the window was not key, so this capture proves nothing; run again)"
            } else if let reported = state.reported, wanted == nil || wanted == reported {
                let native = FocusGallery.names[reported] == "native-textfield"
                let ok = native ? state.rings == 0 : state.rings == 1 && system < systemRingThreshold
                if !native { judged += 1 }
                if !ok { failures.append(capture) }
                line += ok ? " · ok" : " · WRONG (want \(native ? "the system ring only" : "one pixel ring, no system ring"))"
            } else if wanted != nil && NSApp.isFullKeyboardAccessEnabled {
                failures.append(capture)                 // with Keyboard navigation on, every control takes focus
                line += " · WRONG (did not take focus)"
            } else {
                line += " · not judged (wanted \(wanted.map { FocusGallery.names[$0] } ?? "any"))"
            }
            recorder.log(line)
            recorder.log(shot)
        }
        for (index, name) in FocusGallery.names.enumerated() {
            keepKey("focus-\(index)")
            state.request = index
            try? await Task.sleep(for: .milliseconds(400))
            if name == "calendar" {                // what a first arrow does, through the same function the view calls
                recorder.log("calendar: first arrow chooses \(FocusGallery.grid.day(from: nil, weeks: 1) ?? "none")")
            }
            judge("focus-\(index)-\(name)", index)
        }

        // Real key events through the window's own event path: Tab from no focus through every control, Shift-Tab back.
        state.request = nil
        try? await Task.sleep(for: .milliseconds(300))
        window.makeFirstResponder(window.contentView)
        var order: [String] = []
        for step in 1...13 {
            keepKey("tab-\(step)")
            press(window, key: 48, "\t")
            try? await Task.sleep(for: .milliseconds(300))
            order.append(state.reported.map { FocusGallery.names[$0] } ?? "none")
            judge("tab-\(step)", nil)
        }
        keepKey("tab-shift-back")
        press(window, key: 48, "\u{19}", shift: true)
        try? await Task.sleep(for: .milliseconds(300))
        judge("tab-shift-back", nil)
        recorder.log("tab order: \(order.joined(separator: " → "))")
        // Every control once, in reading order (the segmented control is a stop per option), then round to the first.
        let expected = FocusGallery.names.flatMap { $0 == "pixel-segmented" ? [$0, $0, $0] : [$0] } + [FocusGallery.names[0]]
        if order != expected { failures.append("tab-order") }
        if state.reported != FocusGallery.names.firstIndex(of: "calendar") { failures.append("tab-shift-back") }

        // Space activates the focused button and switch; Return and Escape reach the default and cancel buttons.
        func key(_ code: UInt16, _ characters: String, focus: Int, _ what: String, expect: String, flips: Bool = false) async {
            state.request = focus
            try? await Task.sleep(for: .milliseconds(300))
            keepKey(what)
            let before = state.activations.count, wasOn = state.toggleOn
            press(window, key: code, characters)
            try? await Task.sleep(for: .milliseconds(300))
            let ran = state.activations.dropFirst(before).joined(separator: ",")
            let ok = ran == expect && (wasOn != state.toggleOn) == flips
            if !ok { failures.append("\(what)-\(FocusGallery.names[focus])") }
            recorder.log("\(what) with \(FocusGallery.names[focus]) focused: ran [\(ran)]\(wasOn != state.toggleOn ? ", switch turned \(state.toggleOn ? "on" : "off")" : "")\(ok ? " · ok" : " · WRONG")")
        }
        await key(49, " ", focus: 0, "Space", expect: "pixel-button")
        await key(49, " ", focus: 4, "Space", expect: "plain-row")
        await key(49, " ", focus: 5, "Space", expect: "", flips: true)
        await key(36, "\r", focus: 3, "Return", expect: "pixel-prominent")          // the default button, from anywhere
        await key(53, "\u{1b}", focus: 3, "Escape", expect: "pixel-button")        // the cancel button
        // Calendar arrows travel through the real SwiftUI key-command path, not just the date helper.
        state.request = 9
        try? await Task.sleep(for: .milliseconds(300))
        for (code, character, days, weeks) in [(UInt16(124), "\u{f703}", 0, 1), (123, "\u{f702}", 0, -1),
                                               (126, "\u{f700}", -1, 0), (125, "\u{f701}", 1, 0)] {
            keepKey("calendar-arrow")
            let expected = FocusGallery.grid.day(from: state.day, days: days, weeks: weeks)
            press(window, key: code, character)
            try? await Task.sleep(for: .milliseconds(300))
            let ok = state.day == expected
            if !ok { failures.append("calendar-arrow-\(code)") }
            recorder.log("calendar arrow \(code): \(state.day ?? "none"), expected \(expected ?? "none") · \(ok ? "ok" : "WRONG")")
        }
        window.close()

        // The Dashboard's Home page, Tab by Tab from the sidebar, captured (judged by system-ring pixels only).
        model.detailsSection = .home
        if let details = NSApp.windows.first(where: { $0.isVisible && $0.title == Product.name }) {
            details.makeKeyAndOrderFront(nil)
            details.makeFirstResponder(details.contentView)
            try? await Task.sleep(for: .milliseconds(600))
            for step in 1...12 {
                if !details.isKeyWindow {
                    recorder.log("details-tab-\(step): the Dashboard had lost key status; made key again")
                    NSApp.activate(ignoringOtherApps: true)
                    details.makeKeyAndOrderFront(nil)
                }
                press(details, key: 48, "\t")
                try? await Task.sleep(for: .milliseconds(300))
                let capture = "details-tab-\(step)"
                let shot = shoot(details, folder, capture)
                recorder.log("\(capture): system-ring pixels \(systemRingPixels(folder.appendingPathComponent("\(capture).png"), hue: hue))")
                recorder.log(shot)
            }
        }
        recorder.log(failures.isEmpty ? "focus gallery verdict: PASS (\(judged) judged)" : "focus gallery verdict: FAIL \(failures.joined(separator: " "))")
    }

    /// A key press (down and up) handed to `window` through the app's own event dispatch; nothing is posted to the system.
    static func press(_ window: NSWindow, key: UInt16, _ characters: String, shift: Bool = false) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: shift ? .shift : [],
                                               timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                               context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                               isARepeat: false, keyCode: key) else { continue }
            NSApp.sendEvent(event)
        }
    }

    /// More pixels than this of the system's focus colour in a capture means its rounded ring is showing.
    static let systemRingThreshold = 40

    /// The hue (degrees) of the system's keyboard focus ring, which follows the Mac's accent colour.
    static func systemFocusHue() -> CGFloat {
        (NSColor.keyboardFocusIndicatorColor.usingColorSpace(.sRGB)?.hueComponent ?? 0.58) * 360
    }

    /// Pixels in a capture that are saturated, bright enough and within 14° of `hue`: the system focus ring.
    static func systemRingPixels(_ url: URL, hue: CGFloat) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return -1 }
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return -1 }
        var count = 0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let r = CGFloat(bytes[i]) / 255, g = CGFloat(bytes[i + 1]) / 255, b = CGFloat(bytes[i + 2]) / 255
            let high = max(r, g, b), low = min(r, g, b), range = high - low
            guard high > 0.25, range / high > 0.4 else { continue }
            var h: CGFloat = high == r ? (g - b) / range : high == g ? 2 + (b - r) / range : 4 + (r - g) / range
            h = (h * 60 + 360).truncatingRemainder(dividingBy: 360)
            let distance = abs(h - hue)
            if min(distance, 360 - distance) < 14 { count += 1 }
        }
        return count
    }

    /// The player card turning over, captured as fast as the screenshot tool allows (about every 100 ms): with Reduce
    /// Motion off the frames show the card edge-on; with it on, a crossfade between two flat faces.
    static func flipFrames(_ model: AppModel, _ recorder: Recorder, _ folder: URL) async {
        model.cardTiltPreview = .zero
        model.cardShowsBack = false
        model.detailsSection = .card
        try? await Task.sleep(for: .milliseconds(1600))
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.title == Product.name }) else { return recorder.log("ERROR no details window") }
        let start = ProcessInfo.processInfo.systemUptime
        model.cardShowsBack = true
        // Off the main thread, so the animation keeps running while the screenshot tool works.
        let number = window.windowNumber
        for frame in 0..<6 {
            let ms = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
            let url = folder.appendingPathComponent("flip-\(frame)-\(ms)ms.png")
            let status = await Task.detached { () -> Int32 in
                let tool = Process()
                tool.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                tool.arguments = ["-x", "-o", "-l", String(number), url.path]
                do { try tool.run() } catch { return -1 }
                tool.waitUntilExit()
                return tool.terminationStatus
            }.value
            recorder.log(status == 0 ? "captured flip-\(frame)-\(ms)ms" : "ERROR flip frame \(frame) status \(status)")
        }
        model.cardShowsBack = false
        try? await Task.sleep(for: .milliseconds(1200))
    }

    static func tabTitle(_ tab: AppModel.SettingsTab) -> String {
        switch tab {
        case .general: Copy.Settings.general
        case .notifications: Copy.Settings.notifications
        case .providers: Copy.Settings.providers
        case .plan: Copy.Settings.plan
        case .diagnostics: Copy.Settings.diagnostics
        }
    }

    static func statusButton() -> NSStatusBarButton? {
        func find(_ view: NSView?) -> NSStatusBarButton? {
            guard let view else { return nil }
            if let button = view as? NSStatusBarButton { return button }
            return view.subviews.lazy.compactMap(find).first
        }
        return NSApp.windows.lazy.compactMap { find($0.contentView) }.first
    }

    /// Samples the actual native status button, without screen capture, clicks or Accessibility permission.
    /// The probe's isolated home/store keeps this fixture run away from the installed app's preferences and data.
    static func captureMenuBarRotation(_ folder: URL, model: AppModel) async {
        await model.setDemo(true)
        await model.setShowPercent(true)
        await model.setMenuBarDisplay(.rotating)
        try? await Task.sleep(for: .seconds(1))
        var frames: [[String: String]] = []
        for index in 0..<4 {
            if index > 0 { try? await Task.sleep(for: .seconds(MenuBarReadout.rotationInterval + 0.25)) }
            guard let button = statusButton(), let image = button.image, let data = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) else {
                frames.append(["error": "native status button image unavailable"])
                continue
            }
            try? png.write(to: folder.appendingPathComponent("menu-bar-\(index).png"))
            frames.append(["sha256": SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined(),
                           "width": String(describing: image.size.width), "height": String(describing: image.size.height),
                           "button_width": String(describing: button.bounds.width),
                           "scale": String(describing: button.window?.backingScaleFactor ?? 1)])
        }
        let hashes = Set(frames.compactMap { $0["sha256"] })
        let widths = Set(frames.compactMap { $0["width"] })
        let expected = ProbeOverrides.reduceMotion || NSWorkspace.shared.isVoiceOverEnabled ? 1 : 2
        let report: [String: Any] = ["frames": frames, "distinct_images": hashes.count, "expected_images": expected,
                                     "passed": frames.count == 4 && hashes.count == expected && widths.count == 1]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent("menu-bar-report.json"))
        }
    }

    static func popoverWindow() -> NSWindow? {
        NSApp.windows.first { $0.isVisible && String(describing: type(of: $0)).contains("MenuBarExtra") }
    }

    /// One window's on-screen pixels via the system screenshot tool (the window number names exactly this window).
    static func shoot(_ window: NSWindow, _ folder: URL, _ name: String) -> String {
        let url = folder.appendingPathComponent("\(name).png")
        let tool = Process()
        tool.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        tool.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        do { try tool.run(); tool.waitUntilExit() } catch { return "ERROR screencapture \(name): \(error)" }
        guard tool.terminationStatus == 0 else { return "ERROR screencapture \(name) status \(tool.terminationStatus)" }
        return "captured \(name)"
    }
}
#endif
