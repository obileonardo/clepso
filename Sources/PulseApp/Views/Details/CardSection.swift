import AppKit
import DesignSystem
import enum Domain.Product
import SwiftUI
import UniformTypeIdentifiers

/// Increment 1.10c: the player card, after Aqua Voice's shareable stats card. Rendered once for the screen and once,
/// at 2×, as an image to copy, save or share. Nothing is sent anywhere unless the user shares it.
struct CardSection: View {
    @Bindable var model: AppModel
    @State private var note: String?
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: theme.spacing(.spacious)) {
            if let card = model.playerCard {
                PlayerCardView(card: card, topModelID: model.statsSummary(.allTime)?.favorite?.model)
                    .frame(maxWidth: .infinity)
                HStack(spacing: theme.spacing(.standard)) {
                    Button(Copy.Card.copy) { copy(card) }.buttonStyle(PixelButtonStyle())
                    Button(Copy.Card.save) { save(card) }.buttonStyle(PixelButtonStyle(prominent: true))
                    if let image = image(card) {
                        ShareLink(item: Image(nsImage: image), preview: SharePreview(card.name.isEmpty ? Product.name : card.name, image: Image(nsImage: image))) {
                            Text(Copy.Card.share)
                        }
                        .buttonStyle(PixelButtonStyle())
                    }
                }
                if let note { Text(note).font(theme.font(.supporting)).foregroundStyle(theme.color(.accent, scheme)) }
                Text(Copy.Card.note).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(Copy.Card.needsStats).font(theme.font(.label)).foregroundStyle(theme.color(.textSecondary, scheme))
            }
        }
        .frame(maxWidth: .infinity)
    }

    @MainActor func image(_ card: PlayerCard) -> NSImage? {
        let view = PlayerCardView(card: card, topModelID: model.statsSummary(.allTime)?.favorite?.model)
            .padding(theme.spacing(.spacious))
            .background(theme.color(.background, scheme))
            .environment(\.theme, theme)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.nsImage
    }

    func copy(_ card: PlayerCard) {
        guard let image = image(card) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        note = Copy.Card.copied
    }

    func save(_ card: PlayerCard) {
        guard let image = image(card), let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(Product.name.lowercased())-card.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        note = (try? png.write(to: url)) != nil ? Copy.Card.saved : nil
    }
}

/// The card itself: name, since, plan, stamps, output total, level and progress, four numbers.
struct PlayerCardView: View {
    let card: PlayerCard
    let topModelID: String?
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    static let width: CGFloat = 600

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                        Text((card.name.isEmpty ? Product.name : card.name).uppercased()).font(theme.font(.metricHero))
                            .foregroundStyle(theme.color(.textPrimary, scheme)).lineLimit(1).minimumScaleFactor(0.5)
                        HStack(spacing: theme.spacing(.standard)) {
                            if let since = card.since { tag("\(Copy.Card.since) \(since)", lit: false) }
                            tag((card.plan ?? Copy.Account.planNotSet).uppercased(), lit: card.plan != nil)
                        }
                    }
                    Spacer()
                    ModelSprite(family: ModelSprite.Family(topModelID ?? ""), role: .accent)
                        .frame(width: theme.spacing(.spacious) * 4.5, height: theme.spacing(.spacious) * 4.5)
                        .background(theme.color(.surfaceMuted, scheme))
                }
                if !card.milestones.isEmpty {
                    HStack(spacing: theme.spacing(.standard)) { ForEach(card.milestones) { stamp($0) } }
                }
                VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                    Text(Copy.Card.outputTokens).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                    Text(card.output.formatted(.number)).font(theme.font(.metricHero)).monospacedDigit()
                        .foregroundStyle(theme.color(.textPrimary, scheme)).lineLimit(1).minimumScaleFactor(0.5)
                }
                VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                    Text(Copy.Card.toNext(Formatting.compact(card.level.next - card.level.output), card.level.level + 1))
                        .font(theme.font(.supporting)).foregroundStyle(theme.color(.accent, scheme))
                    ZStack(alignment: .leading) {
                        PixelBar(fraction: card.level.progress, role: .accent, pattern: .solid, segments: 30)
                    }
                    Text(Copy.Card.levelBar(card.level.level, card.levelName)).font(theme.font(.title))
                        .foregroundStyle(theme.color(.textPrimary, scheme))
                }
            }
            .padding(theme.spacing(.spacious) * 1.4)
            Rectangle().fill(theme.color(.separator, scheme)).frame(height: theme.stroke(.hairline))
            HStack(alignment: .top, spacing: 0) {
                cell(Copy.Card.streak, Copy.Card.days(card.streak))
                divider
                cell(Copy.Card.topModel, card.topModel ?? "—")
                divider
                cell(Copy.Card.sessions, card.sessions.formatted(.number))
                divider
                cell(Copy.Card.longest, card.longestSessionMs.map { Formatting.duration(milliseconds: $0) } ?? "—")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: Self.width)
        .background(DotGrid().opacity(0.5))
        .background(theme.color(.surfaceElevated, scheme))
        .overlay(PixelRect(step: theme.stroke(.hairline) * 3).strokeBorder(theme.color(.accent, scheme).opacity(0.7), lineWidth: theme.stroke(.emphasis)))
        .accessibilityElement(children: .combine)
    }

    var divider: some View { Rectangle().fill(theme.color(.separator, scheme)).frame(width: theme.stroke(.hairline)) }

    func cell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
            Text(label.uppercased()).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
            Text(value).font(theme.font(.title)).foregroundStyle(theme.color(.textPrimary, scheme)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(theme.spacing(.spacious))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func tag(_ text: String, lit: Bool) -> some View {
        Text(text).font(theme.font(.micro)).foregroundStyle(theme.color(lit ? .background : .textSecondary, scheme))
            .padding(.horizontal, theme.spacing(.standard)).padding(.vertical, theme.spacing(.compact))
            .background(PixelRect(step: theme.stroke(.hairline) * 2).fill(lit ? theme.color(.accent, scheme) : Color.clear))
            .overlay(PixelRect(step: theme.stroke(.hairline) * 2).strokeBorder(theme.color(lit ? .accent : .separator, scheme), lineWidth: theme.stroke(.hairline)))
    }

    func stamp(_ m: Milestone) -> some View {
        VStack(spacing: theme.spacing(.compact) / 2) {
            Text(m.big).font(theme.font(.metricMedium)).foregroundStyle(theme.color(.accent, scheme))
            Text(m.unit).font(theme.font(.micro)).foregroundStyle(theme.color(.accent, scheme))
        }
        .padding(.horizontal, theme.spacing(.standard) + theme.spacing(.compact)).padding(.vertical, theme.spacing(.standard))
        .overlay(PixelRect(step: theme.stroke(.hairline) * 3).strokeBorder(theme.color(.accent, scheme), style: StrokeStyle(lineWidth: theme.stroke(.hairline), dash: [3, 2])))
        .rotationEffect(.degrees(-3))
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
