import Foundation
import Testing
@testable import ClepsoApp

/// v0.1 holds the player Card and Goals back for v0.2 (RELEASE_ROADMAP §4, founder decision 19 Oct 2026). These prove
/// the shipping configuration hides both, and that no way into the Dashboard reaches them.
@Suite("Release features")
@MainActor
struct ReleaseFeaturesTests {
    @Test("The shipping configuration hides the Card and Goals and nothing else; debug builds show everything")
    func shipping() {
        #expect(!ReleaseFeatures.shipping.playerCard && !ReleaseFeatures.shipping.goals)
        let hidden = AppModel.DetailsSection.allCases.filter { !ReleaseFeatures.shipping.allows($0) }
        #expect(Set(hidden) == [.card, .goals])
        #expect(AppModel.DetailsSection.allCases.allSatisfy(ReleaseFeatures.all.allows))
        // This test target is built in debug: everything by default, the release on request.
        #expect(ReleaseFeatures.current(debugFlag: { _ in nil }) == .all)
        #expect(ReleaseFeatures.current(debugFlag: { $0 == "ClepsoReleaseFeatures" ? "shipping" : nil }) == .shipping)
        let live = AppEnvironment.live(bundle: .main, flag: { $0 == "ClepsoReleaseFeatures" ? "shipping" : nil })
        #expect(live.features == .shipping)
    }

    @Test("The sidebar lists neither section when they are held back, and both when they ship")
    func sidebar() {
        let shipping = DetailsSidebar.groups(.shipping).flatMap(\.sections)
        #expect(!shipping.contains(.card) && !shipping.contains(.goals))
        #expect(shipping == [.home, .limits, .session, .overview, .models, .account, .settings])
        #expect(DetailsSidebar.groups(.all).flatMap(\.sections) == [.home, .limits, .session, .overview, .models, .card, .goals, .account, .settings])
    }

    @Test("Every link into a held-back section lands on Home: sidebar, Home's buttons, For you items, the popover")
    func navigation() {
        let box = Sandbox(); defer { box.cleanUp() }
        var environment = box.model(clock: TestClock()).environment
        environment.features = .shipping
        let model = AppModel(environment: environment)
        for section in AppModel.DetailsSection.allCases {
            model.detailsSection = .limits
            model.detailsSection = section
            #expect(model.detailsSection == (ReleaseFeatures.shipping.allows(section) ? section : .home), "\(section)")
        }
        environment.features = .all
        let full = AppModel(environment: environment)
        full.detailsSection = .card
        #expect(full.detailsSection == .card)
        full.detailsSection = .goals
        #expect(full.detailsSection == .goals)
    }

    @Test("For you never suggests a goal, or any held-back section, when Goals are held back")
    func forYou() {
        var input = ForYou.Input()
        input.goals = [GoalStatus(kind: .fiveHourPeak, value: "97%", amount: 97, target: "≤ 80%", fraction: 1, state: .missed, detail: "d", streak: 0)]
        #expect(ForYou.make(input).map(\.kind) == [.goal])
        input.features = .shipping
        let items = ForYou.make(input)
        #expect(items.map(\.kind) == [.allClear])
        #expect(items.allSatisfy { $0.section.map(ReleaseFeatures.shipping.allows) ?? true })
    }
}
