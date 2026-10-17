import AppKit
import DesignSystem
import Domain
import SwiftUI

/// The app's scenes; the Xcode app target's `@main` only creates the model and returns these.
public struct PulseScenes: Scene {
    public static let onboardingID = "onboarding"
    public static let detailsID = "details"
    let model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model).themed(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window(Product.name, id: Self.detailsID) {
            DetailsView(model: model).themed(model)
                .onOpenURL { url in Task { await model.handleOpenURL(url) } }      // the sign-in link returns here (ROADMAP 2.0)
        }
        .handlesExternalEvents(matching: ["auth-callback"])
        .defaultSize(width: DetailsMetrics.defaultWidth, height: DetailsMetrics.minHeight + 160)

        Window("Welcome to \(Product.name)", id: Self.onboardingID) {
            OnboardingView(model: model).themed(model)
        }
        .windowResizability(.contentSize)
    }
}

/// Every window's root (1.15): the chosen colour theme, the chosen appearance, and native controls (pickers,
/// toggles, focus rings) tinted with that theme's accent for the scheme actually shown.
struct ThemedRoot: ViewModifier {
    let model: AppModel
    func body(content: Content) -> some View {
        content.modifier(Tint(theme: model.theme)).environment(\.theme, model.theme)
            .modifier(Scheme(forced: model.appearance.colorScheme))
            .preferredColorScheme(model.appearance.colorScheme)
    }

    /// `preferredColorScheme` never reaches the menu bar panel (it follows the menu bar), so a chosen Light or Dark is
    /// also set in the environment, which is what every token and native control reads.
    struct Scheme: ViewModifier {
        let forced: ColorScheme?
        func body(content: Content) -> some View {
            if let forced { content.environment(\.colorScheme, forced) } else { content }
        }
    }

    struct Tint: ViewModifier {
        let theme: Theme
        @Environment(\.colorScheme) private var scheme
        func body(content: Content) -> some View { content.tint(theme.color(.accent, scheme)) }
    }
}

extension View {
    func themed(_ model: AppModel) -> some View { modifier(ThemedRoot(model: model)) }
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
