import Foundation
import Testing
@testable import ClepsoApp

/// v0.1 held the player Card and Goals back; v0.2 "Your first season" ships both (RELEASE_ROADMAP §2 and §4, founder
/// decision 19 Oct 2026). These prove the shipping configuration now shows every section, and that the mechanism still
/// works for a later hold-back: a section switched off has no sidebar entry and no way into it.
@Suite("Release features")
@MainActor
struct ReleaseFeaturesTests {
    /// What v0.1.0 shipped: a configuration that holds both back, to keep the mechanism tested.
    static let heldBack = ReleaseFeatures(playerCard: false, goals: false)

    @Test("v0.2 ships the Card and Goals: the shipping configuration hides nothing; debug builds show everything")
    func shipping() {
        #expect(ReleaseFeatures.shipping.playerCard && ReleaseFeatures.shipping.goals)
        #expect(ReleaseFeatures.shipping == ReleaseFeatures(playerCard: true, goals: true, claudeMod: false))
        #expect(ReleaseFeatures.all.claudeMod && !ReleaseFeatures.shipping.claudeMod)
        #expect(AppModel.DetailsSection.allCases.allSatisfy(ReleaseFeatures.shipping.allows))
        #expect(AppModel.DetailsSection.allCases.allSatisfy(ReleaseFeatures.all.allows))
        let hidden = AppModel.DetailsSection.allCases.filter { !Self.heldBack.allows($0) }
        #expect(Set(hidden) == [.card, .goals])
        // This test target is built in debug: everything by default, the release on request.
        #expect(ReleaseFeatures.current(debugFlag: { _ in nil }) == .all)
        #expect(ReleaseFeatures.current(debugFlag: { $0 == "ClepsoReleaseFeatures" ? "shipping" : nil }) == .shipping)
        let live = AppEnvironment.live(bundle: .main, flag: { $0 == "ClepsoReleaseFeatures" ? "shipping" : nil })
        #expect(live.features == .shipping)
    }

    @Test("The sidebar lists the Card and Goals in the release, and neither when they are held back")
    func sidebar() {
        let full = [AppModel.DetailsSection.home, .limits, .session, .overview, .models, .card, .goals, .account, .settings]
        #expect(DetailsSidebar.groups(.shipping).flatMap(\.sections) == full)
        #expect(DetailsSidebar.groups(.all).flatMap(\.sections) == full)
        let held = DetailsSidebar.groups(Self.heldBack).flatMap(\.sections)
        #expect(held == [.home, .limits, .session, .overview, .models, .account, .settings])
    }

    @Test("Every section is reachable in the release; a held-back one lands on Home from every link")
    func navigation() {
        let box = Sandbox(); defer { box.cleanUp() }
        var environment = box.model(clock: TestClock()).environment
        environment.features = .shipping
        let release = AppModel(environment: environment)
        for section in AppModel.DetailsSection.allCases {
            release.detailsSection = .limits
            release.detailsSection = section
            #expect(release.detailsSection == section, "\(section)")
        }
        environment.features = Self.heldBack
        let held = AppModel(environment: environment)
        for section in AppModel.DetailsSection.allCases {
            held.detailsSection = .limits
            held.detailsSection = section
            #expect(held.detailsSection == (Self.heldBack.allows(section) ? section : .home), "\(section)")
        }
    }

    @Test("For you suggests a goal in the release, and never a held-back section")
    func forYou() {
        var input = ForYou.Input()
        input.goals = [GoalStatus(kind: .fiveHourPeak, value: "97%", amount: 97, target: "≤ 80%", fraction: 1, state: .missed, detail: "d", streak: 0)]
        input.features = .shipping
        #expect(ForYou.make(input).map(\.kind) == [.goal])
        input.features = Self.heldBack
        let items = ForYou.make(input)
        #expect(items.map(\.kind) == [.allClear])
        #expect(items.allSatisfy { $0.section.map(Self.heldBack.allows) ?? true })
    }
}
