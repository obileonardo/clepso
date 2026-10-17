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
        #expect(abs(worst.ratio - 4.71) < 0.01, "DESIGN_SYSTEM.md claims the worst case is 4.71:1; measured \(worst.ratio) for \(worst.what)")
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
        for theme in [Theme.phosphor, .ember] {
            for text in ColorToken.textTokens {
                for surface in ColorToken.surfaces {
                    let ratio = RGB.contrast(theme.rgb(text, .dark), theme.rgb(surface, .dark))
                    #expect(ratio >= 4.5, "\(theme.name): \(text) on \(surface): \(ratio)")
                }
            }
        }
    }

    @Test("The bundled pixel faces register and resolve to their own families, not a fallback")
    func pixelFonts() {
        #expect(PixelFonts.ensureRegistered())
        for family in [PixelFonts.display, PixelFonts.number, PixelFonts.terminal] {
            let font = CTFontCreateWithName(family as CFString, 12, nil)
            #expect(CTFontCopyFamilyName(font) as String == family, "\(family) resolved to \(CTFontCopyFamilyName(font))")
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
    @Test("Connection first, then the absence reason, then freshness (DESIGN_SYSTEM §1)")
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
