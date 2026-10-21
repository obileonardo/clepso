import ClaudeCodeAdapter
import DesignSystem
import SwiftUI

/// The chosen model in full, after the founder's references: Life Reset's character profile (a framed sprite with a
/// name plate beside a table of stats, then a level card with an XP bar), Nike Run Club's "X to the next level" with
/// the level's range, and Revolut Business's detail panel of labelled rows.
struct ModelDossier: View {
    let entry: ModelsRoster.Entry
    let range: StatsSummary.Range
    /// `ModelsRoster.activity`: one level 0…4 per day (or per week).
    let activity: [Int]
    let weekly: Bool
    let from: String
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @State private var characterPaused = false
    @Environment(\.reduceMotion) private var reduceMotion

    var role: ColorToken { ModelStyle.role(entry.style) }
    var gap: CGFloat { theme.spacing(.standard) + theme.spacing(.compact) }

    var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            HStack(alignment: .top, spacing: gap) {
                portrait
                stats.frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .fixedSize(horizontal: false, vertical: true)
            levelCard
            facts
            activityStrip
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Copy.ModelsPage.dossierLabel(entry.name))
    }

    /// Life Reset's portrait: the sprite in a frame of the model's colour, its name on a plate underneath, the rank in
    /// the corner.
    var portrait: some View {
        let px = theme.stroke(.hairline) * 2
        return VStack(spacing: 0) {
            ModelSprite(modelID: entry.id, animated: !characterPaused)
                .frame(width: theme.spacing(.spacious) * 8, height: theme.spacing(.spacious) * 6.5)
            HStack(spacing: theme.spacing(.standard)) {
                InfoButton(title: Copy.ModelsPage.characterAbout, text: Copy.ModelsPage.characterExplanation(entry.id)) {
                    Text(Copy.ModelsPage.characterDetails)
                }
                Spacer(minLength: theme.spacing(.compact))
                Button { characterPaused.toggle() } label: {
                    Text(reduceMotion ? Copy.ModelsPage.characterStill : characterPaused ? Copy.ModelsPage.characterResume : Copy.ModelsPage.characterPause)
                }
                .buttonStyle(PixelPlainButtonStyle())
                .accessibilityLabel(characterPaused ? Copy.ModelsPage.characterResumeLabel : Copy.ModelsPage.characterPauseLabel)
                .accessibilityValue(reduceMotion ? Copy.ModelsPage.characterReduced : characterPaused ? Copy.ModelsPage.characterPaused : Copy.ModelsPage.characterPlaying)
                .disabled(reduceMotion)
            }
            .font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
            .padding(theme.spacing(.standard))
            Rectangle().fill(theme.color(role, scheme)).frame(height: px)
            Text(entry.name.uppercased()).font(theme.font(.title)).foregroundStyle(theme.color(.textPrimary, scheme))
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, theme.spacing(.standard))
                .background(theme.color(.surfaceElevated, scheme))
        }
        .frame(width: theme.spacing(.spacious) * 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.color(.surfaceMuted, scheme))
        .clipShape(PixelRect(step: px))
        .overlay(PixelRect(step: px).strokeBorder(theme.color(role, scheme), lineWidth: px))
        .overlay(alignment: .topLeading) {
            Text(Copy.ModelsPage.rank(entry.rank)).font(theme.font(.title)).monospacedDigit().foregroundStyle(theme.color(.background, scheme))
                .padding(.horizontal, theme.spacing(.standard)).padding(.vertical, theme.spacing(.compact) / 2)
                .background(PixelRect(step: px).fill(theme.color(role, scheme)))
                .padding(px * 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Copy.ModelsPage.rowLabel(rank: entry.rank, name: entry.name, level: entry.level?.level,
                                                     tokens: ModelsRoster.spoken(entry.share.tokens), share: ModelsRoster.spokenPercent(entry.share.share)))
        .accessibilityAddTraits(.isHeader)
    }

    /// Life Reset's stat table: the four kinds of token as rows, output first and lit, because it is the one that counts.
    @ViewBuilder var stats: some View {
        let px = theme.stroke(.hairline) * 2
        VStack(alignment: .leading, spacing: 0) {
            Text(Copy.Stats.tokenKinds).font(theme.font(.micro)).tracking(1).foregroundStyle(theme.color(.textSecondary, scheme))
                .padding(.horizontal, gap).padding(.vertical, theme.spacing(.standard))
                .frame(maxWidth: .infinity, alignment: .leading)
            if let kinds = entry.kinds {
                ForEach(kinds, id: \.kind) { KindRow(kind: $0, role: role) }
            } else {
                Text(Copy.ModelsPage.kindsUnknown).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(gap)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(PixelRect(step: px).fill(theme.color(.surfaceElevated, scheme)))
        .overlay(PixelRect(step: px).strokeBorder(theme.color(.separator, scheme), lineWidth: theme.stroke(.hairline)))
    }

    /// Life Reset's "Level 5 · 197 XP to Lvl 6" card with Nike's range under the bar: the level chip, how much output
    /// to the next level, the segmented bar, the two targets, and the output written so far on the right.
    @ViewBuilder var levelCard: some View {
        if let level = entry.level {
            let top = level.next <= level.floor          // past the last target on the ladder
            HStack(alignment: .center, spacing: theme.spacing(.spacious)) {
                LevelChip(level: level.level, role: role, large: true)
                VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                    Text(Copy.ModelsPage.toNext(Formatting.compact(max(0, level.next - level.output)), level.level + 1))
                        .font(theme.font(.label)).monospacedDigit().foregroundStyle(theme.color(.textPrimary, scheme))
                    PixelBar(fraction: top ? 1 : level.progress, role: role, pattern: .solid, segments: 32)
                    HStack {
                        Text(Copy.ModelsPage.levelFrom(level.level, Formatting.compact(level.floor))).foregroundStyle(theme.color(role, scheme))
                        Spacer(minLength: theme.spacing(.standard))
                        Text(Copy.ModelsPage.levelFrom(level.level + 1, Formatting.compact(level.next))).foregroundStyle(theme.color(.textSecondary, scheme))
                    }
                    .font(theme.font(.micro)).monospacedDigit()
                }
                VStack(alignment: .trailing, spacing: theme.spacing(.compact) / 2) {
                    Text(Formatting.compact(level.output)).font(theme.font(.metricMedium)).monospacedDigit().foregroundStyle(theme.color(.textPrimary, scheme))
                    Text(Copy.ModelsPage.outputWritten).font(theme.font(.micro)).tracking(1).foregroundStyle(theme.color(.textSecondary, scheme))
                }
                .fixedSize()
            }
            .pageCard()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Copy.Stats.levelLabel(level.level, output: ModelsRoster.spoken(level.output), next: ModelsRoster.spoken(level.next)))
            .accessibilityValue(Copy.Stats.outputOf(ModelsRoster.spoken(level.output), ModelsRoster.spoken(level.next),
                                                    toGo: ModelsRoster.spoken(max(0, level.next - level.output))))
        } else {
            HStack(spacing: theme.spacing(.spacious)) {
                LevelChip(level: nil, role: role, large: true)
                Text(Copy.ModelsPage.levelUnknownLine).font(theme.font(.supporting))
                    .foregroundStyle(theme.color(.textSecondary, scheme)).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .pageCard()
            .accessibilityElement(children: .combine)
        }
    }

    /// Revolut's detail panel: labelled rows, value on the right.
    var facts: some View {
        let px = theme.stroke(.hairline) * 2
        return VStack(alignment: .leading, spacing: 0) {
            FactLine(label: Copy.ModelsPage.factSpecialty) { specialtyChip }
            FactLine(label: Copy.ModelsPage.factTokens(range)) { value(Formatting.compact(entry.share.tokens)) }
            FactLine(label: Copy.ModelsPage.factShare) { value(ModelsRoster.percent(entry.share.share)) }
            FactLine(label: Copy.ModelsPage.factActive, divider: false) {
                value("\(entry.activeDays)").accessibilityLabel("\(entry.activeDays)")
            }
        }
        .padding(.horizontal, gap)
        .background(PixelRect(step: px).fill(theme.color(.surfaceElevated, scheme)))
        .overlay(PixelRect(step: px).strokeBorder(theme.color(.separator, scheme), lineWidth: theme.stroke(.hairline)))
    }

    func value(_ text: String) -> some View {
        Text(text).font(theme.font(.label)).monospacedDigit().foregroundStyle(theme.color(.textPrimary, scheme))
    }

    /// The specialty; its (?) says what it means in this model's own numbers, then the general rule.
    var specialtyChip: some View {
        let title = entry.specialty.map { Copy.Stats.specialty($0.kind.doing, times: $0.ratio) } ?? Copy.ModelsPage.specialtyUnknown
        let text = entry.specialty.map { Copy.ModelsPage.specialtyExplained(entry.name, kind: $0.kind, times: $0.ratio) + "\n\n" + Copy.Stats.specialtyRule }
            ?? Copy.ModelsPage.kindsUnknown
        return InfoButton(title: Copy.ModelsPage.specialtyAbout(entry.name), text: text, value: title) {
            HStack(spacing: theme.spacing(.standard)) {
                Text(title).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                PixelIcon(.question).foregroundStyle(theme.color(.textSecondary, scheme))
            }
        }
    }

    /// One row of cells across the range in the activity calendar's pixel vocabulary (`PixelDensity`): each cell a
    /// muted ground of whole 2-point pixels, lit in the model's colour as sparse dots, a checkerboard, solid with
    /// holes, or solid by how many tokens it used (no tokens: the plain ground). The cells span the full width, so the
    /// first sits under the range's start and the last under TODAY; they are as wide as the range allows (seven days
    /// make wide cells, a long range one-pixel columns), and as tall as an odd number of pixels.
    var activityStrip: some View {
        let px = theme.stroke(.hairline) * 2
        let height = Self.stripHeight(theme)
        return VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            HStack {
                Text(Copy.ModelsPage.activityTitle).font(theme.font(.micro)).tracking(1).foregroundStyle(theme.color(.textSecondary, scheme))
                Spacer()
                Text(StatsFormat.day(from).uppercased() + " – " + Copy.ModelsPage.today).font(theme.font(.micro))
                    .foregroundStyle(theme.color(.textSecondary, scheme))
            }
            Canvas { context, size in
                let ground = theme.color(.surfaceMuted, scheme), lit = theme.color(role, scheme)
                for (rect, level) in zip(Self.stripCells(count: activity.count, width: size.width, height: height, px: px), activity) {
                    context.fill(PixelDensity.pixels(level: 4, in: rect, px: px), with: .color(ground))
                    if level > 0 { context.fill(PixelDensity.pixels(level: min(level, 4), in: rect, px: px), with: .color(lit)) }
                }
            }
            .frame(height: height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.ModelsPage.activityLabel(entry.name, days: entry.activeDays, weekly: weekly))
    }

    /// The strip's height: the largest odd number of 2-point pixels within the spacious spacing (18 pt in Phosphor,
    /// 14 pt in the 16-point themes), so each pattern sits centred top to bottom.
    static func stripHeight(_ theme: Theme) -> CGFloat {
        let px = theme.stroke(.hairline) * 2, rows = Int((theme.spacing(.spacious) / px).rounded(.down))
        return CGFloat(max(1, rows % 2 == 0 ? rows - 1 : rows)) * px
    }

    /// `count` cells across `width`, on whole pixels of `px` from the left edge: the pixels shared out as evenly as
    /// whole pixels allow, one pixel between cells while every cell keeps at least one of its own, and none when the
    /// range is too long for that (then cells touch). The last cell ends within a pixel of the right edge.
    static func stripCells(count: Int, width: CGFloat, height: CGFloat, px: CGFloat) -> [CGRect] {
        guard count > 0, px > 0 else { return [] }
        let total = Int((width / px).rounded(.down))
        let gap = total + 1 >= count * 2 ? 1 : 0
        return (0..<count).map { i in
            let start = i * (total + gap) / count, end = (i + 1) * (total + gap) / count - gap
            return CGRect(x: CGFloat(start) * px, y: 0, width: CGFloat(max(0, end - start)) * px, height: height)
        }
    }
}

/// A grey label and a value on the right, a faint rule under it (Revolut's detail rows).
struct FactLine<Value: View>: View {
    let label: String
    var divider = true
    @ViewBuilder let value: () -> Value
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
            Spacer(minLength: theme.spacing(.standard))
            value()
        }
        .padding(.vertical, theme.spacing(.standard) + theme.spacing(.compact) / 2)
        .overlay(alignment: .bottom) {
            if divider { Rectangle().fill(theme.color(.separator, scheme).opacity(0.5)).frame(height: theme.stroke(.hairline)) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One kind of token as a stat row: its name, its value, its part of this model's tokens, and a (?) with what the
/// kind is. Output's row is lit in the model's colour and badged, because it is the only kind that counts for level.
struct KindRow: View {
    let kind: ModelsRoster.Kind
    let role: ColorToken
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let counts = kind.countsForLevel
        HStack(alignment: .center, spacing: theme.spacing(.standard)) {
            Rectangle().fill(theme.color(counts ? role : .separator, scheme)).frame(width: theme.stroke(.hairline) * 2)
            Text(kind.kind.name.uppercased()).font(theme.font(.micro)).tracking(1)
                .foregroundStyle(theme.color(counts ? .textPrimary : .textSecondary, scheme)).lineLimit(1).fixedSize()
            if counts {
                Text(Copy.Stats.countsForLevel).font(theme.font(.micro)).foregroundStyle(theme.color(.accent, scheme)).lineLimit(1).fixedSize()
            }
            Spacer(minLength: theme.spacing(.standard))
            Text(ModelsRoster.percent(kind.fraction)).font(theme.font(.supporting)).monospacedDigit()
                .foregroundStyle(theme.color(.textSecondary, scheme)).lineLimit(1).fixedSize()
            Text(Formatting.compact(kind.tokens)).font(theme.font(.title)).monospacedDigit().foregroundStyle(theme.color(.textPrimary, scheme))
                .lineLimit(1).fixedSize()
                .frame(minWidth: theme.spacing(.spacious) * 4, alignment: .trailing)
            InfoButton(title: Copy.ModelsPage.aboutKind(kind.kind.name), text: kind.kind.definition) {
                PixelIcon(.question).foregroundStyle(theme.color(.textSecondary, scheme))
            }
        }
        .padding(.trailing, theme.spacing(.standard) + theme.spacing(.compact))
        .padding(.vertical, theme.spacing(.standard))
        .background(counts ? theme.color(role, scheme).opacity(0.12) : .clear)
        .overlay(alignment: .top) { Rectangle().fill(theme.color(.separator, scheme).opacity(0.5)).frame(height: theme.stroke(.hairline)) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Copy.ModelsPage.kindLabel(kind.kind.name, value: ModelsRoster.spoken(kind.tokens),
                                                      pct: ModelsRoster.spokenPercent(kind.fraction), counts: counts))
    }
}

extension ModelSpecialty.Kind {
    var name: String {
        switch self {
        case .output: Copy.Stats.output
        case .input: Copy.Stats.input
        case .cacheRead: Copy.Stats.cacheRead
        case .cacheWrite: Copy.Stats.cacheWrite
        }
    }

    /// What the kind is and whether it counts for level (`Copy.Stats.kindDefinitions`).
    var definition: String {
        let entry = Copy.Stats.kindDefinitions.first { $0.0 == name }
        return (entry?.1 ?? "") + " " + (entry?.2 == true ? Copy.Stats.countsForLevel : Copy.Stats.notForLevel).capitalized + "."
    }
}

/// A (?) that opens a short explanation: Space or Return opens it, Esc closes it, and VoiceOver reads the same text as
/// the button's hint, so nothing is hidden behind a pointer.
struct InfoButton<Label: View>: View {
    let title: String
    let text: String
    var value: String? = nil
    @ViewBuilder let label: () -> Label
    @State private var shown = false
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button { shown.toggle() } label: { label() }
            .buttonStyle(PixelPlainButtonStyle())
            .accessibilityLabel(title)
            .accessibilityValue(value ?? "")
            .accessibilityHint(text)
            .popover(isPresented: $shown, arrowEdge: .bottom) {
                Text(text).font(theme.font(.supporting)).foregroundStyle(theme.color(.textPrimary, scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: PageMetrics.labelColumn + theme.spacing(.spacious) * 2, alignment: .leading)
                    .padding(theme.spacing(.windowPadding))
                    .presentationBackground(theme.color(.surfaceElevated, scheme))
                    .environment(\.theme, theme)
                    .environment(\.colorScheme, scheme)
            }
    }
}
