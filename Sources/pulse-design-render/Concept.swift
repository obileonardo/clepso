import DesignSystem
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Increment 1.7b concept board: the popover, a stats strip and the menu bar icon in each candidate palette, built
// from the real DesignSystem pixel components so the founder judges what would ship. Demo values only.
// usage: pulse-design-render --concept <output dir>

@MainActor
func renderConceptBoards(to folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    PixelFonts.ensureRegistered()
    for theme in [Theme.phosphor, .ember] {
        let board = ConceptBoard()
            .environment(\.theme, theme)
            .environment(\.colorScheme, .dark)
            .environment(\.isFixtureData, false)
        let renderer = ImageRenderer(content: board)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let out = CGImageDestinationCreateWithURL(folder.appendingPathComponent("concept-\(theme.name).png") as CFURL,
                                                        UTType.png.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(out, image, nil)
        guard CGImageDestinationFinalize(out) else { throw CocoaError(.fileWriteUnknown) }
        print("concept-\(theme.name).png \(image.width / 2)x\(image.height / 2)")
    }
}

struct ConceptBoard: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing(.spacious) * 2) {
            VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
                caption("MENU BAR")
                MenuBarConcept()
                caption("POPOVER")
                PopoverConcept().frame(width: 340)
            }
            VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
                caption("STATS")
                StatsConcept().frame(width: 460)
                caption("BUTTONS")
                HStack(spacing: theme.spacing(.standard)) {
                    Button("Details") {}.buttonStyle(PixelButtonStyle(prominent: true))
                    Button("Stats") {}.buttonStyle(PixelButtonStyle())
                    Button("Settings") {}.buttonStyle(PixelButtonStyle())
                }
            }
        }
        .padding(theme.spacing(.spacious) * 2)
        .background(theme.color(.background, scheme))
        .overlay(alignment: .bottomTrailing) {
            Text("CONCEPT · \(theme.name.uppercased()) · DEMO DATA")
                .font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme)).padding(theme.spacing(.standard))
        }
    }

    func caption(_ text: String) -> some View {
        Text(text).font(theme.font(.micro)).tracking(1).foregroundStyle(theme.color(.textSecondary, scheme))
    }
}

/// Faint horizontal scanlines: a Matrix/CRT texture, decorative only.
struct Scanlines: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height { context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.white.opacity(0.035))); y += 3 }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct PopoverConcept: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        PixelPanel {
            VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
                HStack(alignment: .firstTextBaseline) {
                    Text("AI CAPACITY").font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
                    Spacer()
                    Text("LIVE · 1M AGO").font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                }
                Text("Reported limits available").font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                limit("5-HOUR", used: 14, resets: "RESETS 16:20 · IN 1H 51M", role: .statusSuccess, status: "Available")
                limit("7-DAY", used: 23, resets: "RESETS THU 05:00 · IN 4D", role: .statusSuccess, status: "Available")
                limit("SPEND", used: 87, resets: "RESETS NOV 1", role: .statusAttention, status: "Approaching limit")
                session
                HStack(spacing: theme.spacing(.standard)) {
                    Button("Details") {}.buttonStyle(PixelButtonStyle(prominent: true))
                    Button("Stats") {}.buttonStyle(PixelButtonStyle())
                    Spacer()
                }
            }
        }
        .overlay(Scanlines().clipShape(PixelRect(step: 2)))
    }

    func limit(_ scope: String, used: Int, resets: String, role: ColorToken, status: String) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
            HStack(alignment: .lastTextBaseline) {
                Text(scope).font(theme.font(.title)).foregroundStyle(theme.color(.textPrimary, scheme))
                Spacer()
                Text("\(used)").font(theme.font(.metricHero)).foregroundStyle(theme.color(.textPrimary, scheme))
                Text("%").font(theme.font(.metricMedium)).foregroundStyle(theme.color(.textSecondary, scheme))
            }
            PixelBar(fraction: Double(used) / 100, role: role, pattern: .solid)
            HStack {
                Label(status, systemImage: role == .statusSuccess ? "circle" : "circle.badge.exclamationmark")
                    .font(theme.font(.supporting)).foregroundStyle(theme.color(role, scheme))
                Spacer()
                Text(resets).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
            }
        }
    }

    var session: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
            HStack {
                Text("OPUS 5.5").font(theme.font(.title)).foregroundStyle(theme.color(.background, scheme))
                    .padding(.horizontal, theme.spacing(.compact) * 1.5).padding(.vertical, theme.spacing(.compact) / 2)
                    .background(PixelRect(step: 2).fill(theme.color(.accent, scheme)))
                Spacer()
                Text("CTX 58%").font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
            }
            PixelBar(fraction: 0.58, role: .accent, pattern: .solid, segments: 32)
            HStack {
                stat("$69.27", "COST EST")
                stat("99%", "CACHE")
                stat("+10.6K", "LINES")
                stat("2H 0M", "API TIME")
            }
        }
    }

    func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(theme.font(.label).weight(.semibold)).foregroundStyle(theme.color(.textPrimary, scheme))
            Text(label).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatsConcept: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    let weeks = 26

    var body: some View {
        PixelPanel {
            VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
                HStack {
                    Text("ACTIVITY").font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
                    Spacer()
                    Text("ALL TIME · 30D · 7D").font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                }
                heatmap.frame(height: 7 * 12)
                HStack(spacing: theme.spacing(.spacious)) {
                    big("2", "DAY STREAK")
                    big("11", "BEST STREAK")
                    big("27", "ACTIVE DAYS")
                    big("16.5B", "TOKENS")
                }
                Text("Favorite model: Opus 5.5 · 75.5% of tokens").font(theme.font(.supporting))
                    .foregroundStyle(theme.color(.textSecondary, scheme))
                ForEach([("OPUS 5.5", 0.755), ("OPUS 5", 0.131), ("FABLE 5.1", 0.057), ("SONNET 5.5", 0.056)], id: \.0) { name, share in
                    HStack(spacing: theme.spacing(.standard)) {
                        Text(name).font(theme.font(.micro)).foregroundStyle(theme.color(.textPrimary, scheme)).frame(width: 90, alignment: .leading)
                        PixelBar(fraction: share, role: .accent, pattern: .solid, segments: 30)
                        Text(String(format: "%.1f%%", share * 100)).font(theme.font(.micro))
                            .foregroundStyle(theme.color(.textSecondary, scheme)).frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
        .overlay(Scanlines().clipShape(PixelRect(step: 2)))
    }

    var heatmap: some View {
        Canvas { context, size in
            let cell = min(size.width / CGFloat(weeks), size.height / 7)
            let accent = theme.color(.accent, scheme), empty = theme.color(.surfaceMuted, scheme)
            for week in 0..<weeks {
                for day in 0..<7 {
                    // Deterministic demo pattern: quiet early, busy in the last weeks.
                    let seed = (week * 7 + day) * 2_654_435_761 % 97
                    let level = week < 18 ? (seed % 11 == 0 ? 1 : 0) : (seed % 4)
                    let rect = CGRect(x: CGFloat(week) * cell + 1, y: CGFloat(day) * cell + 1, width: cell - 2, height: cell - 2)
                    context.fill(Path(rect), with: .color(level == 0 ? empty : accent.opacity([0, 0.35, 0.65, 1][level])))
                }
            }
        }
        .accessibilityLabel("Activity heatmap, demo data")
    }

    func big(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(theme.font(.metricMedium)).foregroundStyle(theme.color(.textPrimary, scheme))
            Text(label).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
        }
    }
}

/// A pixel ring drawn on a 16×16 grid, plus the highest percentage in the number face.
struct MenuBarConcept: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    static let ring: [String] = [
        ".....######.....", "...##......##...", "..#..........#..", ".#............#.", ".#............#.", "#..............#",
        "#..............#", "#..............#", "#..............#", "#..............#", "#..............#", ".#............#.",
        ".#............#.", "..#..........#..", "...##......##...", ".....######.....",
    ]

    var body: some View {
        HStack(spacing: theme.spacing(.standard)) {
            Canvas { context, size in
                let px = size.width / 16
                for (y, row) in Self.ring.enumerated() {
                    for (x, ch) in row.enumerated() where ch == "#" {
                        context.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px, height: px)),
                                     with: .color(theme.color(.textPrimary, scheme)))
                    }
                }
            }
            .frame(width: 16, height: 16)
            Text("23%").font(theme.font(.title)).foregroundStyle(theme.color(.textPrimary, scheme))
        }
        .padding(.horizontal, theme.spacing(.standard)).padding(.vertical, theme.spacing(.compact))
        .background(PixelRect(step: 2).fill(theme.color(.surfaceMuted, scheme)))
    }
}
