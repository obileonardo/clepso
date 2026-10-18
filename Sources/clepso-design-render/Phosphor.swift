import DesignSystem
import Domain
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Increment 1.7 design-system update: the Phosphor pixel layer, rendered from the real components in `Theme.phosphor`
// (dark in both appearances) with demo values. Written into design.json under "phosphor".

@MainActor
func renderPhosphor(images: URL, now: Date, used: (Decimal?, Double, AbsenceReason) -> Provenanced<Decimal>,
                    pool: (String, Provenanced<Decimal>, CardState, Date?) -> PoolCardModel) throws -> [String: Any] {
    PixelFonts.ensureRegistered()
    let theme = Theme.phosphor
    let reset = now.addingTimeInterval(2 * 3600 + 14 * 60)

    func shoot(_ id: String, width: CGFloat, _ view: some View) throws -> [String: Any] {
        let framed = view
            .padding(theme.spacing(.spacious))
            .frame(width: width, alignment: .leading)
            .background(theme.color(.background, .dark))
            .environment(\.theme, theme)
            .environment(\.colorScheme, .dark)
            .environment(\.displayTimeZone, london)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.isFixtureData, false)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        let name = "phosphor-\(id).png"
        guard let image = renderer.cgImage,
              let out = CGImageDestinationCreateWithURL(images.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(out, image, nil)
        guard CGImageDestinationFinalize(out) else { throw CocoaError(.fileWriteUnknown) }
        return ["image": "img/\(name)", "width": image.width / 2, "height": image.height / 2]
    }

    let rows: [(String, String, String, PoolCardModel, String?)] = [
        ("limit-available", "PixelLimitRow", "Available, live", pool("5-hour", used(41, 1, .providerOmitted), .available, reset), nil),
        ("limit-approaching", "PixelLimitRow", "Approaching, with a pace estimate", pool("5-hour", used(83, 1, .providerOmitted), .approaching, reset),
         "Estimate: at this pace, 100% around 15:52"),
        ("limit-critical", "PixelLimitRow", "Nearly exhausted", pool("5-hour", used(96, 1, .providerOmitted), .critical, reset), nil),
        ("limit-exhausted", "PixelLimitRow", "Limit reached, reset known", pool("7-day", used(100, 1, .providerOmitted), .exhausted, reset), nil),
        ("limit-reset-expected", "PixelLimitRow", "Reset time passed, no fresh reading", pool("7-day", used(100, 8, .providerOmitted), .resetExpected,
                                                                                             now.addingTimeInterval(-120)), nil),
        ("limit-stale", "PixelLimitRow", "Stale: dithered bar, last seen", pool("5-hour", used(83, 42, .providerOmitted), .approaching, reset), nil),
        ("limit-not-available", "PixelLimitRow", "Not reported (F06): words, empty outlined bar, never 0%",
         pool("5-hour", used(nil, 1, .providerOmitted), .quotaNotAvailable, nil), nil),
    ]
    var specimens: [[String: Any]] = []
    for (id, component, caption, model, pace) in rows {
        var row = try shoot(id, width: 420, PixelLimitRow(model: model, now: now, pace: pace))
        row["id"] = id; row["component"] = component; row["caption"] = caption
        specimens.append(row)
    }

    let extras: [(String, String, String, CGFloat, AnyView)] = [
        ("bars", "PixelBar", "Solid, dithered (stale) and outlined (no value): the non-colour cues", 420, AnyView(VStack(spacing: 12) {
            PixelBar(fraction: 0.41, role: .statusSuccess, pattern: .solid)
            PixelBar(fraction: 0.83, role: .statusStale, pattern: .hatched)
            PixelBar(fraction: nil, role: .statusUnknown, pattern: .outline)
        })),
        ("buttons", "PixelButtonStyle", "Prominent, normal and disabled; the bevel swaps when pressed", 420, AnyView(HStack(spacing: 8) {
            Button("Details") {}.buttonStyle(PixelButtonStyle(prominent: true))
            Button("Stats") {}.buttonStyle(PixelButtonStyle())
            Button("Install") {}.buttonStyle(PixelButtonStyle()).disabled(true)
        })),
        ("tabs", "PixelTabs", "Selected tab lit, others recessed", 420, AnyView(
            PixelTabs([(0, "Limits"), (1, "Session"), (2, "Stats")], selection: .constant(0)))),
        ("stats", "PixelStat", "Value over a pixel caption", 420, AnyView(HStack {
            PixelStat("$8.40", "Cost est.")
            PixelStat("97%", "Cache hits")
            PixelStat("+1.3K", "Lines +/−")
            PixelStat("42m 0s", "API time")
        })),
        ("chart", "PixelLineChart", "Usage history: steps on a pixel grid, 80/95/100 guides, NOW, dashed pace", 640, AnyView(
            PixelLineChart(series: [ChartSeries(id: "5h", points: (0...12).map { (x: Double($0), y: 59 + Double($0) * 2) }, role: .accent)],
                           xRange: -48...20, yRange: 0...100, guides: [80, 95, 100], guideLabel: { $0 == 95 ? "" : "\(Int($0))%" },
                           projection: ((12, 83), (19, 100)), marker: 12, summary: "5-hour usage history, demo")
                .frame(height: 140))),
        ("heatmap", "PixelHeatmap", "Activity like /stats: Monday on top, four levels, Less → More", 640, AnyView(
            PixelHeatmap(weeks: (0..<13).map { w in (0..<7).map { d in (w * 7 + d) % 11 == 0 ? 4 : (w > 8 ? (w * 3 + d) % 5 : ((w + d) % 9 == 0 ? 1 : 0)) } },
                         months: [(1, "Aug"), (5, "Sep"), (9, "Oct")], summary: "Activity heatmap, demo"))),
        ("panel", "PixelPanel", "Stepped corners, outer frame, inner rule (glass in the app)", 420, AnyView(
            PixelPanel { Text("AI CAPACITY").font(theme.font(.title)).foregroundStyle(theme.color(.accent, .dark)).frame(maxWidth: .infinity, alignment: .leading) })),
        ("type", "Typography", "Silkscreen for figures and labels, monospaced system face for sentences", 420, AnyView(
            VStack(alignment: .leading, spacing: 6) {
                Text("83%").font(theme.font(.metricHero)).foregroundStyle(theme.color(.textPrimary, .dark))
                Text("16.5B · OPUS 5.5").font(theme.font(.metricMedium)).foregroundStyle(theme.color(.textPrimary, .dark))
                Text("5-HOUR").font(theme.font(.title)).foregroundStyle(theme.color(.textPrimary, .dark))
                Text("Approaching limit · just now").font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, .dark))
                Text("RESETS 17:24 · IN 2H 14M").font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, .dark))
            })),
    ]
    for (id, component, caption, width, view) in extras {
        var row = try shoot(id, width: width, view)
        row["id"] = id; row["component"] = component; row["caption"] = caption
        specimens.append(row)
    }

    var palette: [[String: Any]] = []
    for token in ColorToken.allCases {
        palette.append(["token": token.rawValue, "hex": theme.rgb(token, .dark).css, "isText": ColorToken.textTokens.contains(token)])
    }
    var contrast: [[String: Any]] = []
    for text in ColorToken.textTokens {
        for surface in ColorToken.surfaces {
            let ratio = RGB.contrast(theme.rgb(text, .dark), theme.rgb(surface, .dark))
            contrast.append(["text": text.rawValue, "surface": surface.rawValue, "ratio": (ratio * 100).rounded() / 100, "passesAA": ratio >= 4.5])
        }
    }
    return [
        "specimens": specimens, "palette": palette, "contrast": contrast,
        "fonts": [["family": PixelFonts.display, "use": "figures, labels, buttons, tabs", "licence": "SIL OFL 1.1"],
                  ["family": PixelFonts.number, "use": "bundled; replaced for figures (its 5 read as S)", "licence": "SIL OFL 1.1"],
                  ["family": PixelFonts.terminal, "use": "bundled for terminal details", "licence": "SIL OFL 1.1"],
                  ["family": "SF Mono (system)", "use": "sentences, for legibility", "licence": "system"]],
    ]
}
