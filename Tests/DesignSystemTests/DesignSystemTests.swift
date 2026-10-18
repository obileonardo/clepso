import CoreText
import Domain
import Foundation
import SwiftUI
import Testing
@testable import DesignSystem

let now = Date(timeIntervalSince1970: 1_792_159_260)                    // 2026-10-16T14:01:00Z
let reset = Date(timeIntervalSince1970: 1_792_167_300)                  // 16:15 UTC
let london = TimeZone(identifier: "Europe/London")!
let us = Locale(identifier: "en_US_POSIX")
let claude = SourceDescriptor(evidence: .officialLocalTelemetry, displayName: "Claude Code", version: "2.1.302")

func pool(_ used: Decimal?, card: CardState, observedMinutesAgo: Double = 1, absence: AbsenceReason = .providerOmitted,
          connection: ConnectionState = .connected) -> PoolCardModel {
    let at = now.addingTimeInterval(-observedMinutesAgo * 60)
    let value: Provenanced<Decimal> = used.map { .measured($0, evidence: .officialLocalTelemetry, quality: .reported, observedAt: at, observationID: nil) }
        ?? .absent(absence, evidence: .officialLocalTelemetry, observedAt: at, observationID: nil)
    return PoolCardModel(scope: "5-hour", source: claude, used: value,
                         resetsAt: .measured(reset, evidence: .officialLocalTelemetry, quality: .reported, observedAt: at, observationID: nil),
                         card: card, connection: connection)
}

@Suite("Theme")
struct ThemeTests {
    @Test("Every text token reaches 4.5:1 on every surface, light and dark (WCAG AA)")
    func contrast() {
        var worst = (ratio: 99.0, what: "")
        for scheme in [ColorScheme.light, .dark] {
            for text in ColorToken.textTokens {
                for surface in ColorToken.surfaces {
                    let ratio = RGB.contrast(Theme.mac.rgb(text, scheme), Theme.mac.rgb(surface, scheme))
                    #expect(ratio >= 4.5, "\(text) on \(surface) (\(scheme)): \(ratio)")
                    if ratio < worst.ratio { worst = (ratio, "\(text) on \(surface), \(scheme)") }
                }
            }
        }
        #expect(abs(worst.ratio - 4.71) < 0.01, "The design system documents the worst case as 4.71:1; measured \(worst.ratio) for \(worst.what)")
    }

    @Test("Every colour token has a light and a dark value; nothing falls back to magenta")
    func complete() {
        for theme in Theme.all {
            for token in ColorToken.allCases { #expect(theme.palette[token] != nil, "\(theme.name) \(token)") }
        }
    }

    @Test("Compact counts and durations read like Claude Code's /stats")
    func compactAndDuration() {
        #expect(Formatting.compact(16_500_000_000) == "16.5B")
        #expect(Formatting.compact(27_700_000) == "27.7M")
        #expect(Formatting.compact(193_200) == "193.2K")
        #expect(Formatting.compact(2_000_000) == "2M")
        #expect(Formatting.compact(940) == "940")
        #expect(Formatting.duration(milliseconds: 675_300_000) == "7d 19h 35m")
        #expect(Formatting.duration(milliseconds: 7_254_000) == "2h 0m")
        #expect(Formatting.duration(milliseconds: 252_000) == "4m 12s")
        #expect(Formatting.duration(milliseconds: 38_400) == "38s")
    }

    @Test("1.7b concept palettes: every text token reaches 4.5:1 on every surface")
    func conceptContrast() {
        for (theme, scheme) in [(Theme.phosphor, ColorScheme.dark), (.phosphor, .light), (.ember, .dark)] {     // phosphor light: 1.13
            for text in ColorToken.textTokens {
                for surface in ColorToken.surfaces {
                    let ratio = RGB.contrast(theme.rgb(text, scheme), theme.rgb(surface, scheme))
                    #expect(ratio >= 4.5, "\(theme.name) \(scheme): \(text) on \(surface): \(ratio)")
                }
            }
            // Text on an accent fill (chips, selected tabs, prominent buttons) uses the background colour.
            #expect(RGB.contrast(theme.rgb(.background, scheme), theme.rgb(.accent, scheme)) >= 4.5)
        }
    }

    @Test("1.15 colour themes: every text token reaches 4.5:1 on every surface, in light and dark, for every theme")
    func themeContrast() {
        #expect(Theme.selectable.map(\.name) == ["phosphor", "amber", "cobalt", "orchid", "graphite"])
        for theme in Theme.selectable {
            for scheme in [ColorScheme.light, .dark] {
                for text in ColorToken.textTokens {
                    for surface in ColorToken.surfaces {
                        let ratio = RGB.contrast(theme.rgb(text, scheme), theme.rgb(surface, scheme))
                        #expect(ratio >= 4.5, "\(theme.name) \(scheme): \(text) on \(surface): \(ratio)")
                    }
                }
                // Text on an accent fill (chips, selected tabs, prominent buttons, the DEMO tag) uses a surface colour.
                for onAccent in [ColorToken.background, .surfaceElevated] {
                    let ratio = RGB.contrast(theme.rgb(onAccent, scheme), theme.rgb(.accent, scheme))
                    #expect(ratio >= 4.5, "\(theme.name) \(scheme): \(onAccent) on accent: \(ratio)")
                }
            }
        }
    }

    @Test("Themes are found by name; an unknown name falls back to Phosphor, and every theme keeps the pixel type")
    func themeLookup() {
        for theme in Theme.selectable {
            #expect(Theme.named(theme.name).name == theme.name)
            #expect(theme.typeface == .pixel)
            #expect(theme.spacingValues == Theme.phosphor.spacingValues)
        }
        #expect(Theme.named("no-such-theme").name == "phosphor")
    }

    @Test("Every theme defines every spacing token, so none falls back to the silent default; sections get 32 pt of air")
    func spacingComplete() {
        for theme in Theme.all {
            for token in SpacingToken.allCases { #expect(theme.spacingValues[token] != nil, "\(theme.name) lacks \(token)") }
            #expect(theme.spacing(.section) == 32, "\(theme.name)")
        }
    }

    @Test("The bundled pixel faces register and resolve to their own families, not a fallback")
    func pixelFonts() {
        #expect(PixelFonts.ensureRegistered())
        for family in [PixelFonts.number, PixelFonts.terminal] {
            let font = CTFontCreateWithName(family as CFString, 12, nil)
            #expect(CTFontCopyFamilyName(font) as String == family, "\(family) resolved to \(CTFontCopyFamilyName(font))")
        }
        // 1.16: Pulse's own faces, by PostScript name; CoreText must not substitute another font.
        for name in [PixelFonts.display, PixelFonts.body, PixelFonts.bodyMedium, PixelFonts.bodyBold] {
            let font = CTFontCreateWithName(name as CFString, 12, nil)
            #expect(CTFontCopyPostScriptName(font) as String == name, "\(name) resolved to \(CTFontCopyPostScriptName(font))")
        }
    }

    @Test("Reduce Motion turns every animation off")
    func reduceMotion() {
        for token in MotionToken.allCases { #expect(Theme.mac.motion(token, reduceMotion: true) == nil) }
    }
}

@Suite("Status styles (AT-01)")
struct StatusStyleTests {
    @Test("Within each family, no two states share a shape: symbol, badge and pattern are unique")
    func uniqueShapes() {
        func key(_ s: StatusStyle) -> String { "\(s.symbol)|\(s.badge ?? "-")|\(s.pattern)" }
        let values = ValueState.allCases.map { key(StatusStyles.of($0)) }
        let cards = CardState.allCases.map { key(StatusStyles.of($0)) }
        let plans = PlanProvenance.allCases.map { key(StatusStyles.of($0)) }
        #expect(Set(values).count == values.count)
        #expect(Set(cards).count == cards.count)
        #expect(Set(plans).count == plans.count)
    }

    @Test("Every state has visible words and a spoken phrase")
    func labels() {
        let styles = ValueState.allCases.map(StatusStyles.of) + CardState.allCases.map(StatusStyles.of) + PlanProvenance.allCases.map(StatusStyles.of)
        for style in styles {
            #expect(!style.label.isEmpty && !style.accessibility.isEmpty && !style.symbol.isEmpty)
        }
    }
}

@Suite("State resolution")
struct ResolveTests {
    @Test("Connection first, then the absence reason, then freshness (DATA_MODEL §2.2)")
    func resolution() {
        #expect(pool(83, card: .approaching).valueState(now: now, staleAfter: 600) == .live)
        #expect(pool(83, card: .approaching, observedMinutesAgo: 10).valueState(now: now, staleAfter: 600) == .stale)
        #expect(pool(nil, card: .quotaNotAvailable).valueState(now: now, staleAfter: 600) == .notAvailable)
        #expect(pool(nil, card: .quotaNotAvailable, absence: .providerNull).valueState(now: now, staleAfter: 600) == .notReportedYet)
        #expect(pool(nil, card: .quotaNotAvailable, absence: .rejectedBySanitizer).valueState(now: now, staleAfter: 600) == .providerError)
        #expect(pool(83, card: .disconnected, connection: .disconnected).valueState(now: now, staleAfter: 600) == .notConnected)
    }

    @Test("Engine limit states map to card states")
    func cardMapping() {
        #expect(CardState(limit: .approaching(.critical), hasResetTime: true, connected: true) == .critical)
        #expect(CardState(limit: .exhausted, hasResetTime: false, connected: true) == .exhaustedNoReset)
        #expect(CardState(limit: .paidOverage, hasResetTime: true, connected: true) == .exhaustedOverage)
        #expect(CardState(limit: .unknown, hasResetTime: false, connected: true) == .quotaNotAvailable)
        #expect(CardState(limit: .available, hasResetTime: true, connected: false) == .disconnected)
        #expect(CardState(limit: .available, hasResetTime: true, connected: true, availableAgain: .userConfirmed) == .availableAgainUser)
    }
}

@Suite("Text and VoiceOver")
struct TextTests {
    @Test("Percentages: integers stay integers, one decimal otherwise")
    func percent() {
        #expect(Formatting.percent(83) == "83%")
        #expect(Formatting.percent(Decimal(string: "23.5")!) == "23.5%")
        #expect(Formatting.percent(Decimal(string: "23.46")!) == "23.5%")
    }

    @Test("F16: a time-zone change changes the text, not the instant")
    func timeZones() {
        let la = TimeZone(identifier: "America/Los_Angeles")!
        #expect(Formatting.resetTime(reset, now: now, zone: london, locale: us) == "5:15 PM")
        #expect(Formatting.resetTime(reset, now: now, zone: la, locale: us) == "9:15 AM")
    }

    @Test("Views follow the Mac's zone without a relaunch: the default display zone updates itself")
    func displayZoneFollowsSystem() {
        #expect(EnvironmentValues().displayTimeZone == TimeZone.autoupdatingCurrent)
    }

    @Test("Ages: just now, minutes, then clock time")
    func ages() {
        #expect(Formatting.age(of: now.addingTimeInterval(-30), now: now, zone: london, locale: us) == "just now")
        #expect(Formatting.age(of: now.addingTimeInterval(-42 * 60), now: now, zone: london, locale: us) == "42m ago")
        #expect(Formatting.age(of: now.addingTimeInterval(-3 * 3600), now: now, zone: london, locale: us) == "12:01 PM")
        #expect(Formatting.countdown(to: reset, now: now) == "in 2h 14m")
        #expect(Formatting.countdown(to: now.addingTimeInterval(-1), now: now) == nil, "a passed reset has no countdown")
    }

    @Test("AT-02: one sentence per row in the UX order: scope, value, source, freshness, status, reset")
    func voiceOver() {
        let sentence = AccessibilityText.poolRow(pool(83, card: .approaching), now: now, staleAfter: 600, zone: london, locale: us)
        #expect(sentence == "5-hour, 83 percent used, Claude Code, 1 minute ago, approaching limit, resets 5:15 PM")
        let demo = AccessibilityText.poolRow(pool(83, card: .approaching), now: now, staleAfter: 600, zone: london, locale: us, isDemo: true)
        #expect(demo.hasPrefix("Demo data, "), "AT-09: demo is read first")
    }

    @Test("FR-02: an absent value is never spoken as zero; a stale one says 'last seen'")
    func absentAndStale() {
        let absent = AccessibilityText.poolRow(pool(nil, card: .quotaNotAvailable), now: now, staleAfter: 600, zone: london, locale: us)
        #expect(absent.contains("not available") && !absent.contains("0 percent"))
        let stale = AccessibilityText.poolRow(pool(83, card: .approaching, observedMinutesAgo: 42), now: now, staleAfter: 600, zone: london, locale: us)
        #expect(stale.contains("last seen 42 minutes ago") && !stale.lowercased().contains("live"))
    }
}

#if canImport(AppKit)
import AppKit

@Suite("Readable text (1.8 review)")
struct ReadableTextTests {
    @Test("Every sentence-text token in the pixel theme is at least 12 pt at the default text size")
    func minimumSize() {
        func points(_ style: Font.TextStyle) -> CGFloat {
            let ns: NSFont.TextStyle = switch style {
            case .largeTitle: .largeTitle
            case .title: .title1
            case .title2: .title2
            case .title3: .title3
            case .headline: .headline
            case .subheadline: .subheadline
            case .body: .body
            case .callout: .callout
            case .footnote: .footnote
            case .caption: .caption1
            case .caption2: .caption2
            @unknown default: .caption2
            }
            return NSFont.preferredFont(forTextStyle: ns).pointSize
        }
        for token in TypographyToken.allCases {
            guard let style = Theme.pixelTextStyle(token) else { continue }
            #expect(points(style) >= 12, "\(token) uses \(style) at \(points(style)) pt")
        }
        #expect(Theme.pixelTextStyle(.label).map(points) ?? 0 > Theme.pixelTextStyle(.supporting).map(points) ?? 0,
                "labels should outrank supporting text")
    }
}
#endif

#if canImport(AppKit)
@Suite("Pixel menu bar icon (1.11; item 7: the brand kit's state family)")
@MainActor
struct PixelMenuBarIconTests {
    static let kit = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("design/brand/menubar")

    /// Opaque pixels of a PNG as indices y × width + x.
    static func opaque(_ url: URL) throws -> Set<Int> {
        let rep = try #require(NSBitmapImageRep(data: Data(contentsOf: url)), "\(url.lastPathComponent)")
        var on = Set<Int>()
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { on.insert(y * rep.pixelsWide + x) }
        }
        return on
    }

    /// 16×16 cells blown up to `scale` device pixels each, as indices on a 16·scale-wide grid.
    static func scaled(_ cells: Set<Int>, _ scale: Int) -> Set<Int> {
        Set(cells.flatMap { cell in
            (0..<scale * scale).map { i in ((cell / 16) * scale + i / scale) * 16 * scale + (cell % 16) * scale + i % scale }
        })
    }

    /// Draws the image at `scale` device pixels per point; → opaque pixels of the 16 pt glyph square, and of the rest.
    static func rendered(_ image: NSImage, scale: Int) throws -> (glyph: Set<Int>, rest: Int) {
        let w = Int(image.size.width.rounded(.up)) * scale, h = 16 * scale
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = NSSize(width: CGFloat(w / scale), height: 16)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        var glyph = Set<Int>(), rest = 0
        for y in 0..<h {
            for x in 0..<w where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                if x < 16 * scale { glyph.insert(y * 16 * scale + x) } else { rest += 1 }
            }
        }
        return (glyph, rest)
    }

    @Test("The app draws exactly the brand kit's images: every state, and the stale variants, at 1× and 2×")
    func matchesKit() throws {
        let variants = MenuBarIcon.Shape.allCases.map { ($0, false) } + [(.approaching, true), (.flatline, true)]
        for (shape, stale) in variants {
            for scale in [1, 2] {
                let name = "state-\(shape.rawValue)\(stale ? "-stale" : "")\(scale == 2 ? "@2x" : "").png"
                let want = try Self.opaque(Self.kit.appendingPathComponent(name))
                #expect(Self.scaled(MenuBarIcon.pixels(shape, staleMark: stale), scale) == want, "\(name)")
            }
        }
    }

    @Test("The family differs by shape alone: no two states alike, the ring kept, the beat is the brand mark")
    func family() {
        let sets = MenuBarIcon.Shape.allCases.map { MenuBarIcon.pixels($0, staleMark: false) }
            + [MenuBarIcon.pixels(.approaching, staleMark: true), MenuBarIcon.pixels(.flatline, staleMark: true)]
        for i in sets.indices {
            for j in sets.indices where j > i {
                #expect(sets[i].symmetricDifference(sets[j]).count >= 4, "glyphs \(i) and \(j) differ by under 4 pixels")
            }
        }
        let ring = MenuBarIcon.pixels(.notConnected, staleMark: false)              // the empty ring
        for shape in MenuBarIcon.Shape.allCases where shape != .demo {
            #expect(MenuBarIcon.pixels(shape, staleMark: false).isSuperset(of: ring), "\(shape) lost the ring")
        }
        #expect(MenuBarIcon.pixels(.beat, staleMark: false) == Set(ClepsoMark.pixels.map { $0.y * 16 + $0.x }))
        // The stale mark opens the ring (so it cannot merge into it) and sets a dot; the clock takes none.
        let flat = MenuBarIcon.pixels(.flatline, staleMark: false), flatStale = MenuBarIcon.pixels(.flatline, staleMark: true)
        #expect(!flatStale.contains(11 * 16 + 14) && flat.contains(11 * 16 + 14) && flatStale.contains(12 * 16 + 12))
        #expect(MenuBarIcon.pixels(.stale, staleMark: true) == MenuBarIcon.pixels(.stale, staleMark: false))
    }

    @Test("Every state renders as a template image on whole pixels at 1× and 2×, with and without the % text")
    func renders() throws {
        for shape in MenuBarIcon.Shape.allCases {
            for stale in [false, true] {
                for text in [nil, "83%"] as [String?] {
                    let image = MenuBarIcon.pixelImage(shape, staleMark: stale, text: text)
                    #expect(image.isTemplate && image.size.height == 16)
                    #expect(text == nil ? image.size.width == 16 : image.size.width > 30)
                    for scale in [1, 2] {
                        let drawn = try Self.rendered(image, scale: scale)
                        #expect(drawn.glyph == Self.scaled(MenuBarIcon.pixels(shape, staleMark: stale), scale), "\(shape) \(scale)x")
                        #expect((drawn.rest > 0) == (text != nil), "\(shape): text \(text ?? "none")")
                    }
                }
            }
        }
    }

    /// Visual review, not a check: with PULSE_MENUBAR_RENDER_DIR set, writes every state (and the stale variants), with
    /// and without text, tinted as a template on a light and a dark menu bar at 1× and 2×, plus a 4× contact sheet.
    @Test("Contact sheet for review (only with PULSE_MENUBAR_RENDER_DIR)")
    func contactSheet() throws {
        guard let dir = ProcessInfo.processInfo.environment["PULSE_MENUBAR_RENDER_DIR"] else { return }
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var rows: [(String, MenuBarIcon.Shape, Bool, String?)] = []
        for shape in MenuBarIcon.Shape.allCases {
            let text: String? = switch shape { case .demo: "DEMO"; case .beat, .approaching: "83%"; default: nil }
            rows.append(("\(shape.rawValue)", shape, false, nil))
            if let text { rows.append(("\(shape.rawValue)+text", shape, false, text)) }
            if shape == .approaching || shape == .flatline { rows.append(("\(shape.rawValue)-stale", shape, true, nil)) }
        }
        rows.append(("approaching-stale+text", .approaching, true, "83%"))
        // A menu bar slice 24 pt high: the light bar's ink is black at 85 %, the dark bar's white (as macOS tints templates).
        let bars: [(String, NSColor, NSColor)] = [("light", NSColor(white: 0.93, alpha: 1), NSColor(white: 0, alpha: 0.85)),
                                                  ("dark", NSColor(white: 0.16, alpha: 1), NSColor(white: 1, alpha: 1))]
        let slice = NSSize(width: 64, height: 24)
        func render(_ image: NSImage, scale: Int, bar: NSColor, ink: NSColor) throws -> NSBitmapImageRep {
            let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(slice.width) * scale,
                                                    pixelsHigh: Int(slice.height) * scale, bitsPerSample: 8, samplesPerPixel: 4,
                                                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            rep.size = slice
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            bar.setFill(); NSRect(origin: .zero, size: slice).fill()
            let tinted = NSImage(size: image.size, flipped: false) { rect in
                image.draw(in: rect); ink.set(); rect.fill(using: .sourceIn); return true
            }
            tinted.draw(in: NSRect(x: 8, y: 4, width: image.size.width, height: image.size.height))
            NSGraphicsContext.restoreGraphicsState()
            return rep
        }
        let zoom = 4, cellW = Int(slice.width) * 2 * zoom, cellH = Int(slice.height) * 2 * zoom
        let sheet = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cellW * 4 + 50, pixelsHigh: (cellH + 10) * rows.count,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        let sheetContext = NSGraphicsContext(bitmapImageRep: sheet)
        NSGraphicsContext.current = sheetContext
        sheetContext?.imageInterpolation = .none
        NSColor(white: 0.5, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: sheet.pixelsWide, height: sheet.pixelsHigh).fill()
        for (r, row) in rows.enumerated() {
            let image = MenuBarIcon.pixelImage(row.1, staleMark: row.2, text: row.3)
            for (b, bar) in bars.enumerated() {
                for scale in [1, 2] {
                    let rep = try render(image, scale: scale, bar: bar.1, ink: bar.2)
                    let name = "\(row.0)-\(bar.0)\(scale == 2 ? "@2x" : "").png"
                    try #require(rep.representation(using: .png, properties: [:])).write(to: out.appendingPathComponent(name))
                    // Contact sheet: each render blown up to the same physical size (1× by 8, 2× by 4), no smoothing.
                    let col = b * 2 + (scale - 1)
                    let y = sheet.pixelsHigh - (r + 1) * (cellH + 10)
                    rep.draw(in: NSRect(x: col * (cellW + 10), y: y, width: cellW, height: cellH), from: .zero, operation: .copy,
                             fraction: 1, respectFlipped: false, hints: [.interpolation: NSNumber(value: NSImageInterpolation.none.rawValue)])
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try #require(sheet.representation(using: .png, properties: [:])).write(to: out.appendingPathComponent("contact-sheet.png"))
        try rows.map(\.0).joined(separator: "\n").write(to: out.appendingPathComponent("contact-sheet-rows.txt"), atomically: true, encoding: .utf8)
    }
}
#endif

@Suite("Pixel icon set (1.13)")
struct PixelIconSetTests {
    @Test("Every glyph is 12×12, glyphs are distinct, and every symbol name in use maps to a glyph")
    func glyphs() throws {
        for glyph in PixelGlyph.allCases {
            #expect(glyph.rows.count == 12 && glyph.rows.allSatisfy { $0.count == 12 }, "\(glyph)")
            #expect(glyph.rows.joined().contains("#"), "\(glyph) is empty")
        }
        let shapes = PixelGlyph.allCases.map { $0.rows.joined() }
        #expect(Set(shapes).count == shapes.count, "two glyphs are identical")
        // Every name the app and its status styles pass to PixelIcon(symbol:) is in the map (else it would draw "?").
        let styles = ValueState.allCases.map { StatusStyles.of($0).symbol } + CardState.allCases.map { StatusStyles.of($0).symbol }
            + CardState.allCases.compactMap { StatusStyles.of($0).badge } + PlanProvenance.allCases.map { StatusStyles.of($0).symbol }
        for name in styles { #expect(PixelGlyph.symbols[name] != nil, "no glyph for \(name)") }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = FileManager.default.enumerator(atPath: root.appendingPathComponent("Sources/PulseApp").path)?
            .compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") } ?? []
        let pattern = try NSRegularExpression(pattern: #"(?:symbol: |return |: )"([a-z][a-z0-9.]+)""#)
        for file in sources {
            let text = try String(contentsOf: root.appendingPathComponent("Sources/PulseApp/" + file), encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let name = String(text[Range(match.range(at: 1), in: text)!])
                guard name.contains("."), PixelGlyph.symbols[name] == nil, ["circle", "trash", "key"].contains(name) == false else { continue }
                // Dotted lowercase strings that aren't icons (diagnostic codes, preference keys) are skipped by prefix.
                let isIcon = ["person", "chevron", "clock", "gauge", "chart", "square", "exclamation", "checkmark", "flag", "text", "dot", "link",
                              "bolt", "arrow", "questionmark", "ellipsis", "minus", "waveform", "theatermasks", "circle."].contains { name.hasPrefix($0) }
                #expect(!isIcon, "\(file): no glyph for \(name)")
            }
        }
    }
}
