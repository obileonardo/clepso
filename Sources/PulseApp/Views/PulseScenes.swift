import AppKit
import DesignSystem
import Domain
import SwiftUI

/// The app's scenes; the Xcode app target's `@main` only creates the model and returns these.
public struct PulseScenes: Scene {
    public static let onboardingID = "onboarding"
    let model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
                .environment(\.theme, .mac)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model).environment(\.theme, .mac)
        }

        Window("Welcome to \(Product.name)", id: Self.onboardingID) {
            OnboardingView(model: model).environment(\.theme, .mac)
        }
        .windowResizability(.contentSize)
    }
}

/// The status item: shape, optional text, and the aggregate line as its accessibility label (AT-07).
/// It is also the first view SwiftUI creates, so it starts the model and opens onboarding on first run.
struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let snapshot = model.snapshot
        HStack(spacing: 0) {
            Image(nsImage: MenuBarIcon.image(snapshot.iconShape, staleMark: snapshot.iconStaleMark))
            if let text = snapshot.iconText { Text(" " + text).monospacedDigit() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.iconAccessibilityLabel)
        .accessibilityRemoveTraits(.isImage)
        .help(snapshot.aggregateLine)
        .task {
            await model.start()
            #if DEBUG
            if await PopoverProbe.runIfRequested(model: model, openWindow: { openWindow(id: PulseScenes.onboardingID) },
                                                openSettings: { openSettings() }) { return }
            #endif
            if !model.onboardingComplete {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: PulseScenes.onboardingID)
            }
        }
    }
}
