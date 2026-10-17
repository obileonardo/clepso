import AppKit
import DesignSystem
import Domain
import SwiftUI

/// The app's scenes; the Xcode app target's `@main` only creates the model and returns these.
public struct PulseScenes: Scene {
    public static let onboardingID = "onboarding"
    public static let detailsID = "details"
    /// Native controls (toggles, pickers) take the Phosphor accent.
    static let accent = Theme.phosphor.color(.accent, .dark)
    let model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
                .environment(\.theme, .phosphor)
                .preferredColorScheme(.dark)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window(Product.name, id: Self.detailsID) {
            DetailsView(model: model).environment(\.theme, .phosphor).preferredColorScheme(.dark)
                .onOpenURL { url in Task { await model.handleOpenURL(url) } }      // the sign-in link returns here (ROADMAP 2.0)
        }
        .handlesExternalEvents(matching: ["auth-callback"])
        .defaultSize(width: DetailsMetrics.defaultWidth, height: DetailsMetrics.minHeight + 160)

        Window("Welcome to \(Product.name)", id: Self.onboardingID) {
            OnboardingView(model: model).environment(\.theme, .phosphor).preferredColorScheme(.dark).tint(PulseScenes.accent)
        }
        .windowResizability(.contentSize)
    }
}

/// The status item: shape, optional text, and the aggregate line as its accessibility label (AT-07).
/// It is also the first view SwiftUI creates, so it starts the model and opens onboarding on first run.
struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let snapshot = model.snapshot
        // One template image (pixel ring + the % in the pixel face): the menu bar ignores custom fonts in Text.
        Image(nsImage: MenuBarIcon.pixelImage(snapshot.iconShape, staleMark: snapshot.iconStaleMark, text: snapshot.iconText))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.iconAccessibilityLabel)
        .accessibilityRemoveTraits(.isImage)
        .help(snapshot.aggregateLine)
        .task {
            await model.start()
            #if DEBUG
            if await PopoverProbe.runIfRequested(model: model, openWindow: { openWindow(id: PulseScenes.onboardingID) },
                                                openDetails: { openWindow(id: PulseScenes.detailsID) }) { return }
            #endif
            if !model.onboardingComplete {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: PulseScenes.onboardingID)
            }
        }
    }
}
