import AppKit
import DesignSystem
import enum Domain.Product
import SwiftUI
import UniformTypeIdentifiers

/// Increment 1.10c: the player card, after Aqua Voice's shareable stats card. Redesigned after the founder's review:
/// the Clepso mark, one hero figure with the rest in a grid, unambiguous streaks, an "updated" stamp, and a back side
/// (the mark, a line, an activity log, the website) the card flips to. Rendered live for the screen, and once, at 2×,
/// as an image of the side showing to copy, save or share. Nothing is sent anywhere unless the user shares it.
struct CardSection: View {
    @Bindable var model: AppModel
    @State private var note: String?
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.locale) private var locale
    @Environment(\.displayTimeZone) private var zone

    /// 1.14: Account's structure. The card with its actions, then the milestone ladders as aligned rows.
    var body: some View {
        PageColumn {
            // Read from the model here, so the page follows it: a new reading or a rewritten statistics file redraws it.
            if let card = model.playerCard {
                PageSection(Copy.CardPage.yourCard, Copy.Card.note) {
                    VStack(alignment: .leading, spacing: theme.spacing(.spacious) * 1.5) {
                        FlipCard(card: card, showsBack: $model.cardShowsBack, previewTilt: model.cardTiltPreview)
                        HStack(spacing: theme.spacing(.standard)) {
                            // 1.15: the primary action leads, as in every action row.
                            Button(Copy.Card.save) { save(card) }.buttonStyle(PixelButtonStyle(prominent: true))
                            Button(Copy.Card.copy) { copy(card) }.buttonStyle(PixelButtonStyle())
                            let image = image(card)
                            ShareLink(item: Image(nsImage: image), preview: SharePreview(card.name.isEmpty ? Product.name : card.name, image: Image(nsImage: image))) {
                                Text(Copy.Card.share)
                            }
                            .buttonStyle(PixelButtonStyle())
                            Button(model.cardShowsBack ? Copy.Card.showFront : Copy.Card.showBack) { model.cardShowsBack.toggle() }
                                .buttonStyle(PixelButtonStyle())
                            if let note { Text(note).font(theme.font(.supporting)).foregroundStyle(theme.color(.accent, scheme)) }
                        }
                    }
                }
                if let summary = model.statsSummary(.allTime) {
                    PageSection(Copy.CardPage.milestones.capitalized, Copy.CardPage.milestonesSub) {
                        milestones(Ladder.all(output: card.output, longestStreak: summary.longestStreak, sessions: summary.sessions,
                                              activeDays: summary.activeDays))
                    }
                }
            } else {
                PageSection(Copy.Card.title, nil) {
                    Text(Copy.Card.needsStats).font(theme.font(.label)).foregroundStyle(theme.color(.textSecondary, scheme))
                }
            }
        }
        .onChange(of: model.cardShowsBack) { note = nil }
    }

    /// Tripadvisor's ladders as rows: the category and its tier on the left, the rungs, then what reaches the next.
    func milestones(_ ladders: [Ladder]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ladders) { ladder in
                HStack(alignment: .center, spacing: theme.spacing(.spacious)) {
                    IconRow(glyph: Self.symbol(ladder.kind), title: Copy.CardPage.tier(ladder.kind, ladder.reached), subtitle: Copy.CardPage.name(ladder.kind))
                        .frame(width: PageMetrics.labelColumn - theme.spacing(.spacious), alignment: .leading)
                    VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                        HStack(spacing: theme.stroke(.hairline) * 2) {
                            ForEach(Array(ladder.steps.enumerated()), id: \.offset) { i, step in
                                VStack(spacing: theme.spacing(.compact)) {
                                    Rectangle().fill(theme.color(i < ladder.reached ? .accent : .surfaceMuted, scheme)).frame(height: theme.spacing(.standard))
                                    Text(Formatting.compact(step)).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        Text(ladder.remaining.map { Copy.CardPage.toGo(ladder.kind, Formatting.compact($0)) } ?? Copy.CardPage.top)
                            .font(theme.font(.supporting)).foregroundStyle(theme.color(.accent, scheme))
                    }
                }
                .padding(.vertical, theme.spacing(.standard))
                .accessibilityElement(children: .combine)
            }
        }
    }

    static func symbol(_ kind: Ladder.Kind) -> String {
        switch kind {
        case .output: "text.cursor"
        case .streak: "flame"
        case .sessions: "terminal"
        case .activeDays: "calendar"
        }
    }

    /// The side showing, flat (no tilt), at 2×. What you see is what you share: the front carries the figures, the back
    /// the activity log and the website; the front is stamped with when its figures were last updated.
    @MainActor func image(_ card: PlayerCard) -> NSImage {
        let view = PlayerCardFace(card: card, back: model.cardShowsBack)
            .padding(theme.spacing(.spacious))
            .background(theme.color(.background, scheme))
            .environment(\.theme, theme)
            .environment(\.colorScheme, scheme)
            .environment(\.locale, locale)
            .environment(\.displayTimeZone, zone)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.nsImage ?? NSImage()
    }

    func copy(_ card: PlayerCard) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image(card)])
        note = Copy.Card.copied(model.cardShowsBack)
    }

    func save(_ card: PlayerCard) {
        guard let tiff = image(card).tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(Product.name.lowercased())-card-\(model.cardShowsBack ? "back" : "front").png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        note = (try? png.write(to: url)) != nil ? Copy.Card.saved : nil
    }
}

// MARK: - The interactive card

/// The card on screen: tilts toward the pointer (a perspective rotation, with a sheen and a shadow that follow it) and
/// flips to its back on a click, Space or Return. With Reduce Motion there is no tilt and the flip is a crossfade.
/// One accessibility element: a button named "Flip card" whose value reads the face showing.
struct FlipCard: View {
    let card: PlayerCard
    @Binding var showsBack: Bool
    /// Debug probe only: a fixed pointer position (−1…1 on each axis) so a screenshot can show the tilt.
    var previewTilt: CGSize? = nil
    @State private var angle: Double = 0                 // 0 front … 180 back
    @State private var tilt: CGSize = .zero              // pointer offset from the centre, −1…1
    @State private var pointer: UnitPoint = .center
    @State private var hovering = false
    @State private var size = CGSize(width: PlayerCardFront.width, height: 1)
    @FocusState private var focused: Bool
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let maxTilt: Double = 8                       // degrees, with the pointer at the card's edge

    var body: some View {
        // A preview tilt (probe only) replaces the pointer entirely, so a capture never depends on where the mouse is.
        let lean = reduceMotion ? .zero : (previewTilt ?? tilt)
        let lifted = !reduceMotion && (previewTilt.map { $0 != .zero } ?? hovering)
        PlayerCardFront(card: card)
            .modifier(FlipFace(angle: angle, back: false, flat: reduceMotion))
            .overlay { PlayerCardBack(card: card).modifier(FlipFace(angle: angle, back: true, flat: reduceMotion)) }
            .overlay { sheen(lean, lifted: lifted) }
            .overlay { focusRing }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .rotation3DEffect(.degrees(-Double(lean.height) * Self.maxTilt), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
            .rotation3DEffect(.degrees(Double(lean.width) * Self.maxTilt), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
            .scaleEffect(lifted ? 1.01 : 1)
            .shadow(color: shadow.opacity(lifted ? 0.3 : 0.15), radius: theme.spacing(.spacious) * (lifted ? 1.5 : 0.8),
                    x: -lean.width * theme.spacing(.standard) * 1.5, y: theme.spacing(.standard) * (lifted ? 2 : 1) - lean.height * theme.spacing(.compact))
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75), value: tilt)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75), value: hovering)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    if !hovering { NSCursor.pointingHand.push() }
                    hovering = true
                    pointer = UnitPoint(x: location.x / max(1, size.width), y: location.y / max(1, size.height))
                    tilt = CGSize(width: min(1, max(-1, pointer.x * 2 - 1)), height: min(1, max(-1, pointer.y * 2 - 1)))
                case .ended:
                    if hovering { NSCursor.pop() }
                    hovering = false
                    tilt = .zero
                }
            }
            .onTapGesture { showsBack.toggle() }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.space, .return]) { _ in
                showsBack.toggle()
                return .handled
            }
            .onAppear { angle = showsBack ? 180 : 0 }
            .onChange(of: showsBack) { _, back in
                // A spring flip; under Reduce Motion the same change is a short crossfade (`FlipFace(flat:)`).
                withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.6, dampingFraction: 0.82)) {
                    angle = back ? 180 : 0
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Copy.Card.flip)
            .accessibilityValue(showsBack ? PlayerCardBack.summary(card) : PlayerCardFront.summary(card))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { showsBack.toggle() }
    }

    /// Shadows are dark in both appearances: the light palette's ink.
    var shadow: Color { theme.color(.textPrimary, .light) }

    /// A soft accent glow under the pointer, like light catching the card.
    @ViewBuilder func sheen(_ lean: CGSize, lifted: Bool) -> some View {
        let center = previewTilt.map { UnitPoint(x: (1 + $0.width) / 2, y: (1 + $0.height) / 2) } ?? pointer
        RadialGradient(colors: [theme.color(.accent, scheme).opacity(scheme == .dark ? 0.16 : 0.10), theme.color(.accent, scheme).opacity(0)],
                       center: center, startRadius: 0, endRadius: PlayerCardFront.width * 0.6)
            .blendMode(scheme == .dark ? .plusLighter : .multiply)
            .opacity(lifted ? 1 : 0)
            .allowsHitTesting(false)
    }

    @ViewBuilder var focusRing: some View {
        if focused {
            PixelRect(step: theme.stroke(.hairline) * 3).inset(by: -theme.stroke(.focus) * 2)
                .strokeBorder(theme.color(.accent, scheme), lineWidth: theme.stroke(.focus))
                .allowsHitTesting(false)
        }
    }
}

/// One face of the flip. `angle` animates 0 → 180; each face shows only while it faces the viewer. `flat` (Reduce
/// Motion): no rotation, the faces crossfade instead.
struct FlipFace: ViewModifier, Animatable {
    var angle: Double
    let back: Bool
    let flat: Bool

    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let progress = min(1, max(0, angle / 180))
        let showing = back ? angle > 90 : angle <= 90
        if flat {
            content.opacity(back ? progress : 1 - progress).allowsHitTesting(back ? progress > 0.5 : progress <= 0.5)
        } else {
            content
                .rotation3DEffect(.degrees(back ? angle - 180 : angle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                .opacity(showing ? 1 : 0)
                .allowsHitTesting(showing)
        }
    }
}

/// A flat face for export: the back is laid out at the front's size, so both images match.
struct PlayerCardFace: View {
    let card: PlayerCard
    let back: Bool

    var body: some View {
        if back {
            PlayerCardFront(card: card).hidden().overlay { PlayerCardBack(card: card) }
        } else {
            PlayerCardFront(card: card)
        }
    }
}

// MARK: - Front

/// The front: who (name, since, plan, the Clepso mark), one hero figure (total tokens), the level, eight figures in a
/// grid, and when it was last updated.
struct PlayerCardFront: View {
    let card: PlayerCard
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.locale) private var locale
    @Environment(\.displayTimeZone) private var zone

    static let width: CGFloat = 600
    /// 16 pixels at 4 points: every pixel of the mark on whole points.
    static let markSize: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: theme.spacing(.spacious) * 1.2) {
                header
                VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                    Text(Copy.Card.totalTokens).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                    Text(Formatting.compact(card.totalTokens)).font(theme.font(.metricDisplay)).monospacedDigit()
                        .foregroundStyle(theme.color(.textPrimary, scheme)).lineLimit(1).minimumScaleFactor(0.5)
                    Text(Copy.Card.totalCaption).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                }
                level
            }
            .padding(theme.spacing(.spacious) * 1.4)
            rule
            grid
            rule
            footer
        }
        .frame(width: Self.width)
        .background(DotGrid().opacity(0.5))
        .background(theme.color(.surfaceElevated, scheme))
        .overlay(CardFrame())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.summary(card, zone: zone))
    }

    var header: some View {
        HStack(alignment: .top, spacing: theme.spacing(.spacious)) {
            VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                Text((card.name.isEmpty ? Product.name : card.name).uppercased()).font(theme.font(.metricHero))
                    .foregroundStyle(theme.color(.textPrimary, scheme)).lineLimit(1).minimumScaleFactor(0.5)
                HStack(spacing: theme.spacing(.standard)) {
                    if let since = card.since.flatMap(Self.day) { CardTag(text: "\(Copy.Card.since) \(since)", lit: false) }
                    CardTag(text: (card.plan ?? Copy.Account.planNotSet).uppercased(), lit: card.plan != nil)
                }
            }
            Spacer(minLength: 0)
            ClepsoMark().frame(width: Self.markSize, height: Self.markSize)
        }
    }

    var level: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            HStack(alignment: .firstTextBaseline) {
                Text(Copy.Card.levelBar(card.level.level, card.levelName)).font(theme.font(.title))
                    .foregroundStyle(theme.color(.textPrimary, scheme))
                Spacer(minLength: theme.spacing(.standard))
                Text(Copy.Card.toNext(Formatting.compact(card.level.next - card.level.output), card.level.level + 1))
                    .font(theme.font(.supporting)).foregroundStyle(theme.color(.accent, scheme))
            }
            PixelBar(fraction: card.level.progress, role: .accent, pattern: .solid, segments: 30)
        }
    }

    /// Eight figures, two rows of four; each a label, a value and a line saying exactly what it counts.
    var grid: some View {
        let rows = Self.figures(card, zone: zone).chunked(4)
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                if i > 0 { rule }
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { j, figure in
                        if j > 0 { Rectangle().fill(theme.color(.separator, scheme)).frame(width: theme.stroke(.hairline)) }
                        cell(figure)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func cell(_ f: Figure) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
            Text(f.label.uppercased()).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(f.value).font(theme.font(.metricMedium)).monospacedDigit().foregroundStyle(theme.color(f.lit ? .accent : .textPrimary, scheme))
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(f.caption).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, theme.spacing(.spacious) * 0.8).padding(.vertical, theme.spacing(.spacious) * 0.7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var footer: some View {
        HStack {
            if let updated = card.updatedAt {
                Text(Copy.Card.updated(Self.stamp(updated, zone: zone, locale: locale))).font(theme.font(.micro))
                    .foregroundStyle(theme.color(.textSecondary, scheme))
            }
            Spacer(minLength: theme.spacing(.standard))
            if let through = card.statsThrough.flatMap(Self.shortDay) {
                Text(Copy.Card.through(through)).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
            }
        }
        .padding(.horizontal, theme.spacing(.spacious) * 1.4).padding(.vertical, theme.spacing(.spacious) * 0.6)
    }

    var rule: some View { Rectangle().fill(theme.color(.separator, scheme)).frame(height: theme.stroke(.hairline)) }

    struct Figure: Equatable {
        let label: String
        let value: String
        let caption: String
        var lit = false
    }

    static func figures(_ c: PlayerCard, zone: TimeZone) -> [Figure] {
        let lines: Figure = if let l = c.lines {
            Figure(label: Copy.Card.lines, value: "+" + Formatting.compact(l.added),
                   caption: Copy.Card.linesCaption(removed: Formatting.compact(l.removed), since: l.fullWindow ? nil : shortDay(l.since, zone: zone)))
        } else {
            Figure(label: Copy.Card.lines, value: "—", caption: Copy.Card.linesCaption(removed: "0", since: nil))
        }
        let today = c.activity.columns.last?.compactMap { $0 }.last
        let includesToday = c.currentStreak > 0 && (today.map { $0.level > 0 || $0.pending } ?? false)
        return [
            // Exact: the level is earned by this number, and it still fits the cell up to the billions.
            Figure(label: Copy.Card.output, value: c.output.formatted(.number), caption: Copy.Card.outputCaption),
            lines,
            Figure(label: Copy.Card.currentStreak, value: Copy.Card.days(c.currentStreak),
                   caption: Copy.Card.currentCaption(includesToday: includesToday), lit: c.currentStreak > 0),
            Figure(label: Copy.Card.bestStreak, value: Copy.Card.days(c.bestStreak), caption: Copy.Card.bestCaption),
            Figure(label: Copy.Card.sessions, value: c.sessions.formatted(.number), caption: Copy.Card.sessionsCaption),
            Figure(label: Copy.Card.longest, value: c.longestSessionMs.map { Formatting.duration(milliseconds: $0) } ?? "—",
                   caption: Copy.Card.longestCaption),
            Figure(label: Copy.Card.activeDays, value: c.activeDays.formatted(.number), caption: Copy.Card.activeCaption(c.dayCount)),
            Figure(label: Copy.Card.topModel, value: c.topModel ?? "—", caption: c.topModelShare.map { Copy.Card.topCaption($0) } ?? ""),
        ]
    }

    static func summary(_ c: PlayerCard, zone: TimeZone = .current) -> String {
        Copy.Card.frontSummary(c, figures: [(Copy.Card.totalTokens.capitalized, Formatting.compact(c.totalTokens))]
                               + figures(c, zone: zone).map { ($0.label, "\($0.value), \($0.caption)") })
    }

    /// "2026-07-21" → "21 JUL 2026" (Claude Code's day labels carry no time zone).
    static func day(_ label: String) -> String? {
        StatsSummary.Day.date(label).map {
            $0.formatted(Date.FormatStyle(timeZone: StatsSummary.Day.calendar.timeZone).day().month(.abbreviated).year()).uppercased()
        }
    }

    static func shortDay(_ label: String) -> String? {
        StatsSummary.Day.date(label).map {
            $0.formatted(Date.FormatStyle(timeZone: StatsSummary.Day.calendar.timeZone).day().month(.abbreviated)).uppercased()
        }
    }

    static func shortDay(_ date: Date, zone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(timeZone: zone).day().month(.abbreviated))
    }

    /// "18 OCT 2026 AT 04:43": date and time, so a saved image says when it was true.
    static func stamp(_ date: Date, zone: TimeZone, locale: Locale) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: zone)).uppercased()
    }
}

// MARK: - Back

/// The back, after Aqua Voice's: the mark large in a pixel halo, a tag and a line, the activity log, the website.
struct PlayerCardBack: View {
    let card: PlayerCard
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    /// The mark at 8 points a pixel, in a halo 24 pixels across.
    static let mark: CGFloat = 128, halo: CGFloat = 192

    var body: some View {
        VStack(spacing: theme.spacing(.spacious)) {
            Spacer(minLength: 0)
            ZStack {
                PixelHalo().frame(width: Self.halo, height: Self.halo)
                ClepsoMark().frame(width: Self.mark, height: Self.mark)
            }
            VStack(spacing: theme.spacing(.standard)) {
                CardTag(text: "\(Product.name.uppercased()) · \(Copy.Card.backTag)", lit: false)
                Text(Copy.Card.backLine).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
            ActivityLog(activity: card.activity)
            Spacer(minLength: 0)
            Text(Copy.Card.website).font(theme.font(.title)).foregroundStyle(theme.color(.textPrimary, scheme))
        }
        .padding(theme.spacing(.spacious) * 1.4)
        .frame(width: PlayerCardFront.width)
        .frame(maxHeight: .infinity)
        .background(DotGrid().opacity(0.5))
        .background(theme.color(.surfaceElevated, scheme))
        .overlay(CardFrame())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.summary(card))
    }

    static func summary(_ c: PlayerCard) -> String { Copy.Card.backSummary(c, weeks: c.activity.columns.count) }
}

/// The activity log: one square a day for the last weeks (Sunday on top, today last), the Stats calendar's levels;
/// a day Clepso saw that Claude Code's file doesn't cover yet is drawn as an outline. Hover a day for its date.
struct ActivityLog: View {
    let activity: CardActivity
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    /// 15-point days with 3-point gaps: thirty weeks fit the card's 544-point content width.
    static let cell: CGFloat = 15

    var body: some View {
        let cell = Self.cell, gap = theme.stroke(.hairline) * 3
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            HStack(alignment: .firstTextBaseline) {
                Text(Copy.Card.activityTitle(activity.columns.count)).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                Spacer(minLength: theme.spacing(.standard))
                Text(Copy.Card.activitySummary(activity.activeDays, activity.days)).font(theme.font(.micro))
                    .foregroundStyle(theme.color(.accent, scheme))
            }
            HStack(alignment: .top, spacing: gap) {
                ForEach(Array(activity.columns.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { d in square(d < week.count ? week[d] : nil) }
                    }
                }
            }
            HStack(spacing: theme.spacing(.compact)) {
                Text(Copy.Card.less).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                ForEach(0..<5, id: \.self) { level in Rectangle().fill(color(level)).frame(width: cell * 0.75, height: cell * 0.75) }
                Text(Copy.Card.more).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                Spacer(minLength: theme.spacing(.standard))
                if activity.columns.joined().contains(where: { $0?.pending == true }) {
                    Rectangle().strokeBorder(theme.color(.accent, scheme), lineWidth: theme.stroke(.emphasis)).frame(width: cell * 0.75, height: cell * 0.75)
                    Text(Copy.Card.pending).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                }
            }
        }
    }

    @ViewBuilder func square(_ day: CardActivity.Day?) -> some View {
        if let day {
            Rectangle().fill(color(day.level))
                .overlay { if day.pending { Rectangle().strokeBorder(theme.color(.accent, scheme), lineWidth: theme.stroke(.emphasis)) } }
                .frame(width: Self.cell, height: Self.cell)
                .help(Copy.Card.dayHelp(PlayerCardFront.day(day.date) ?? day.date, active: day.level > 0, pending: day.pending))
        } else {
            Color.clear.frame(width: Self.cell, height: Self.cell)
        }
    }

    func color(_ level: Int) -> Color {
        level == 0 ? theme.color(.surfaceMuted, scheme) : theme.color(.accent, scheme).opacity([0, 0.3, 0.55, 0.8, 1][min(level, 4)])
    }
}

// MARK: - Shared pieces

/// The card's frame: a pixel-cut border in the accent.
struct CardFrame: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        PixelRect(step: theme.stroke(.hairline) * 3).strokeBorder(theme.color(.accent, scheme).opacity(0.7), lineWidth: theme.stroke(.emphasis))
            .allowsHitTesting(false)
    }
}

/// A small pixel tag: "SINCE 21 JUL 2026", the plan (lit when set).
struct CardTag: View {
    let text: String
    let lit: Bool
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(text).font(theme.font(.micro)).foregroundStyle(theme.color(lit ? .background : .textSecondary, scheme))
            .padding(.horizontal, theme.spacing(.standard)).padding(.vertical, theme.spacing(.compact))
            .background(PixelRect(step: theme.stroke(.hairline) * 2).fill(theme.color(lit ? .accent : .surfaceElevated, scheme)))
            .overlay(PixelRect(step: theme.stroke(.hairline) * 2).strokeBorder(theme.color(lit ? .accent : .separator, scheme), lineWidth: theme.stroke(.hairline)))
    }
}

/// A pixelated disc of soft accent behind the mark on the back (the pixel take on Aqua's glow): a core and a fainter
/// outer ring of cells.
struct PixelHalo: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Canvas { context, size in
            let n = 24, unit = min(size.width, size.height) / CGFloat(n), r = Double(n) / 2
            var inner = Path(), outer = Path()
            for y in 0..<n {
                for x in 0..<n {
                    let dx = Double(x) + 0.5 - r, dy = Double(y) + 0.5 - r
                    let d = (dx * dx + dy * dy).squareRoot()
                    let rect = CGRect(x: CGFloat(x) * unit, y: CGFloat(y) * unit, width: unit, height: unit)
                    if d <= r * 0.78 { inner.addRect(rect) } else if d <= r { outer.addRect(rect) }
                }
            }
            context.fill(outer, with: .color(theme.color(.accent, scheme).opacity(0.06)))
            context.fill(inner, with: .color(theme.color(.accent, scheme).opacity(0.12)))
        }
        .accessibilityHidden(true)
    }
}

/// A faint grid of dots behind the card, like graph paper.
struct DotGrid: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Canvas { context, size in
            let step = theme.spacing(.spacious)
            var y = step / 2
            while y < size.height {
                var x = step / 2
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(theme.color(.separator, scheme)))
                    x += step
                }
                y += step
            }
        }
        .accessibilityHidden(true)
    }
}

extension Array {
    /// Consecutive slices of `size` (the last may be shorter).
    func chunked(_ size: Int) -> [ArraySlice<Element>] {
        stride(from: 0, to: count, by: Swift.max(1, size)).map { self[$0..<Swift.min($0 + size, count)] }
    }
}
