import DesignSystem
import SwiftUI

/// Increment 1.15: the colour theme, chosen from swatches that preview each theme in the current appearance. The
/// selected one carries a tick and a heavier frame, so the choice never rests on colour alone. Keyboard: each is a button.
struct ThemePicker: View {
    let selection: String
    let choose: (String) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let gap = theme.spacing(.standard)
        // One row; where that doesn't fit (the 1100 pt minimum window), rows of three.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: gap) {
                ForEach(Theme.selectable, id: \.name) { swatch($0) }
            }
            Grid(alignment: .topLeading, horizontalSpacing: gap, verticalSpacing: gap) {
                ForEach(Array(stride(from: 0, to: Theme.selectable.count, by: 3)), id: \.self) { i in
                    GridRow {
                        ForEach(Theme.selectable[i..<min(i + 3, Theme.selectable.count)], id: \.name) { swatch($0) }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Copy.SettingsPage.theme)
    }

    func swatch(_ candidate: Theme) -> some View {
        ThemeSwatch(candidate: candidate, selected: candidate.name == selection) { choose(candidate.name) }
    }
}

struct ThemeSwatch: View {
    let candidate: Theme
    let selected: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let px = theme.stroke(.hairline) * 2
        Button(action: action) {
            VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                preview
                HStack(spacing: theme.spacing(.compact)) {
                    PixelIcon(selected ? .checkSquare : .dashedSquare)
                        .foregroundStyle(theme.color(selected ? .accent : .separator, scheme))
                    Text(Copy.SettingsPage.themeName(candidate.name).uppercased()).font(theme.font(.micro)).lineLimit(1)
                        .foregroundStyle(theme.color(selected ? .textPrimary : .textSecondary, scheme))
                }
            }
            .padding(theme.spacing(.standard))
            .background(PixelRect(step: px).fill(theme.color(selected ? .surfaceMuted : .surfaceElevated, scheme)))
            .overlay(PixelRect(step: px).strokeBorder(theme.color(selected ? .accent : .separator, scheme),
                                                      lineWidth: selected ? theme.stroke(.emphasis) : theme.stroke(.hairline)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PixelPlainButtonStyle())
        .help(Copy.SettingsPage.themeIntent(candidate.name))
        .accessibilityLabel(Copy.SettingsPage.themeName(candidate.name) + ", " + Copy.SettingsPage.themeIntent(candidate.name))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// A miniature panel in the candidate's own colours: a title line, a lit meter, and the three status colours.
    var preview: some View {
        let c = { (token: ColorToken) in candidate.color(token, scheme) }
        let unit = theme.spacing(.compact)
        return VStack(alignment: .leading, spacing: unit) {
            Rectangle().fill(c(.textPrimary)).frame(width: unit * 7, height: unit)
            Rectangle().fill(c(.textSecondary)).frame(width: unit * 11, height: unit / 2)
            HStack(spacing: unit / 2) {
                ForEach(0..<8, id: \.self) { i in Rectangle().fill(i < 5 ? c(.accent) : c(.surfaceMuted)).frame(width: unit * 1.5, height: unit * 2) }
            }
            HStack(spacing: unit / 2) {
                ForEach([ColorToken.statusSuccess, .statusAttention, .statusBlocked], id: \.self) { role in
                    Rectangle().fill(c(role)).frame(width: unit * 2, height: unit * 2)
                }
            }
        }
        .padding(theme.spacing(.standard))
        .frame(width: theme.spacing(.spacious) * 5, alignment: .leading)
        .background(c(.background))
        .overlay(Rectangle().strokeBorder(c(.separator), lineWidth: theme.stroke(.hairline)))
        .accessibilityHidden(true)
    }
}
