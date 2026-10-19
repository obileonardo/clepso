import DesignSystem
import Foundation
import Storage
import Testing
@testable import ClepsoApp

/// Home's "What's new" card (RELEASE_ROADMAP §6): compiled-in text, shown once after the version changes, never on a
/// fresh install, dismissable, and a changelog link that opens only when clicked.
@Suite("What's new")
@MainActor
struct WhatsNewTests {
    /// One app on one data folder, relaunched at different versions; every link it would open is recorded instead.
    @MainActor final class Mac {
        let box = Sandbox()
        let clock = TestClock()
        var opened: [URL] = []

        func launch(_ version: String) async -> AppModel {
            var environment = AppEnvironment(dataDirectory: box.data, home: box.home, shimPath: "/Applications/Clepso.app/Contents/Helpers/clepso-statusline",
                                             clock: clock, loginItem: FakeLoginItem(), notifications: FakeNotifications(), keychain: FakeKeychain(),
                                             appVersion: version, timeZone: utc, locale: enUS, tickInterval: .seconds(3600))
            environment.openLink = { [weak self] url in self?.opened.append(url) }
            environment.openFile = { [weak self] url in self?.opened.append(url) }
            let model = AppModel(environment: environment)
            await model.start()
            return model
        }

        /// A v0.1 install: onboarding finished, and no seen version recorded (v0.1 had no What's new card).
        func installV01() async throws {
            try FileManager.default.createDirectory(at: box.data, withIntermediateDirectories: true)
            let store = try Store.onDisk(at: box.data.appendingPathComponent(LegacyDataMigration.databaseName), now: clock.now())
            try await store.setPreference(AppModel.Pref.onboardingComplete, true, now: clock.now())
        }

        func seen() async throws -> String? {
            let store = try Store.onDisk(at: box.data.appendingPathComponent(LegacyDataMigration.databaseName), now: clock.now())
            return try await store.preference(AppModel.Pref.whatsNewSeen, as: String.self)
        }

        deinit { box.cleanUp() }
    }

    static let v02 = WhatsNew.entries.first { $0.version == "0.2.0" }

    // MARK: Which entry

    @Test("The newest entry after the last seen version and no later than this one; nothing for a patch, a downgrade or a dev build")
    func choosing() throws {
        let v02 = try #require(Self.v02)
        #expect(WhatsNew.entry(lastSeen: nil, current: "0.2.0") == v02)
        #expect(WhatsNew.entry(lastSeen: "0.1.0", current: "0.2.0") == v02)
        #expect(WhatsNew.entry(lastSeen: "0.1.0", current: "0.2.1") == v02)          // skipped 0.2.0, still news
        #expect(WhatsNew.entry(lastSeen: "dev", current: "0.2.0") == v02)            // unreadable seen: before everything
        #expect(WhatsNew.entry(lastSeen: "0.2.0", current: "0.2.0") == nil)
        #expect(WhatsNew.entry(lastSeen: "0.2.0", current: "0.2.1") == nil)          // a patch without an entry
        #expect(WhatsNew.entry(lastSeen: "0.3.0", current: "0.2.0") == nil)          // a downgrade
        #expect(WhatsNew.entry(lastSeen: nil, current: "0.1.0") == nil)              // older than every entry
        #expect(WhatsNew.entry(lastSeen: nil, current: "dev") == nil)
        let later = ["0.4.0", "0.3.0", "0.2.0"].map { WhatsNew(version: $0, title: "t", summary: "s", highlights: []) }
        #expect(WhatsNew.entry(lastSeen: "0.2.0", current: "0.4.0", in: later)?.version == "0.4.0")   // newest, once
        #expect(WhatsNew.entry(lastSeen: "0.2.0", current: "0.3.5", in: later)?.version == "0.3.0")
        #expect(WhatsNew.entry(lastSeen: "0.3.0", current: "0.3.5", in: later) == nil)
    }

    @Test("Versions compare as numbers, ignoring a pre-release or build suffix")
    func numeric() {
        #expect(WhatsNew.numeric("0.2.0") == [0, 2, 0])
        #expect(WhatsNew.numeric("0.2") == [0, 2, 0])
        #expect(WhatsNew.numeric("0.10.1-test") == [0, 10, 1])
        #expect(WhatsNew.numeric("1.0.0+5") == [1, 0, 0])
        #expect(WhatsNew.numeric("0.10.0")!.lexicographicallyPrecedes([0, 9, 0]) == false)
        for bad in ["dev", "", "0.2.x", "1..0", "1.2.3.4"] { #expect(WhatsNew.numeric(bad) == nil, "\(bad)") }
    }

    @Test("v0.2 spotlights the Player Card and Goals, with pixel icons and a button into each; the link is the site's changelog")
    func content() throws {
        let v02 = try #require(Self.v02)
        #expect(v02.title == "Your first season")
        #expect(v02.highlights.map(\.section) == [.card, .goals, .limits])
        for highlight in v02.highlights {
            #expect(PixelGlyph(symbol: highlight.symbol) != .question, "\(highlight.symbol) has no pixel glyph")
            #expect(!highlight.title.isEmpty && !highlight.detail.isEmpty && !highlight.open.isEmpty)
        }
        #expect(WhatsNew.changelogURL.absoluteString == "https://clepso-app.vercel.app/changelog/")
        // Entries are newest first, each version once and readable.
        let versions = WhatsNew.entries.map { WhatsNew.numeric($0.version) }
        #expect(versions.allSatisfy { $0 != nil })
        #expect(Set(WhatsNew.entries.map(\.version)).count == WhatsNew.entries.count)
        #expect(zip(versions, versions.dropFirst()).allSatisfy { $1!.lexicographicallyPrecedes($0!) })
    }

    // MARK: When it shows

    @Test("A fresh install never shows it: the version is recorded, and it stays hidden after onboarding and a relaunch")
    func freshInstall() async throws {
        let mac = Mac()
        let first = await mac.launch("0.2.0")
        #expect(first.whatsNew == nil)
        #expect(try await mac.seen() == "0.2.0")
        await first.completeOnboarding()
        first.stop()
        let second = await mac.launch("0.2.0")
        #expect(second.whatsNew == nil)
        second.stop()
        #expect(mac.opened.isEmpty)
    }

    @Test("After an update from v0.1 it shows once: still there until Home shows it, gone after a relaunch")
    func onceAfterUpdate() async throws {
        let mac = Mac()
        try await mac.installV01()
        let updated = await mac.launch("0.2.0")
        #expect(updated.whatsNew == Self.v02)
        #expect(try await mac.seen() == nil)                       // not seen until Home shows it
        updated.stop()
        let notYetOpened = await mac.launch("0.2.0")                // the Dashboard was never opened: still news
        #expect(notYetOpened.whatsNew == Self.v02)
        await notYetOpened.whatsNewShown()
        #expect(notYetOpened.whatsNew == Self.v02)                 // stays on screen this run until dismissed
        #expect(try await mac.seen() == "0.2.0")
        notYetOpened.stop()
        let relaunched = await mac.launch("0.2.0")
        #expect(relaunched.whatsNew == nil)
        relaunched.stop()
        let patched = await mac.launch("0.2.1")                    // a patch with no entry of its own: nothing new
        #expect(patched.whatsNew == nil)
        #expect(try await mac.seen() == "0.2.1")
        patched.stop()
        #expect(mac.opened.isEmpty)
    }

    @Test("A user who installed 0.1 with this card's code and updates sees it too")
    func updateWithRecordedVersion() async throws {
        let mac = Mac()
        let v01 = await mac.launch("0.1.0")
        #expect(v01.whatsNew == nil)
        await v01.completeOnboarding()
        v01.stop()
        let v02 = await mac.launch("0.2.0")
        #expect(v02.whatsNew == Self.v02)
        v02.stop()
    }

    @Test("Dismiss hides it at once and for good, and opens nothing")
    func dismiss() async throws {
        let mac = Mac()
        try await mac.installV01()
        let model = await mac.launch("0.2.0")
        #expect(model.whatsNew != nil)
        await model.dismissWhatsNew()
        #expect(model.whatsNew == nil)
        #expect(try await mac.seen() == "0.2.0")
        model.stop()
        let relaunched = await mac.launch("0.2.0")
        #expect(relaunched.whatsNew == nil)
        relaunched.stop()
        #expect(mac.opened.isEmpty)
    }

    @Test("No network: showing and dismissing open nothing; only a click on the link opens the changelog, in the browser")
    func linkOnlyOnClick() async throws {
        let mac = Mac()
        try await mac.installV01()
        let model = await mac.launch("0.2.0")
        await model.whatsNewShown()
        #expect(mac.opened.isEmpty)
        model.openChangelog()
        #expect(mac.opened == [WhatsNew.changelogURL])
        await model.dismissWhatsNew()
        #expect(mac.opened == [WhatsNew.changelogURL])
        model.stop()
    }

    @Test("Delete all leaves a fresh install: no card, and none after onboarding again")
    func afterDeleteAll() async throws {
        let mac = Mac()
        try await mac.installV01()
        let model = await mac.launch("0.2.0")
        #expect(model.whatsNew != nil)
        _ = await model.deleteAll(includeBackups: false, relaunch: true)
        #expect(model.whatsNew == nil)
        #expect(try await mac.seen() == "0.2.0")
        model.stop()
    }
}
