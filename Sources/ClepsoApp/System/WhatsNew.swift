import Foundation

/// Home's "What's new" card (RELEASE_ROADMAP §6): one entry per release that has something to point at, written into
/// the app at build time. Nothing here is fetched: the text is compiled in, and the changelog link is opened by the
/// user's browser only when they click it.
///
/// When it shows (`AppModel.start`): after the app's version changes, once. A fresh install (onboarding not finished)
/// records the version without showing anything: onboarding is the introduction. A later release adds an entry at the
/// top of `entries`; a patch with no entry of its own shows nothing new.
struct WhatsNew: Sendable, Equatable, Identifiable {
    struct Highlight: Sendable, Equatable, Identifiable {
        /// Its icon, by the symbol name `PixelGlyph(symbol:)` maps to a pixel glyph (as every Home row names its icon).
        let symbol: String
        let title: String
        let detail: String
        /// The Dashboard section its button opens, and the button's title. No button if this build holds it back.
        let section: AppModel.DetailsSection?
        let open: String
        var id: String { title }
    }

    /// The version this entry introduces, numeric semver (`MARKETING_VERSION`, e.g. "0.2.0").
    let version: String
    let title: String
    let summary: String
    let highlights: [Highlight]
    var id: String { version }

    /// The site's changelog: opened only from the card's link, by the user's browser.
    static let changelogURL = URL(string: "https://clepso-app.vercel.app/changelog/")!

    /// Newest first.
    static let entries: [WhatsNew] = [
        WhatsNew(version: "0.2.0", title: Copy.WhatsNewCard.firstSeasonTitle, summary: Copy.WhatsNewCard.firstSeasonSummary, highlights: [
            Highlight(symbol: "person.text.rectangle", title: Copy.WhatsNewCard.cardTitle, detail: Copy.WhatsNewCard.cardDetail,
                      section: .card, open: Copy.HomePage.openCard),
            Highlight(symbol: "target", title: Copy.WhatsNewCard.goalsTitle, detail: Copy.WhatsNewCard.goalsDetail,
                      section: .goals, open: Copy.WhatsNewCard.openGoals),
        ]),
    ]

    /// The entry to show to someone who last saw `lastSeen` and now runs `current`: the newest one released after
    /// `lastSeen` and no later than `current`, or nil. An unreadable `lastSeen` (none yet, or a development build's
    /// "dev") counts as before every entry; an unreadable `current` shows nothing.
    static func entry(lastSeen: String?, current: String, in entries: [WhatsNew] = entries) -> WhatsNew? {
        guard let now = numeric(current) else { return nil }
        let seen = lastSeen.flatMap(numeric)
        return entries
            .compactMap { entry in numeric(entry.version).map { (entry, $0) } }
            .filter { _, version in version.lexicographicallyPrecedes(now) || version == now }
            .filter { _, version in seen.map { $0.lexicographicallyPrecedes(version) } ?? true }
            .max { $0.1.lexicographicallyPrecedes($1.1) }?.0
    }

    /// "0.2.0" → [0, 2, 0]; a suffix after "-" or "+" ("0.2.0-test") is ignored. nil unless every part is a number.
    /// Padded to three parts, so "0.2" and "0.2.0" compare equal.
    static func numeric(_ version: String) -> [Int]? {
        let core = version.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? ""
        let parts = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.count <= 3, parts.allSatisfy({ $0 != nil }) else { return nil }
        return (parts.compactMap { $0 } + [0, 0, 0]).prefix(3).map { $0 }
    }
}
