import DesignSystem
import Domain
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Developer tool: renders the real SwiftUI components with ImageRenderer and exports the theme as JSON,
// so the design-system page shows the shipped code, not an imitation. Every value shown is demo data.
// usage: pulse-design-render <output dir>

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--concept" {
    try renderConceptBoards(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    exit(0)
}

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "design-render")
let images = output.appendingPathComponent("img")
try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)

let now = Date(timeIntervalSince1970: 1_792_159_260)          // a fixed demo instant
let reset = now.addingTimeInterval(2 * 3600 + 14 * 60)
let london = TimeZone(identifier: "Europe/London")!
let claude = SourceDescriptor(evidence: .officialLocalTelemetry, displayName: "Claude Code", version: "2.1.302")
let manual = SourceDescriptor(evidence: .userConfirmed, displayName: "Entered by you", version: nil)

func used(_ value: Decimal?, minutesAgo: Double = 1, absence: AbsenceReason = .providerOmitted) -> Provenanced<Decimal> {
    let at = now.addingTimeInterval(-minutesAgo * 60)
    return value.map { .measured($0, evidence: .officialLocalTelemetry, quality: .reported, observedAt: at, observationID: nil) }
        ?? .absent(absence, evidence: .officialLocalTelemetry, observedAt: at, observationID: nil)
}
func resets(_ date: Date?) -> Provenanced<Date> {
    date.map { .measured($0, evidence: .officialLocalTelemetry, quality: .reported, observedAt: now.addingTimeInterval(-60), observationID: nil) }
        ?? .absent(.providerOmitted, evidence: .officialLocalTelemetry, observedAt: now.addingTimeInterval(-60), observationID: nil)
}
func pool(_ scope: String, _ value: Provenanced<Decimal>, _ card: CardState, reset r: Date? = reset,
          source: SourceDescriptor = claude, connection: ConnectionState = .connected) -> PoolCardModel {
    PoolCardModel(scope: scope, source: source, used: value, resetsAt: resets(r), card: card, connection: connection)
}
let session = SessionRowModel(modelName: "Opus 5.5",
                              contextUsed: .measured(41, evidence: .officialLocalTelemetry, quality: .reported, observedAt: now, observationID: nil),
                              contextTokens: .measured(82_000, evidence: .officialLocalTelemetry, quality: .reported, observedAt: now, observationID: nil),
                              contextWindow: .measured(200_000, evidence: .officialLocalTelemetry, quality: .reported, observedAt: now, observationID: nil))

struct Specimen {
    let id: String
    let component: String
    let caption: String
    let view: AnyView
}

let specimens: [Specimen] = [
    Specimen(id: "quota-available", component: "QuotaProgress", caption: "Available · 41%", view: AnyView(QuotaProgress(model: pool("5-hour", used(41), .available), now: now))),
    Specimen(id: "quota-approaching", component: "QuotaProgress", caption: "Approaching · crossed 80%", view: AnyView(QuotaProgress(model: pool("5-hour", used(83), .approaching), now: now))),
    Specimen(id: "quota-critical", component: "QuotaProgress", caption: "Nearly exhausted · crossed 95%", view: AnyView(QuotaProgress(model: pool("5-hour", used(96), .critical), now: now))),
    Specimen(id: "quota-exhausted", component: "QuotaProgress", caption: "Limit reached", view: AnyView(QuotaProgress(model: pool("7-day", used(100), .exhausted), now: now))),
    Specimen(id: "quota-exhausted-no-reset", component: "QuotaProgress", caption: "Limit reached, no reset time reported", view: AnyView(QuotaProgress(model: pool("5-hour", used(100), .exhaustedNoReset, reset: nil), now: now))),
    Specimen(id: "quota-overage", component: "QuotaProgress", caption: "Limit reached, paid usage evidenced", view: AnyView(QuotaProgress(model: pool("5-hour", used(100), .exhaustedOverage), now: now))),
    Specimen(id: "quota-reset-expected", component: "QuotaProgress", caption: "Reset time passed, no fresh reading yet", view: AnyView(QuotaProgress(model: pool("7-day", used(100, minutesAgo: 8), .resetExpected), now: now))),
    Specimen(id: "quota-available-again", component: "QuotaProgress", caption: "Available again, verified by a fresh reading", view: AnyView(QuotaProgress(model: pool("5-hour", used(4), .availableAgain), now: now))),
    Specimen(id: "quota-entered-by-you", component: "QuotaProgress", caption: "Manual snapshot", view: AnyView(QuotaProgress(model: pool("Weekly", used(60, minutesAgo: 25), .available, source: manual), now: now))),
    Specimen(id: "quota-stale", component: "QuotaProgress", caption: "Stale: last reading 42 minutes ago", view: AnyView(QuotaProgress(model: pool("5-hour", used(83, minutesAgo: 42), .approaching), now: now))),
    Specimen(id: "quota-not-available", component: "QuotaProgress", caption: "Provider did not send rate limits (F06)", view: AnyView(QuotaProgress(model: pool("5-hour", used(nil), .quotaNotAvailable, reset: nil), now: now))),
    Specimen(id: "quota-not-reported", component: "QuotaProgress", caption: "Provider sent null (first event, F07)", view: AnyView(QuotaProgress(model: pool("Context", used(nil, absence: .providerNull), .quotaNotAvailable, reset: nil), now: now))),
    Specimen(id: "quota-provider-error", component: "QuotaProgress", caption: "Value failed validation", view: AnyView(QuotaProgress(model: pool("5-hour", used(nil, absence: .rejectedBySanitizer), .quotaNotAvailable, reset: nil), now: now))),
    Specimen(id: "quota-disconnected", component: "QuotaProgress", caption: "Not connected", view: AnyView(QuotaProgress(model: pool("5-hour", used(nil), .disconnected, reset: nil, connection: .notConnected), now: now))),
    Specimen(id: "reset-upcoming", component: "ResetCountdown", caption: "Verified reset ahead", view: AnyView(ResetCountdown(resetsAt: resets(reset), card: .approaching, now: now))),
    Specimen(id: "reset-expected", component: "ResetCountdown", caption: "Reset time reached: never says Ready", view: AnyView(ResetCountdown(resetsAt: resets(now.addingTimeInterval(-120)), card: .resetExpected, now: now))),
    Specimen(id: "reset-unknown", component: "ResetCountdown", caption: "No reset time reported", view: AnyView(ResetCountdown(resetsAt: resets(nil), card: .exhaustedNoReset, now: now))),
    Specimen(id: "plan-user-confirmed", component: "PlanPill", caption: "User confirmed", view: AnyView(PlanPill(planName: "Max 5×", provenance: .userConfirmed))),
    Specimen(id: "plan-provider-verified", component: "PlanPill", caption: "Provider verified", view: AnyView(PlanPill(planName: "Team · Premium", provenance: .providerVerified))),
    Specimen(id: "plan-selected", component: "PlanPill", caption: "Selected, not verified", view: AnyView(PlanPill(planName: "Pro", provenance: .selectedUnverified))),
    Specimen(id: "plan-not-set", component: "PlanPill", caption: "Plan not set", view: AnyView(PlanPill(planName: nil, provenance: .notSet))),
    Specimen(id: "health-live", component: "ConnectionHealth", caption: "Live", view: AnyView(ConnectionHealth(source: claude, lastSeen: now.addingTimeInterval(-60), state: .live, now: now))),
    Specimen(id: "health-stale", component: "ConnectionHealth", caption: "No new readings", view: AnyView(ConnectionHealth(source: claude, lastSeen: now.addingTimeInterval(-42 * 60), state: .stale, now: now))),
    Specimen(id: "health-not-connected", component: "ConnectionHealth", caption: "Not connected", view: AnyView(ConnectionHealth(source: claude, lastSeen: nil, state: .notConnected, now: now))),
    Specimen(id: "source-live", component: "DataSourceLabel", caption: "Source and freshness", view: AnyView(DataSourceLabel(source: claude, observedAt: now.addingTimeInterval(-60), state: .live, showsSource: true, now: now))),
    Specimen(id: "source-stale", component: "DataSourceLabel", caption: "Stale", view: AnyView(DataSourceLabel(source: claude, observedAt: now.addingTimeInterval(-42 * 60), state: .stale, showsSource: true, now: now))),
    Specimen(id: "card-compact", component: "ProviderCard", caption: "Compact: menu bar popover", view: AnyView(
        ProviderCard(identity: .claudeCode, planName: "Max 5×", plan: .userConfirmed,
                     pools: [pool("5-hour", used(83), .approaching), pool("7-day", used(21), .available, reset: now.addingTimeInterval(2 * 86_400))],
                     session: session, layout: .compact, now: now))),
    Specimen(id: "card-expanded", component: "ProviderCard", caption: "Expanded: provider detail, reset passed", view: AnyView(
        ProviderCard(identity: .claudeCode, planName: "Max 5×", plan: .userConfirmed,
                     pools: [pool("5-hour", used(14), .available), pool("7-day", used(100, minutesAgo: 3), .resetExpected, reset: now.addingTimeInterval(-300))],
                     session: session, layout: .expanded, now: now))),
    Specimen(id: "card-no-rate-limits", component: "ProviderCard", caption: "No rate limits reported, plan not set (F06, F15)", view: AnyView(
        ProviderCard(identity: .claudeCode, planName: nil, plan: .notSet,
                     pools: [pool("5-hour", used(nil), .quotaNotAvailable, reset: nil), pool("7-day", used(nil), .quotaNotAvailable, reset: nil)],
                     session: session, layout: .compact, now: now))),
]

@MainActor
func render(_ view: some View, scheme: ColorScheme, width: CGFloat, to url: URL, glyph: Bool = false) throws -> CGSize {
    let theme = Theme.mac
    // Specimens sit on the app background with breathing room; glyphs are tight on transparency for tables.
    let framed = view
        .padding(glyph ? theme.spacing(.compact) : theme.spacing(.spacious))
        .frame(width: width, alignment: glyph ? .center : .leading)
        .background(glyph ? Color.clear : theme.color(.background, scheme))
        .environment(\.colorScheme, scheme)
        .environment(\.displayTimeZone, london)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.isFixtureData, true)
    let renderer = ImageRenderer(content: framed)
    renderer.scale = 2
    guard let image = renderer.cgImage,
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    return CGSize(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2)
}

func styleRows() -> [[String: Any]] {
    func row(_ family: String, _ state: String, _ s: StatusStyle) -> [String: Any] {
        ["family": family, "state": state, "symbol": s.symbol, "badge": s.badge ?? NSNull(), "label": s.label,
         "accessibility": s.accessibility, "role": s.role.rawValue, "pattern": s.pattern.rawValue,
         "glyph": "img/glyph-\(family)-\(state)"]
    }
    return ValueState.allCases.map { row("value", $0.rawValue, StatusStyles.of($0)) }
        + CardState.allCases.map { row("card", $0.rawValue, StatusStyles.of($0)) }
        + PlanProvenance.allCases.map { row("plan", $0.rawValue, StatusStyles.of($0)) }
}

try MainActor.assumeIsolated {
    var specimenRows: [[String: Any]] = []
    for specimen in specimens {
        var row: [String: Any] = ["id": specimen.id, "component": specimen.component, "caption": specimen.caption]
        for scheme in [ColorScheme.light, .dark] {
            let name = "\(specimen.id)-\(scheme == .light ? "light" : "dark").png"
            let size = try render(specimen.view, scheme: scheme, width: 392, to: images.appendingPathComponent(name))
            row[scheme == .light ? "light" : "dark"] = "img/\(name)"
            row["height"] = size.height
        }
        specimenRows.append(row)
    }
    // One glyph per status style, light and dark, so the table shows the real SF Symbols.
    let all: [(String, String, StatusStyle)] = ValueState.allCases.map { ("value", $0.rawValue, StatusStyles.of($0)) }
        + CardState.allCases.map { ("card", $0.rawValue, StatusStyles.of($0)) }
        + PlanProvenance.allCases.map { ("plan", $0.rawValue, StatusStyles.of($0)) }
    for (family, state, style) in all {
        for scheme in [ColorScheme.light, .dark] {
            let glyph = Image(systemName: style.symbol)
                .overlay(alignment: .bottomTrailing) { if let b = style.badge { Image(systemName: b).font(.caption2).offset(x: 4, y: 3) } }
                .font(.title3)
                .foregroundStyle(Theme.mac.color(style.role, scheme))
            _ = try render(glyph, scheme: scheme, width: 40,
                           to: images.appendingPathComponent("glyph-\(family)-\(state)-\(scheme == .light ? "light" : "dark").png"), glyph: true)
        }
    }

    let theme = Theme.mac
    var palette: [[String: Any]] = []
    for token in ColorToken.allCases {
        palette.append(["token": token.rawValue, "light": theme.rgb(token, .light).css, "dark": theme.rgb(token, .dark).css,
                        "isText": ColorToken.textTokens.contains(token)])
    }
    var contrast: [[String: Any]] = []
    for scheme in [ColorScheme.light, .dark] {
        for text in ColorToken.textTokens {
            for surface in ColorToken.surfaces {
                let ratio = RGB.contrast(theme.rgb(text, scheme), theme.rgb(surface, scheme))
                contrast.append(["scheme": scheme == .light ? "light" : "dark", "text": text.rawValue, "surface": surface.rawValue,
                                 "ratio": (ratio * 100).rounded() / 100, "passesAA": ratio >= 4.5])
            }
        }
    }
    let design: [String: Any] = [
        "generatedAt": ISO8601DateFormatter().string(from: Date()),          // clock-ok: build stamp for the page only
        "demoInstant": ISO8601DateFormatter().string(from: now),
        "palette": palette, "contrast": contrast,
        "typography": [["token": "metricDisplay", "style": "Large Title, rounded, heavy, tabular digits (pixel: 55 pt)"],
                       ["token": "metricHero", "style": "Large Title, rounded, bold, tabular digits"],
                       ["token": "metricMedium", "style": "Title 2, rounded, semibold, tabular digits"],
                       ["token": "title", "style": "Headline"], ["token": "label", "style": "Subheadline"],
                       ["token": "supporting", "style": "Footnote"], ["token": "micro", "style": "Caption 2"]],
        "spacing": SpacingToken.allCases.map { ["token": $0.rawValue, "points": theme.spacing($0)] },
        "radius": RadiusToken.allCases.map { ["token": $0.rawValue, "points": theme.radius($0)] },
        "stroke": StrokeToken.allCases.map { ["token": $0.rawValue, "points": theme.stroke($0)] },
        "styles": styleRows(),
        "specimens": specimenRows,
        "phosphor": try renderPhosphor(images: images, now: now, used: { used($0, minutesAgo: $1, absence: $2) },
                                       pool: { pool($0, $1, $2, reset: $3) }),
    ]
    let data = try JSONSerialization.data(withJSONObject: design, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try data.write(to: output.appendingPathComponent("design.json"))
    print("rendered \(specimens.count) specimens and \(all.count) glyphs, light and dark, to \(output.path)")
}
