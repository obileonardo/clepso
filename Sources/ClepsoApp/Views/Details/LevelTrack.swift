import DesignSystem
import SwiftUI

/// "How levels work" as a picture (Nike's run levels, Noom's characters on the ladder, Azar's level chips): a pixel
/// track of levels 1–20, grouped by power of ten so the 1-2-5 rhythm shows, each model's sprite standing on its level,
/// the chosen model's levels lit and its next one marked NEXT. Under it the four kinds of token as chips with their
/// definitions, and the rank, specialty and scope rules behind one disclosure.
struct LevelTrack: View {
    let roster: ModelsRoster
    let selected: String
    let onSelect: (String) -> Void
    @State private var width: CGFloat = 0
    @State private var rulesOpen = false
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
            VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                Text(Copy.ModelsPage.trackTitle.uppercased()).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
                    .accessibilityAddTraits(.isHeader)
                Text(Copy.ModelsPage.trackIntro(roster.range)).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                .padding(.bottom, -theme.spacing(.spacious))
            let metrics = Self.metrics(width: width, levels: roster.trackLength, gap: gap, decadeGap: decadeGap, minimum: minimumCell)
            Group {
                if metrics.scrolls {
                    ScrollView(.horizontal) { track(metrics.cell) }.scrollIndicators(.visible)
                } else {
                    track(metrics.cell)
                }
            }
            // minWidth 0: a track sized for a wider window must not widen this stack, or the measure above reads the
            // stack's width and the track never narrows (the Arena ran past the window after it was made narrower).
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            if !roster.unplaced.isEmpty {
                Text(Copy.ModelsPage.levelUnknownList(roster.unplaced.map(\.name))).font(theme.font(.supporting))
                    .foregroundStyle(theme.color(.textSecondary, scheme)).fixedSize(horizontal: false, vertical: true)
            }
            chips
            rules
        }
        .padding(.vertical, theme.spacing(.section))
        .overlay(alignment: .top) { Rectangle().fill(theme.color(.separator, scheme)).frame(height: theme.stroke(.hairline)) }
    }

    var gap: CGFloat { theme.stroke(.hairline) * 2 }
    var decadeGap: CGFloat { theme.spacing(.standard) + theme.spacing(.compact) }
    /// Narrow enough for "500M" in the 12 pt face; below it the track scrolls sideways instead of squeezing.
    var minimumCell: CGFloat { theme.spacing(.standard) * 4 }
    var sprite: CGFloat { theme.spacing(.spacious) * 1.75 }

    /// Each cell's width for the space available: cells share what is left after the gaps (a wider one between powers
    /// of ten), never narrower than `minimum`; when that would not fit, the track scrolls.
    nonisolated static func metrics(width: CGFloat, levels: Int, gap: CGFloat, decadeGap: CGFloat, minimum: CGFloat) -> (cell: CGFloat, scrolls: Bool) {
        let decades = Set((1...max(1, levels)).map(ModelsRoster.Slot.decade(of:))).count
        let gaps = CGFloat(max(0, levels - decades)) * gap + CGFloat(max(0, decades - 1)) * decadeGap
        let cell = ((width - gaps) / CGFloat(max(1, levels))).rounded(.down)
        return cell >= minimum ? (cell, false) : (minimum, true)
    }

    func track(_ cell: CGFloat) -> some View {
        let slots = roster.track
        let chosen = roster.resolve(selected)
        let next = roster.nextLevel(for: selected)
        let stack = min(3, slots.map(\.models.count).max() ?? 0)
        return HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(slots.enumerated()), id: \.element.level) { i, slot in
                column(slot, cell: cell, chosen: chosen, next: next, stack: max(1, stack))
                    .padding(.leading, i == 0 ? 0 : slot.decade != slots[i - 1].decade ? decadeGap : gap)
            }
        }
    }

    func column(_ slot: ModelsRoster.Slot, cell: CGFloat, chosen: ModelsRoster.Entry?, next: Int?, stack: Int) -> some View {
        let px = theme.stroke(.hairline) * 2
        let current = chosen?.level?.level
        let isCurrent = slot.level == current, isNext = slot.level == next
        let reached = current.map { slot.level < $0 } ?? false
        let role = chosen.map { ModelStyle.role($0.style) } ?? .accent
        let shown = slot.models.count > stack ? Array(slot.models.prefix(stack - 1)) : slot.models
        let target = slot.level == 1 ? "0" : Formatting.compact(slot.target)
        return VStack(spacing: theme.spacing(.compact)) {
            VStack(spacing: theme.spacing(.compact)) {
                Spacer(minLength: 0)
                ForEach(shown) { entry in spriteButton(entry, chosen: entry.id == chosen?.id) }
                if slot.models.count > shown.count {
                    Text("+\(slot.models.count - shown.count)").font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                        .frame(height: sprite)
                }
            }
            .frame(height: CGFloat(stack) * (sprite + px * 2 + theme.spacing(.compact)))
            Text(isNext ? Copy.ModelsPage.next : " ").font(theme.font(.micro)).foregroundStyle(theme.color(.accent, scheme))
                .lineLimit(1).fixedSize()
                .accessibilityHidden(true)
            ZStack {
                if isNext {
                    PixelRect(step: px).fill(theme.color(.background, scheme))
                    PixelRect(step: px).strokeBorder(theme.color(.accent, scheme), lineWidth: px)
                } else {
                    PixelRect(step: px).fill(isCurrent ? theme.color(role, scheme) : reached ? theme.color(role, scheme).opacity(0.35)
                                             : theme.color(.surfaceMuted, scheme))
                }
                Text("\(slot.level)").font(theme.font(.micro)).monospacedDigit()
                    .foregroundStyle(theme.color(isCurrent ? .background : isNext ? .accent : reached ? .textPrimary : .textSecondary, scheme))
            }
            .frame(height: theme.spacing(.spacious) * 1.5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Copy.ModelsPage.cellLabel(slot.level, target: ModelsRoster.spoken(slot.target), models: slot.models.map(\.name), next: isNext))
            Text(target).font(theme.font(.micro)).monospacedDigit().lineLimit(1).fixedSize()
                .foregroundStyle(theme.color(isCurrent || isNext ? .textPrimary : .textSecondary, scheme))
                .accessibilityHidden(true)
        }
        .frame(width: cell)
    }

    /// A model on the track; choosing it chooses it in the roster too.
    func spriteButton(_ entry: ModelsRoster.Entry, chosen: Bool) -> some View {
        let px = theme.stroke(.hairline) * 2
        let label = Copy.ModelsPage.spriteLabel(entry.name, entry.level?.level ?? 0)
        return Button { onSelect(entry.id) } label: {
            ModelSprite(family: ModelSprite.Family(entry.id), role: ModelStyle.role(entry.style), animated: chosen)
                .frame(width: sprite, height: sprite)
                .padding(px)
                .background { if chosen { PixelRect(step: px).fill(theme.color(.surfaceMuted, scheme)) } }
                .overlay { if chosen { PixelRect(step: px).strokeBorder(theme.color(.accent, scheme), lineWidth: px / 2) } }
        }
        .buttonStyle(PixelPlainButtonStyle())
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// Azar's "How to level up": one card for what counts (output) and one for what doesn't, each kind a chip whose (?)
    /// opens its definition.
    var chips: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            Text(Copy.ModelsPage.howTitle).font(theme.font(.micro)).tracking(1).foregroundStyle(theme.color(.textSecondary, scheme))
            HStack(alignment: .top, spacing: theme.spacing(.standard) + theme.spacing(.compact)) { howCards }
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder var howCards: some View {
        howCard(glyph: .trend, role: .accent, title: Copy.ModelsPage.howOutputTitle, line: Copy.ModelsPage.howOutputLine, kinds: [.output])
        howCard(glyph: .nosign, role: .textSecondary, title: Copy.ModelsPage.howOtherTitle, line: Copy.ModelsPage.howOtherLine,
                kinds: [.input, .cacheRead, .cacheWrite])
    }

    func howCard(glyph: PixelGlyph, role: ColorToken, title: String, line: String, kinds: [ModelSpecialty.Kind]) -> some View {
        let px = theme.stroke(.hairline) * 2
        return HStack(alignment: .top, spacing: theme.spacing(.standard) + theme.spacing(.compact)) {
            PixelIcon(glyph, size: 18).foregroundStyle(theme.color(role, scheme))
                .frame(width: theme.spacing(.spacious) * 2, height: theme.spacing(.spacious) * 2)
                .background(PixelRect(step: px).fill(theme.color(.surfaceMuted, scheme)))
            VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                Text(title).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                Text(line).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: theme.spacing(.standard)) {
                    ForEach(kinds, id: \.self) { kind in
                        InfoButton(title: Copy.ModelsPage.aboutKind(kind.name), text: kind.definition) {
                            HStack(spacing: theme.spacing(.compact)) {
                                Text(kind.name.uppercased()).font(theme.font(.micro)).tracking(1)
                                    .foregroundStyle(theme.color(kind == .output ? .accent : .textSecondary, scheme))
                                PixelIcon(.question).foregroundStyle(theme.color(.textSecondary, scheme))
                            }
                            .lineLimit(1).fixedSize()
                            .padding(.horizontal, theme.spacing(.standard))
                            .padding(.vertical, theme.spacing(.compact) / 2)
                            .background(PixelRect(step: px).fill(theme.color(kind == .output ? .accent : .textSecondary, scheme).opacity(0.16)))
                        }
                    }
                }
                .padding(.top, theme.spacing(.compact))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pageCard(kinds == [.output] ? .accent : .separator)
    }

    /// Rank, specialty, the ladder and the scope note: one click away, closed by default.
    var rules: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            Button { rulesOpen.toggle() } label: {
                HStack(spacing: theme.spacing(.standard)) {
                    PixelIcon(.chevronRight).rotationEffect(.degrees(rulesOpen ? 90 : 0))
                    Text(Copy.ModelsPage.rulesTitle).font(theme.font(.supporting))
                }
                .foregroundStyle(theme.color(.textSecondary, scheme))
                .padding(.vertical, theme.spacing(.compact))
            }
            .buttonStyle(PixelPlainButtonStyle())
            .accessibilityValue(rulesOpen ? Copy.ModelsPage.expanded : Copy.ModelsPage.collapsed)
            if rulesOpen {
                VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                    ForEach([Copy.Stats.rankRule, Copy.Stats.specialtyRule, Copy.Stats.ladderNote,
                             roster.range == .allTime ? Copy.Stats.arenaNote : Copy.Stats.arenaRangeNote], id: \.self) { rule in
                        Text(rule).font(theme.font(.supporting)).foregroundStyle(theme.color(.textPrimary, scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, theme.spacing(.spacious) + theme.spacing(.standard))
            }
        }
    }
}
