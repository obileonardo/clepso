/// What a build shows (RELEASE_ROADMAP §4, founder decision 19 Oct 2026). v0.1 holds the player Card and Goals back
/// for v0.2 "Your first season": their sidebar entries and every link into them are hidden, while the data behind them
/// (stats, goal history) keeps collecting so both open with real history when they are switched on.
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
    /// What the next release ships. v0.1.0: no Card, no Goals (revealed in v0.2).
    public static let shipping = ReleaseFeatures(playerCard: false, goals: false)

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
