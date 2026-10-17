import SwiftUI

// Layer 1: primitives. The only place raw colour values live (DESIGN_SYSTEM.md §2). The founder may
// change any value here; `ThemeContrastTests` reports any text token that falls below 4.5:1.

/// An sRGB colour as a 24-bit hex value, so contrast can be computed exactly in tests and on the website.
public struct RGB: Sendable, Equatable, Codable {
    public let hex: UInt32
    public init(_ hex: UInt32) { self.hex = hex }
    public var red: Double { Double((hex >> 16) & 0xFF) / 255 }
    public var green: Double { Double((hex >> 8) & 0xFF) / 255 }
    public var blue: Double { Double(hex & 0xFF) / 255 }
    public var css: String { String(format: "#%06X", hex) }

    /// WCAG 2.x relative luminance.
    public var luminance: Double {
        func channel(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    public static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (l1, l2) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
        return (l1 + 0.05) / (l2 + 0.05)
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
}

// Layer 2: semantic tokens (PRD §25.2, DESIGN_SYSTEM.md §2).

public enum ColorToken: String, CaseIterable, Sendable, Codable {
    case background, surfaceElevated, surfaceMuted, separator
    case textPrimary, textSecondary, accent
    case statusSuccess, statusAttention, statusBlocked, statusStale, statusUnknown

    /// Tokens drawn as text, which must reach 4.5:1 against every surface.
    public static let textTokens: [ColorToken] = [.textPrimary, .textSecondary, .accent, .statusSuccess,
                                                  .statusAttention, .statusBlocked, .statusStale, .statusUnknown]
    public static let surfaces: [ColorToken] = [.background, .surfaceElevated, .surfaceMuted]
}

public enum TypographyToken: String, CaseIterable, Sendable { case metricHero, metricMedium, title, label, supporting, micro }
public enum SpacingToken: String, CaseIterable, Sendable { case compact, standard, spacious, windowPadding }
public enum RadiusToken: String, CaseIterable, Sendable { case control, card, pill }
public enum StrokeToken: String, CaseIterable, Sendable { case hairline, emphasis, focus }
public enum MotionToken: String, CaseIterable, Sendable { case ringFill, stateChange }

/// How text is set: the system faces, or the pixel faces of increment 1.7b (bundled under the SIL OFL).
public enum Typeface: String, Sendable { case system, pixel }

/// One theme value, injected through the environment. Components read only from here.
public struct Theme: Sendable {
    public var palette: [ColorToken: (light: RGB, dark: RGB)]
    public var spacingValues: [SpacingToken: CGFloat]
    public var radiusValues: [RadiusToken: CGFloat]
    public var strokeValues: [StrokeToken: CGFloat]
    public var typeface: Typeface = .system
    public var name = "mac"

    public func rgb(_ token: ColorToken, _ scheme: ColorScheme) -> RGB {
        let pair = palette[token] ?? (RGB(0xFF00FF), RGB(0xFF00FF))   // magenta: a missing token is visible, never silent
        return scheme == .dark ? pair.dark : pair.light
    }

    public func color(_ token: ColorToken, _ scheme: ColorScheme) -> Color { rgb(token, scheme).color }
    public func spacing(_ token: SpacingToken) -> CGFloat { spacingValues[token] ?? 8 }
    public func radius(_ token: RadiusToken) -> CGFloat { radiusValues[token] ?? 6 }
    public func stroke(_ token: StrokeToken) -> CGFloat { strokeValues[token] ?? 1 }

    /// The system text style behind each sentence-text token in the pixel theme. On macOS at the default size,
    /// body is 13 pt and callout 12 pt (caption, footnote and subheadline are 10–11 pt, too small; 1.8 review).
    public static func pixelTextStyle(_ token: TypographyToken) -> Font.TextStyle? {
        switch token {
        case .label: .body
        case .supporting, .micro: .callout
        case .metricHero, .metricMedium, .title: nil
        }
    }

    /// Dynamic Type styles, so every size scales with the user's text-size setting. Pixel faces scale too
    /// (`relativeTo:`); long text stays in the system face (monospaced in the pixel theme) for legibility.
    public func font(_ token: TypographyToken) -> Font {
        if typeface == .pixel {
            PixelFonts.ensureRegistered()
            return switch token {
            // Silkscreen for figures: its 5 and S differ clearly (in Pixelify Sans "8.5B" read as "8.SB").
            // Increment 1.8 (founder review): nothing under 12 pt. Pixel faces carry figures, titles and buttons;
            // captions moved from 8 pt pixel type to a monospaced face at 12 pt or more (`pixelTextStyle`).
            case .metricHero: .custom(PixelFonts.display, size: 34, relativeTo: .largeTitle)
            case .metricMedium: .custom(PixelFonts.display, size: 22, relativeTo: .title2)
            case .title: .custom(PixelFonts.display, size: 15, relativeTo: .headline)
            case .label: .system(Self.pixelTextStyle(.label) ?? .body, design: .monospaced).weight(.medium)
            case .supporting: .system(Self.pixelTextStyle(.supporting) ?? .callout, design: .monospaced)
            case .micro: .system(Self.pixelTextStyle(.micro) ?? .callout, design: .monospaced).weight(.semibold)
            }
        }
        return switch token {
        case .metricHero: .system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit()
        case .metricMedium: .system(.title2, design: .rounded).weight(.semibold).monospacedDigit()
        case .title: .headline
        case .label: .subheadline
        case .supporting: .footnote
        case .micro: .caption2
        }
    }

    /// nil when Reduce Motion is on: no animation at all, not a shorter one.
    public func motion(_ token: MotionToken, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return switch token {
        case .ringFill: .easeInOut(duration: 0.35)
        case .stateChange: .easeOut(duration: 0.2)
        }
    }

    public static let mac = Theme(
        palette: [
            .background: (RGB(0xF2F2F7), RGB(0x1C1C1E)),
            .surfaceElevated: (RGB(0xFFFFFF), RGB(0x2C2C2E)),
            .surfaceMuted: (RGB(0xE5E5EA), RGB(0x3A3A3C)),
            .separator: (RGB(0xC7C7CC), RGB(0x48484A)),
            .textPrimary: (RGB(0x1C1C1E), RGB(0xF5F5F7)),
            .textSecondary: (RGB(0x5A5A64), RGB(0xB0B0BA)),
            .accent: (RGB(0x1D4FD7), RGB(0x7FA8FF)),
            .statusSuccess: (RGB(0x15703B), RGB(0x4CD47A)),
            .statusAttention: (RGB(0x8A4F00), RGB(0xF2B544)),
            .statusBlocked: (RGB(0xB42318), RGB(0xFF8A7E)),
            .statusStale: (RGB(0x5F5F6B), RGB(0xA8A8B3)),
            .statusUnknown: (RGB(0x62626E), RGB(0xA6A6B1)),
        ],
        spacingValues: [.compact: 4, .standard: 8, .spacious: 16, .windowPadding: 12],
        radiusValues: [.control: 6, .card: 10, .pill: 999],
        strokeValues: [.hairline: 1, .emphasis: 2, .focus: 2])

    // Increment 1.7b concept palettes (founder references: Matrix, Tesla Roadster, Hearth's glass, a pixel UI pack).
    // Dark in both appearances: the same value is given for light and dark. Contrast is tested like `mac`.

    /// Phosphor: near-black glass, phosphor green, Roadster-white type. Increment 1.13 adds its light mode: warm
    /// paper, ink-dark text and a deeper phosphor green, at the same 4.5:1 floor for every text colour on every surface.
    public static let phosphor = Theme(
        palette: [
            .background: (RGB(0xF3F1E7), RGB(0x060907)),
            .surfaceElevated: (RGB(0xFBFAF4), RGB(0x0D1410)),
            .surfaceMuted: (RGB(0xE4E0D0), RGB(0x16211A)),
            .separator: (RGB(0xB9B29C), RGB(0x2C4034)),
            .textPrimary: (RGB(0x0F1A13), RGB(0xEAF7EE)),
            .textSecondary: (RGB(0x44564A), RGB(0x93B9A0)),
            .accent: (RGB(0x0A7238), RGB(0x4DFF8F)),
            .statusSuccess: (RGB(0x0A7238), RGB(0x4DFF8F)),
            .statusAttention: (RGB(0x7E4C00), RGB(0xFFC04D)),
            .statusBlocked: (RGB(0xAD241C), RGB(0xFF6B5E)),
            .statusStale: (RGB(0x52605A), RGB(0x9AAFA2)),
            .statusUnknown: (RGB(0x56615B), RGB(0x98A79E)),
        ],
        spacingValues: [.compact: 4, .standard: 8, .spacious: 20, .windowPadding: 16],
        radiusValues: [.control: 2, .card: 2, .pill: 2],
        strokeValues: [.hairline: 1, .emphasis: 2, .focus: 2],
        typeface: .pixel, name: "phosphor")

    /// Ember: the pixel pack's warm browns and amber, on dark glass.
    public static let ember = Theme(
        palette: dark([
            .background: RGB(0x130D09), .surfaceElevated: RGB(0x221811), .surfaceMuted: RGB(0x33241A), .separator: RGB(0x6B4A33),
            .textPrimary: RGB(0xF7E7D0), .textSecondary: RGB(0xD3B48E), .accent: RGB(0xF4AE55),
            .statusSuccess: RGB(0xA5E58A), .statusAttention: RGB(0xF4AE55), .statusBlocked: RGB(0xFF7A63),
            .statusStale: RGB(0xBFA88F), .statusUnknown: RGB(0xBBA690),
        ]),
        spacingValues: [.compact: 4, .standard: 8, .spacious: 16, .windowPadding: 12],
        radiusValues: [.control: 2, .card: 2, .pill: 2],
        strokeValues: [.hairline: 1, .emphasis: 2, .focus: 2],
        typeface: .pixel, name: "ember")

    public static let all: [Theme] = [.mac, .phosphor, .ember]

    static func dark(_ colors: [ColorToken: RGB]) -> [ColorToken: (light: RGB, dark: RGB)] {
        colors.mapValues { ($0, $0) }
    }
}

extension EnvironmentValues {
    @Entry public var theme: Theme = .mac
    /// Stale after 10 minutes (DECISIONS B2).
    @Entry public var staleAfter: TimeInterval = 600
    /// True for demo or fixture data: every value then carries a DEMO badge.
    @Entry public var isFixtureData: Bool = false
    /// Display time zone; stored instants never change with it (fixture F16).
    @Entry public var displayTimeZone: TimeZone = .current
}
