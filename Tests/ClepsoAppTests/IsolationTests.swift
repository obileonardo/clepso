import AppKit
import Foundation
@testable import Sync
import Testing
@testable import ClepsoApp

/// A debug run on another home or data folder is the installed Clepso to macOS (same bundle identifier). These prove it
/// gets a stand-in for everything macOS keeps per app, and that a run without those flags is the real app, unchanged.
/// Nothing here touches the Mac's login items, notification centre or Keychain: the environments are built, not used.
@Suite("Isolated debug runs")
struct IsolationTests {
    static func flags(_ values: [String: String]) -> (String) -> String? { { values[$0] } }

    @Test("Any of -ClepsoHome, -ClepsoDataDirectory, -ClepsoProbeOutput gives stand-ins for every per-app system service")
    func isolatedStandIns() async {
        for values in [["ClepsoDataDirectory": "/tmp/cd"], ["ClepsoHome": "/tmp/ch"],
                       ["ClepsoHome": "/tmp/ch", "ClepsoProbeOutput": "/tmp/shots"]] {
            let environment = AppEnvironment.live(bundle: .main, flag: Self.flags(values))
            #expect(environment.isolated, "\(values)")
            #expect(environment.loginItem is IsolatedLoginItem, "\(values)")
            #expect(environment.notifications is IsolatedNotifications, "\(values)")
            #expect(environment.keychain is IsolatedKeychain, "\(values)")
            #expect(await environment.sync.store is MemoryAuthStore, "\(values)")
        }
    }

    @Test("No flags: the real app, with the system's login item, notification centre and Keychain")
    func productionUnchanged() async {
        let environment = AppEnvironment.live(bundle: .main, flag: Self.flags([:]))
        #expect(!environment.isolated)
        #expect(environment.rewritesHome)
        #expect(environment.loginItem is SystemLoginItem)
        #expect(environment.notifications is SystemNotifications)
        #expect(environment.keychain is SystemKeychain)
        #expect(await environment.sync.store is KeychainAuthStore)
        #expect(environment.dataDirectory.path.hasSuffix("Library/Application Support/Clepso"))
    }

    @Test("Only a run with its own home may repair files in it; -ClepsoDataDirectory alone reads the real home")
    func rewritesOnlyItsOwnHome() {
        #expect(!AppEnvironment.live(bundle: .main, flag: Self.flags(["ClepsoDataDirectory": "/tmp/cd"])).rewritesHome)
        let own = AppEnvironment.live(bundle: .main, flag: Self.flags(["ClepsoHome": "/tmp/ch"]))
        #expect(own.rewritesHome)
        #expect(own.dataDirectory.path == "/tmp/ch/Library/Application Support/Clepso")
    }

    @Test("A probe without its own home or data folder is refused before it starts")
    func probeNeedsItsOwnData() {
        #expect(AppEnvironment.launchProblem(flag: Self.flags(["ClepsoProbeOutput": "/tmp/shots"])) != nil)
        #expect(AppEnvironment.launchProblem(flag: Self.flags(["ClepsoProbeOutput": "/tmp/shots", "ClepsoDataDirectory": "/tmp/cd"])) == nil)
        #expect(AppEnvironment.launchProblem(flag: Self.flags(["ClepsoProbeOutput": "/tmp/shots", "ClepsoHome": "/tmp/ch"])) == nil)
        #expect(AppEnvironment.launchProblem(flag: Self.flags([:])) == nil)
    }

    @Test("The stand-ins: the login switch lives in memory, notifications read as allowed and hold nothing")
    func standInBehaviour() async throws {
        let login = IsolatedLoginItem()
        #expect(!login.isEnabled)
        try login.setEnabled(true)
        #expect(login.isEnabled)
        let notifications = IsolatedNotifications()
        #expect(await notifications.status() == .authorized)
        #expect(await notifications.pendingReminders().isEmpty)
    }

    @Test("An isolated run on the real home never re-points the installed status line at itself")
    @MainActor func noRepairOfTheRealHome() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        try Data("{}\n".utf8).write(to: box.settings)
        let installed = box.model(clock: TestClock())             // the installed app: installs, then quits
        await installed.start()
        guard case .installed = await installed.install() else { Issue.record("install failed"); return }
        installed.stop()
        let wrapper = box.home.appendingPathComponent(".claude/clepso/statusline.sh")
        let config = box.home.appendingPathComponent(".claude/clepso/config.json")
        let before = (try Data(contentsOf: wrapper), try Data(contentsOf: config))

        // A debug run: same home, its own data folder (another socket) and helper.
        var environment = installed.environment
        environment.dataDirectory = box.root.appendingPathComponent("debug-data")
        environment.shimPath = "/tmp/DerivedData/Clepso.app/Contents/Helpers/clepso-statusline"
        environment.isolated = true
        environment.rewritesHome = false
        let debug = AppModel(environment: environment)
        await debug.start()
        await debug.setForwardCost(false)
        _ = await debug.approveAgentName("db-helper")
        debug.stop()
        #expect(try Data(contentsOf: wrapper) == before.0, "the wrapper still runs the installed helper")
        #expect(try Data(contentsOf: config) == before.1, "the config still names the installed app's socket")

        // Control: the same run allowed to rewrite (its own home) does repair, so the check above can fail.
        environment.rewritesHome = true
        let repairing = AppModel(environment: environment)
        await repairing.start(); repairing.stop()
        #expect(try Data(contentsOf: wrapper) != before.0)
    }

    @Test("An isolated run ignores a sign-in link it did not ask for; the real app opens Account for it")
    @MainActor func signInLinkNotTaken() async {
        let box = Sandbox(); defer { box.cleanUp() }
        let link = URL(string: "clepso://auth-callback#access_token=x")!
        let real = box.model(clock: TestClock())
        real.detailsSection = .home
        await real.handleOpenURL(link)
        #expect(real.detailsSection == .account)

        var environment = real.environment
        environment.isolated = true
        let debug = AppModel(environment: environment)
        debug.detailsSection = .home
        await debug.handleOpenURL(link)
        #expect(debug.detailsSection == .home)
        #expect(debug.accountMessage == nil)
    }

    @Test("An isolated run's windows keep no saved frame and are not restored at the next launch")
    @MainActor func windowsDetached() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        #expect(window.isRestorable)
        IsolatedWindowHook.HookView.detach(window)
        #expect(!window.isRestorable)
        #expect(window.frameAutosaveName.isEmpty)
    }
}
