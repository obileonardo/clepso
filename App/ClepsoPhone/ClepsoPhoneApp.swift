import DesignSystem
import Domain
import Foundation
import SwiftUI
import Sync

@main struct ClepsoPhoneApp: App {
    @State private var model: PhoneModel
    @Environment(\.scenePhase) private var scenePhase
    init() {
        PixelFonts.ensureRegistered()
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let client = SyncClient(config: SyncConfig(infoDictionary: Bundle.main.infoDictionary ?? [:]), now: { SystemClock().now() })
        _model = State(initialValue: PhoneModel(client: client, cache: directory.appendingPathComponent("Clepso/relay.v1.json"), clock: { SystemClock().now() }))
    }
    var body: some Scene {
        WindowGroup {
            PhoneRoot(model: model).environment(\.theme,Theme.phosphor)
                .onOpenURL { url in Task { await model.callback(url) } }
                .task { await model.start() }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        await model.refresh()
                        do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    }
                }
        }
    }
}
