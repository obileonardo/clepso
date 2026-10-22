import ClepsoApp
import Foundation
import Sparkle

@MainActor final class AppUpdater: NSObject, AppUpdating, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController!
    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        controller.updater.sendsSystemProfile = false
        controller.startUpdater()
    }
    // Capability, not Sparkle's transient busy state. Otherwise an unobserved KVO transition can leave Settings
    // permanently disabled after a check. The standard controller handles an already-running session itself.
    let available = true
    var automaticChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
    var automaticDownloads: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { controller.updater.automaticallyDownloadsUpdates = newValue }
    }
    func check() { controller.checkForUpdates(nil) }
    func feedURLString(for updater: SPUUpdater) -> String? { "https://clepso-app.vercel.app/updates/appcast.xml" }
    func allowedChannels(for updater: SPUUpdater) -> Set<String> { ["alpha"] }
}

extension AppEnvironment {
    @MainActor static func withUpdater() -> AppEnvironment {
        var environment = live()
        // Isolated render/QA runs must not invoke the real updater, its preferences or network.
        if !environment.isolated { environment.updater = AppUpdater() }
        return environment
    }
}
