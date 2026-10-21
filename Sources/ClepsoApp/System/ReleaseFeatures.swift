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
    /// v0.3 "Claude, everywhere": limits from the Claude desktop app and the VS Code panel through Clepso's Claude Code
    /// mod (docs/specs/mod-bridge.md). Available in v0.3 after live desktop/IDE quota and restoration checks.
    /// Installation remains an explicit opt-in through its consent sheet.
    public var claudeMod: Bool

    public init(playerCard: Bool, goals: Bool, claudeMod: Bool = false) {
        self.playerCard = playerCard
        self.goals = goals
        self.claudeMod = claudeMod
    }

    /// Everything built: debug builds and tests.
    public static let all = ReleaseFeatures(playerCard: true, goals: true, claudeMod: true)
    /// v0.3 ships the Card, Goals and the optional Claude desktop/IDE connection.
    public static let shipping = ReleaseFeatures(playerCard: true, goals: true, claudeMod: true)

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
