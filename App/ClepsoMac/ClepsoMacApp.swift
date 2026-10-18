import ClepsoApp
import SwiftUI

// The app target is deliberately thin (ARCHITECTURE §2): everything testable lives in the ClepsoApp package target.
@main
struct ClepsoMacApp: App {
    @State private var model = AppModel(environment: .live())
    @NSApplicationDelegateAdaptor(QuitHandler.self) private var quitHandler

    var body: some Scene {
        ClepsoScenes(model: model, quitHandler: quitHandler)
    }
}
