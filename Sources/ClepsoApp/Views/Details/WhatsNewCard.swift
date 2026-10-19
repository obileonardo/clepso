import DesignSystem
import SwiftUI

/// Home's "What's new" card (RELEASE_ROADMAP §6): the release's name, a line on what it brings, one row per highlight
/// with a button into its page, a link to the site's changelog and Dismiss. Shown at the top of Home once per version
/// (`AppModel.whatsNew`); the text is compiled in, and the link opens in the browser only when clicked.
struct WhatsNewCard: View {
    let entry: WhatsNew
    let model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            HStack(alignment: .center, spacing: theme.spacing(.standard)) {
                PixelIcon(.flag).foregroundStyle(theme.color(.accent, scheme))
                Text(Copy.WhatsNewCard.tag(entry.version)).font(theme.font(.micro)).tracking(1)
                    .foregroundStyle(theme.color(.textSecondary, scheme))
                Spacer(minLength: theme.spacing(.standard))
                Button(Copy.WhatsNewCard.dismiss) { Task { await model.dismissWhatsNew() } }
                    .buttonStyle(PixelButtonStyle())
                    .accessibilityHint(Copy.WhatsNewCard.dismissHint)
            }
            Text(entry.title.uppercased()).font(theme.font(.metricMedium)).foregroundStyle(theme.color(.textPrimary, scheme))
                .accessibilityAddTraits(.isHeader)
            Text(entry.summary).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(entry.highlights) { highlight in
                    IconRow(glyph: highlight.symbol, title: highlight.title, subtitle: highlight.detail) {
                        if let section = highlight.section, model.features.allows(section) {
                            Button(highlight.open) { model.detailsSection = section }.buttonStyle(PixelButtonStyle())
                        }
                    }
                }
            }
            Button { model.openChangelog() } label: { PixelLabel(Copy.WhatsNewCard.changelog, glyph: .external) }
                .buttonStyle(PixelButtonStyle())
                .accessibilityHint(Copy.WhatsNewCard.changelogHint)
        }
        .pageCard(.accent)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Copy.WhatsNewCard.label(entry.version))
        .task { await model.whatsNewShown() }
    }
}
