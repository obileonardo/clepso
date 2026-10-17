#if DEBUG
import AppKit
import enum Domain.Product
import OSLog
import ServiceManagement
import SwiftUI

/// Verification harness, debug builds only (DESIGN_SYSTEM §9: popover open ≤ 200 ms p95, trigger to first frame).
///
/// Launched with `-PulseProbeOutput <dir> -PulseMeasurePopover N`, the app reports the system uptime at which the
/// window server makes its popover window visible (and emits an OSSignposter event there). Clicks come from
/// `scripts/probe-popover.swift`, which posts real mouse events and notes the uptime of each click: since macOS 14
/// only a real click lets a menu bar app activate, so in-process clicks cannot open the popover, and the status
/// item's clicks never pass the app's event monitors. Both sides read the same system-wide monotonic clock, so
/// the driver computes click → visible. Opens after the first N show the overview, detail and inspector pages
/// for screenshots. When the driver is done, the app captures each Settings tab and onboarding step and quits.
///
/// Files in <dir>: `state` (opens, closes, last visible uptime, status-item point), `probe.log`, PNGs; the driver
/// adds `popover-open-ms.txt`.
@MainActor
enum PopoverProbe {
    static let signposter = OSSignposter(subsystem: "dev.tokone.pulse", category: "popover")

    static func runIfRequested(model: AppModel, openWindow: () -> Void, openSettings: () -> Void, openDetails: () -> Void) async -> Bool {
        let defaults = UserDefaults.standard
        guard let output = defaults.string(forKey: "PulseProbeOutput") else { return false }
        let folder = URL(fileURLWithPath: output)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let recorder = Recorder(folder: folder, model: model)
        defer {
            recorder.finish()
            NSApp.terminate(nil)
        }
        if defaults.bool(forKey: "PulseProbeDemo") { await model.setDemo(true) }
        try? await Task.sleep(for: .seconds(1))
        guard let button = statusButton() else { recorder.log("ERROR no status item button"); return true }
        recorder.start(button)
        recorder.log("login item: SMAppService.mainApp.status=\(SMAppService.mainApp.status.rawValue) model.loginItemEnabled=\(model.loginItemEnabled)")

        // The driver clicks; wait for it (at most three minutes).
        let done = folder.appendingPathComponent("driver-done")
        for _ in 0..<1800 where !FileManager.default.fileExists(atPath: done.path) { try? await Task.sleep(for: .milliseconds(100)) }

        for tab in [AppModel.SettingsTab.general, .notifications, .providers, .plan, .diagnostics] {
            model.settingsTab = tab
            openSettings()
            try? await Task.sleep(for: .milliseconds(700))
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.title == tabTitle(tab) }) {
                recorder.log(shoot(window, folder, "settings-\(tab.rawValue)"))
            } else {
                recorder.log("ERROR no settings window; visible: " + NSApp.windows.filter(\.isVisible).map(\.title).joined(separator: ", "))
            }
        }
        // The delete-all confirmation, a sheet on the Settings window (opened, captured, cancelled; nothing deleted).
        model.settingsTab = .diagnostics
        openSettings()
        try? await Task.sleep(for: .milliseconds(500))
        model.confirmingDeleteAll = true
        try? await Task.sleep(for: .milliseconds(700))
        if let sheet = NSApp.windows.first(where: { $0.isVisible && $0.title == tabTitle(.diagnostics) })?.attachedSheet {
            recorder.log(shoot(sheet, folder, "settings-delete-all-sheet"))
        } else {
            recorder.log("ERROR no delete-all sheet")
        }
        model.confirmingDeleteAll = false
        try? await Task.sleep(for: .milliseconds(300))

        // The Details window, each tab; Stats with the synthetic file the probe's home provides.
        await model.setStatsEnabled(true)
        openDetails()
        let pages: [(String, AppModel.DetailsSection, StatsSummary.Range, AppModel.ModelsView)] = [
            ("limits", .limits, .allTime, .arena), ("session", .session, .allTime, .arena),
            ("stats-overview", .overview, .allTime, .arena), ("stats-overview-30", .overview, .last30, .arena),
            ("stats-overview-7", .overview, .last7, .arena), ("stats-models", .models, .allTime, .chart),
            ("stats-models-30", .models, .last30, .chart), ("stats-arena", .models, .allTime, .arena),
            ("stats-arena-7", .models, .last7, .arena), ("stats-overview-prev-year", .overview, .allTime, .arena)]
        for (name, section, range, view) in pages {
            model.statsYear = name.hasSuffix("prev-year") ? Calendar.current.component(.year, from: model.environment.clock.now()) - 1 : nil
            model.detailsSection = section
            model.statsRange = range
            model.modelsView = view
            try? await Task.sleep(for: .milliseconds(800))
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.title == Product.name }) {
                recorder.log(shoot(window, folder, "details-\(name)"))
            } else {
                recorder.log("ERROR no details window")
            }
        }

        openWindow()
        for step in AppModel.OnboardingStep.allCases {
            model.onboardingStep = step
            try? await Task.sleep(for: .milliseconds(600))
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
                        let firstPool = model.snapshot.provider?.pools.first?.poolKey ?? ""
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
