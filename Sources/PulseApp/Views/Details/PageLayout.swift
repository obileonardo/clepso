import DesignSystem
import SwiftUI

/// The Dashboard's page structure (1.14), taken from the Account page the founder chose as the model: one centred
/// column; sections separated by a hairline; each section's name (bright green) and one line of explanation (grey) on
/// the left, its content on the right. No boxes inside boxes: hierarchy comes from colour and type, with values in
/// white, explanations in grey and fills in the deep green of the meters.

/// The centred column every page sits in.
struct PageColumn<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: PageMetrics.column, alignment: .leading)
            .frame(maxWidth: .infinity)
    }
}

enum PageMetrics {
    static let column: CGFloat = 1040
    static let labelColumn: CGFloat = 260
    /// The content side's width, for things sized from it (calendars).
    static var content: CGFloat { column - labelColumn - 30 }
}

/// One section: a hairline on top, the name and a line on the left, the content on the right.
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
        .padding(.vertical, theme.spacing(.spacious))
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
