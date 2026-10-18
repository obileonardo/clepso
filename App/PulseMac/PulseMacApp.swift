import PulseApp
import SwiftUI

// The app target is deliberately thin (ARCHITECTURE §2): everything testable lives in the PulseApp package target.
@main
struct PulseMacApp: App {
    @State private var model = AppModel(environment: .live())
    @NSApplicationDelegateAdaptor(QuitHandler.self) private var quitHandler

    var body: some Scene {
        PulseScenes(model: model, quitHandler: quitHandler)
    }
}
