import DesignSystem
import SwiftUI

/// The Dashboard's page structure (1.14), taken from the Account page the founder chose as the model: one centred
/// column; sections separated by a hairline; each section's name (bright green) and one line of explanation (grey) on
/// the left, its content on the right. No boxes inside boxes: hierarchy comes from colour and type, with values in
/// white, explanations in grey and fills in the deep green of the meters.

/// The centred column every page sits in. 1.17 (founder review of a maximised window): the column grows with the
/// window, from 1040 pt to 1360 pt, so a big window is used rather than framed by empty margins. Pages that size
/// things from the column (calendars) take the closure form, which hands them the content side's width.
struct PageColumn<Content: View>: View {
    let content: (CGFloat) -> Content
    /// The pane's width from `DetailsView`, measured where content can't push it wider. A column that measured itself
    /// read its content's width once content overflowed, so calendars sized from it kept overflowing (Overview at the
    /// 1100 pt minimum window, main at 5ac329b). Its own measurement is only a fallback outside the Dashboard.
    @Environment(\.pageWidth) private var pageWidth
    @State private var measured: CGFloat = 0
    var available: CGFloat { pageWidth > 0 ? pageWidth : measured }

    init(@ViewBuilder content: @escaping () -> Content) { self.content = { _ in content() } }
    init(@ViewBuilder fitting content: @escaping (_ contentWidth: CGFloat) -> Content) { self.content = content }

    var body: some View {
        let column = PageMetrics.column(fitting: available)
        // Pages size things (calendars) from the width the column really gets: below 1040 + gutters its frame shrinks
        // to the window.
        VStack(alignment: .leading, spacing: 0) { content(PageMetrics.content(min(column, available))) }
            .frame(maxWidth: column, alignment: .leading)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measured = $0 }
    }
}

extension EnvironmentValues {
    /// The Dashboard page's width, as proposed by the window (see `PageColumn`).
    @Entry var pageWidth: CGFloat = 0
}

enum PageMetrics {
    /// The narrowest column, and the one every page had before 1.17.
    static let column: CGFloat = 1040
    /// Wider than this, lines and charts stop gaining legibility.
    static let maxColumn: CGFloat = 1360
    /// Space kept either side of the column, so it never touches the window's edges.
    static let gutter: CGFloat = 48
    static let labelColumn: CGFloat = 260
    /// The content side's width, for things sized from it (calendars).
    static var content: CGFloat { content(column) }
    static func content(_ column: CGFloat) -> CGFloat { max(0, column - labelColumn - 30) }
    /// The column for a page `available` points wide. Below 1040 + gutters the column stays 1040 and its frame
    /// shrinks to fit, as it always did.
    static func column(fitting available: CGFloat) -> CGFloat { min(max(available - 2 * gutter, column), maxColumn) }
}

/// One section: a hairline on top, the name and a line on the left, the content on the right. 32 pt of air
/// (`.section`) above and below, inside the hairlines (founder review, 18 Oct 2026: sections were cramped at 20 pt).
struct PageSection<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: () -> Content
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    init(_ title: String, _ subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing(.spacious) * 1.5) {
            VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                Text(title.uppercased()).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme)).accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: PageMetrics.labelColumn, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, theme.spacing(.section))
        .overlay(alignment: .top) { Rectangle().fill(theme.color(.separator, scheme)).frame(height: theme.stroke(.hairline)) }
    }
}

/// A grey label and a white value on one line, with a faint rule above.
struct FactRow: View {
    let label: String
    let value: String
    var emphasis = false
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
            Spacer(minLength: theme.spacing(.standard))
            Text(value).font(emphasis ? theme.font(.title) : theme.font(.label)).monospacedDigit()
                .foregroundStyle(theme.color(.textPrimary, scheme)).lineLimit(1).truncationMode(.middle)
        }
        .padding(.vertical, theme.spacing(.standard))
        .overlay(alignment: .top) { Rectangle().fill(theme.color(.separator, scheme).opacity(0.5)).frame(height: theme.stroke(.hairline)) }
        .accessibilityElement(children: .combine)
    }
}

/// An icon in a deep-green tile, a title and a line, and an optional control on the right (Account's sign-in rows).
struct IconRow<Control: View>: View {
    let glyph: String
    let title: String
    let subtitle: String?
    var role: ColorToken = .accent
    @ViewBuilder let control: () -> Control
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: theme.spacing(.standard) + theme.spacing(.compact)) {
            PixelIcon(symbol: glyph).foregroundStyle(theme.color(role, scheme))
                .frame(width: theme.spacing(.spacious) * 1.6, height: theme.spacing(.spacious) * 1.6)
                .background(PixelRect(step: theme.stroke(.hairline) * 2).fill(theme.color(.surfaceMuted, scheme)))
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme)).fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: theme.spacing(.standard))
            control()
        }
        .padding(.vertical, theme.spacing(.standard))
        .accessibilityElement(children: .contain)
    }
}

extension IconRow where Control == EmptyView {
    init(glyph: String, title: String, subtitle: String?, role: ColorToken = .accent) {
        self.init(glyph: glyph, title: title, subtitle: subtitle, role: role) { EmptyView() }
    }
}

/// A big white figure over a small grey caption, for the few headline numbers a section shows.
struct Figure: View {
    let value: String
    let caption: String
    var role: ColorToken = .textPrimary
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
            Text(value).font(theme.font(.metricMedium)).monospacedDigit().foregroundStyle(theme.color(role, scheme)).lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The Dashboard's card: the popover limit cards' language (elevated fill, hairline stepped pixel frame) with the
/// page's roomier inner padding. For headline figures and live objects only; lists and facts stay on hairlines.
struct PageCard: ViewModifier {
    var role: ColorToken = .separator
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let px = theme.stroke(.hairline) * 2
        content
            .padding(theme.spacing(.spacious))
            .background(PixelRect(step: px).fill(theme.color(.surfaceElevated, scheme)))
            .overlay(PixelRect(step: px).strokeBorder(theme.color(role, scheme), lineWidth: theme.stroke(.hairline)))
    }
}

extension View {
    func pageCard(_ role: ColorToken = .separator) -> some View { modifier(PageCard(role: role)) }
}

/// A headline figure as a card: its small-caps name on top (as the popover's 5-HOUR and 7-DAY cards), the value in
/// the display face, and an optional line of context under it. Cards in a row share one height (`StatCardRow`).
struct StatCard: View {
    let caption: String
    let value: String
    var detail: String? = nil
    var role: ColorToken = .textPrimary
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            Text(caption.uppercased()).font(theme.font(.micro)).tracking(1).foregroundStyle(theme.color(.textSecondary, scheme))
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(theme.font(.metricHero)).monospacedDigit().foregroundStyle(theme.color(role, scheme))
                .lineLimit(1).minimumScaleFactor(0.5)
                .padding(.vertical, -theme.spacing(.compact))           // the pixel face's tall line box, trimmed as in the popover
            if let detail {
                Text(detail).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pageCard()
        .accessibilityElement(children: .combine)
    }
}

/// Cards side by side on an even grid, each as tall as the tallest. When they don't all fit across at their natural
/// size (a narrow window, a long value), they reflow two to a row instead of shrinking or truncating.
struct StatCardRow: View {
    let cards: [StatCard]
    @Environment(\.theme) private var theme

    init(@StatCardBuilder _ cards: () -> [StatCard]) { self.cards = cards() }

    var body: some View {
        let gap = theme.spacing(.standard) + theme.spacing(.compact)
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: gap) { ForEach(cards.indices, id: \.self) { cards[$0] } }
            Grid(horizontalSpacing: gap, verticalSpacing: gap) {
                ForEach(Array(stride(from: 0, to: cards.count, by: 2)), id: \.self) { i in
                    GridRow {
                        cards[i]
                        if i + 1 < cards.count { cards[i + 1] } else { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

@resultBuilder
enum StatCardBuilder {
    static func buildBlock(_ cards: StatCard...) -> [StatCard] { cards }
}

/// 1.15: a few figures in a row, each over its small-caps caption, columns set off by hairlines. Replaces a sentence
/// of numbers ("0 received · 0 malformed · …"); VoiceOver reads the sentence it replaces.
struct FigureStrip: View {
    let items: [(value: String, label: String)]
    let summary: String
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                PixelStat(item.value, item.label)
                    .padding(.leading, index == 0 ? 0 : theme.spacing(.standard) + theme.spacing(.compact))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .overlay(alignment: .leading) {
                        if index > 0 { Rectangle().fill(theme.color(.separator, scheme)).frame(width: theme.stroke(.hairline)) }
                    }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }
}
