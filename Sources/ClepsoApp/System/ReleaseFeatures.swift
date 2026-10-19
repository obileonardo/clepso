/// What a build shows (RELEASE_ROADMAP §4, founder decision 19 Oct 2026). v0.1 held the player Card and Goals back
/// for v0.2 "Your first season", while the data behind them (stats, goal history) kept collecting; v0.2 ships both, so
/// they open with real history. The mechanism stays for later reveals: a section switched off here loses its sidebar
/// entry and every link into it.
///
/// Release builds always use `shipping`. Debug builds show everything, and take `-ClepsoReleaseFeatures shipping` to
/// look like the release (the probe and screenshots).
public struct ReleaseFeatures: Sendable, Equatable {
    public var playerCard: Bool
    public var goals: Bool

    public init(playerCard: Bool, goals: Bool) {
        self.playerCard = playerCard
        self.goals = goals
    }

    /// Everything built: debug builds and tests.
    public static let all = ReleaseFeatures(playerCard: true, goals: true)
    /// What the next release ships. v0.2.0: everything built so far, the Card and Goals included (v0.1.0 hid both).
    public static let shipping = ReleaseFeatures(playerCard: true, goals: true)

    /// This build's features. `debugFlag` reads a debug launch argument (always nil in release builds).
    static func current(debugFlag: (String) -> String?) -> ReleaseFeatures {
        #if DEBUG
        debugFlag("ClepsoReleaseFeatures") == "shipping" ? .shipping : .all
        #else
        .shipping
        #endif
    }

    /// Whether a Dashboard section may be shown or navigated to.
    public func allows(_ section: AppModel.DetailsSection) -> Bool {
        switch section {
        case .card: playerCard
        case .goals: goals
        case .home, .limits, .session, .overview, .models, .account, .settings: true
        }
    }
}
