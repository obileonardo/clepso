#if DEBUG
import AppKit
import enum Domain.Product
import OSLog
import ServiceManagement
import SwiftUI

/// Debug probe only: `-ClepsoProbeReduceMotion YES` runs every window as if System Settings › Accessibility › Display ›
/// Reduce motion were on (through `ReduceMotionRoot`), so screenshots can show what that setting does without
/// changing the Mac's own setting.
enum ProbeOverrides {
    static let reduceMotion = UserDefaults.standard.bool(forKey: "ClepsoProbeReduceMotion")
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
/// `-ClepsoProbeFocusGallery YES` focuses each self-drawn control through `@FocusState` and captures it. No key event
/// is ever posted. (Buttons take focus only while the Mac's Keyboard navigation setting is on, which the probe
/// cannot turn on for itself: neither an `-AppleKeyboardUIMode` argument nor answering `isFullKeyboardAccessEnabled`
/// makes SwiftUI focus them, and `selectNextKeyView` does not move SwiftUI's focus.)
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
        PopoverWarmUp.run(model)          // as at a launch into this state (the app warms up after start, see ClepsoScenes)
        try? await Task.sleep(for: .seconds(1))
        guard let button = statusButton() else { recorder.log("ERROR no status item button"); return true }
        recorder.start(button)
        recorder.log("login item: SMAppService.mainApp.status=\(SMAppService.mainApp.status.rawValue) model.loginItemEnabled=\(model.loginItemEnabled)")
        recorder.log("keyboard navigation (the Mac's setting): \(NSApp.isFullKeyboardAccessEnabled) · reduce motion override: \(ProbeOverrides.reduceMotion)")

        // The driver clicks; wait for it (at most twenty minutes: idle runs wait between clicks).
        let done = folder.appendingPathComponent("driver-done")
        for _ in 0..<12_000 where !FileManager.default.fileExists(atPath: done.path) { try? await Task.sleep(for: .milliseconds(100)) }

        // The Details window, each tab; Stats from the probe home's file (synthetic: scripts/probe-home.py).
        await model.setStatsEnabled(true)
        openDetails()
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
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.title == Product.name }), let screen = window.screen?.visibleFrame,
               name.hasSuffix("-tall") || defaults.bool(forKey: "ClepsoProbeTall") {
                // As tall as the screen allows, so content below the fold is captured too.
                window.setFrame(NSRect(x: screen.minX, y: screen.minY, width: min(screen.width, 1500), height: screen.height), display: true)
            } else if let window = NSApp.windows.first(where: { $0.isVisible && $0.title == Product.name }), let screen = window.screen?.visibleFrame,
                      defaults.double(forKey: "ClepsoProbeWidth") > 0 {
                // `-ClepsoProbeWidth <pt>`: every page at one window width (the minimum is 1100), full screen height.
                window.setFrame(NSRect(x: screen.minX, y: screen.minY, width: defaults.double(forKey: "ClepsoProbeWidth"), height: screen.height), display: true)
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

    /// Each self-drawn control focused in turn through `@FocusState` (`FocusGallery`), captured, and whether SwiftUI
    /// reports it focused.
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
        for (index, name) in FocusGallery.names.enumerated() {
            state.request = index
            try? await Task.sleep(for: .milliseconds(400))
            recorder.log("focus gallery \(name): requested \(index), focused \(state.reported.map(String.init) ?? "none")")
            if name == "calendar" {                // what a first arrow does, through the same function the view calls
                recorder.log("calendar: first arrow chooses \(FocusGallery.grid.day(from: nil, weeks: 1) ?? "none")")
            }
            recorder.log(shoot(window, folder, "focus-\(index)-\(name)"))
        }
        window.close()
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
