import AppKit
import DesignSystem
import Foundation
import Testing
@testable import ClepsoApp

@Suite("Dynamic menu bar: attributed windows, rotation and honest reading states")
struct MenuBarReadoutTests {
    @Test("All four actual windows appear in a full cycle with the right agent, value and glyph")
    func fourWindows() async throws {
        let s = try Scenario()
        for (key, value) in [(MenuBarStateTests.claude5h, 12), (MenuBarStateTests.claude7d, 56),
                             (MenuBarStateTests.codex5h, 83), (MenuBarStateTests.codex7d, 100)] {
            try await s.pool(key, at: t0, used: Decimal(value), reset: t0 + 3 * 86_400)
        }
        let snap = try await s.menuBar(now: t0 + 60)
        let frames = try (0..<4).map { try #require(snap.menuBarReadout(display: .rotating, tick: $0)) }
        #expect(Set(frames.map(\.text)) == ["Claude 5h 12%", "Claude 7d 56%", "Codex 5h 83%", "Codex 7d 100%"])
        #expect(frames.first?.text == "Codex 7d 100%", "a reached limit leads, but all four remain reachable")
        #expect(frames.first?.shape == .flatline)
        #expect(frames.first { $0.text == "Codex 5h 83%" }?.shape == .approaching)
        #expect(frames.first { $0.text == "Claude 5h 12%" }?.shape == .beat)
        #expect(snap.menuBarReadout(display: .rotating, tick: 4)?.text == frames.first?.text)
        #expect(snap.menuBarReadout(display: .claudeSevenDay, tick: 200)?.text == "Claude 7d 56%")
        #expect(snap.menuBarHelp.contains("Codex 7-day: 100% used"))
        #expect(snap.menuBarReadout(display: .summary, tick: 1) == nil)
        #expect(snap.iconText == nil, "legacy summary keeps the design system's no-% flatline rule")
    }

    @Test("Old readings stay explicitly OLD; a passed reset is never a fabricated zero or Ready")
    func staleAndReset() async throws {
        let s = try Scenario()
        try await s.pool(MenuBarStateTests.claude5h, at: t0, used: 35, reset: t0 + 120)
        try await s.pool(MenuBarStateTests.codex7d, at: t0, used: 100, reset: t0 + 86_400)
        let snap = try await s.menuBar(now: t0 + 660)
        let reset = try #require(snap.menuBarReadout(display: .claudeFiveHour, tick: 0))
        let old = try #require(snap.menuBarReadout(display: .codexSevenDay, tick: 0))
        #expect(reset.text == "Claude 5h RESET?" && reset.shape == .stale)
        #expect(reset.detail.contains("awaiting a fresh reading"))
        #expect(old.text == "Codex 7d 100% OLD" && old.shape == .flatline && old.staleMark)
        #expect(old.detail.contains("old reading"))
        try await s.pool(MenuBarStateTests.claude5h, at: t0 + 720, used: 2, reset: t0 + 4 * 3600)
        let fresh = try await s.menuBar(now: t0 + 750)
        #expect(fresh.menuBarReadout(display: .claudeFiveHour, tick: 0)?.text == "Claude 5h 2%")
    }

    @Test("Missing, waiting and disabled windows remain distinct, and a pinned Codex never becomes Claude")
    func absentWindows() async throws {
        let s = try Scenario()
        let waiting = try await s.menuBar(now: t0, codex: true)
        #expect(waiting.menuBarReadout(display: .codexFiveHour, tick: 0)?.text == "Codex 5h WAIT")
        try await s.pool(MenuBarStateTests.claude5h, at: t0, used: 0, reset: nil)
        let snap = try await s.menuBar(now: t0 + 30, codex: false)
        #expect(snap.menuBarReadout(display: .claudeFiveHour, tick: 0)?.text == "Claude 5h 0%", "a real zero is a real value")
        #expect(snap.menuBarReadout(display: .claudeSevenDay, tick: 0)?.text == "Claude 7d N/A")
        #expect(snap.menuBarReadout(display: .codexFiveHour, tick: 0)?.text == "Codex 5h OFF")
        #expect(snap.rotatingReadouts.count == 2)
        #expect(snap.rotatingReadouts.allSatisfy { $0.poolKey.hasPrefix("claude-code.") })
    }

    @MainActor
    @Test("Rotating template images have identical width and remain template images across all frames")
    func imageGeometry() async throws {
        let s = try Scenario()
        try await s.pool(MenuBarStateTests.claude5h, at: t0, used: 1, reset: t0 + 3600)
        try await s.pool(MenuBarStateTests.claude7d, at: t0, used: 99.5, reset: t0 + 86_400)
        let snap = try await s.menuBar(now: t0 + 660)
        let reservation = snap.menuBarReadouts.map(\.text) + ["Claude 5h 100.0% OLD"]
        let images = snap.menuBarReadouts.map {
            MenuBarIcon.pixelImage($0.shape, staleMark: $0.staleMark, text: $0.text, reservingText: reservation)
        }
        #expect(Set(images.map { $0.size.width }).count == 1)
        #expect(images.allSatisfy { $0.isTemplate && $0.size.height == 16 && $0.size.width < 220 })
        // Check the actual drawn pixels, not only the canvas width: the former implementation reserved all spare
        // width on the right, which looked off-centre inside macOS's capsule even though every frame was 155 pt.
        for image in images {
            let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            let columns = (0..<bitmap.pixelsWide).filter { x in
                (0..<bitmap.pixelsHigh).contains { y in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 }
            }
            let left = try #require(columns.first), right = bitmap.pixelsWide - 1 - (try #require(columns.last))
            let scale = bitmap.pixelsHigh / 16
            #expect(abs(left - right) <= 2 * scale, "unequal ink margins: \(left) left, \(right) right")
        }
    }
    @MainActor
    @Test("Brand capsules preserve uppercase display type, contrast and stable centred geometry")
    func coloredPill() throws {
        _ = PixelFonts.ensureRegistered()
        #expect(NSFont(name: PixelFonts.display, size: 10)?.fontName == PixelFonts.display)
        let reservation = ["CLAUDE 5H 99.9% OLD"]
        let labels = ["Claude 5h 1%", "Codex 7d 100% OLD", "Claude 5h RESET?", "Codex 7d WAIT"]
        let images = labels.map { MenuBarIcon.pillImage(.beat, staleMark: false, text: $0, reservingText: reservation) }
        #expect(Set(images.map { $0.size.width }).count == 1)
        #expect(images.allSatisfy { !$0.isTemplate && $0.size.height == 20 })
        for theme in Theme.all {
            for shape: MenuBarIcon.Shape in [.beat, .approaching, .flatline, .stale, .demo, .waiting, .notConnected] {
                let colors = MenuBarIcon.pillColors(shape, staleMark: false, theme: theme)
                #expect(RGB.contrast(colors.ink, colors.fill) >= 4.5)
            }
        }
        for (label, image) in zip(labels, images) {
            let uppercase = MenuBarIcon.pillImage(.beat, staleMark: false, text: label.uppercased(), reservingText: reservation)
            #expect(image.tiffRepresentation == uppercase.tiffRepresentation)
            let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            let colors = MenuBarIcon.pillColors(.beat, staleMark: false)
            let columns = (0..<bitmap.pixelsWide).filter { x in
                (0..<bitmap.pixelsHigh).contains { y in
                    guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.alphaComponent > 0.99 else { return false }
                    return abs(c.redComponent - colors.ink.red) < 0.02 && abs(c.greenComponent - colors.ink.green) < 0.02
                }
            }
            let left = try #require(columns.first), right = bitmap.pixelsWide - 1 - (try #require(columns.last))
            #expect(abs(left - right) <= 2 * bitmap.pixelsHigh / 20)
        }
    }

}
