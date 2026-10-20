import AppKit
import DesignSystem
import Domain
import SwiftUI

/// The app's scenes; the Xcode app target's `@main` only creates the model and returns these.
public struct ClepsoScenes: Scene {
    public static let onboardingID = "onboarding"
    public static let detailsID = "details"
    let model: AppModel

    public init(model: AppModel, quitHandler: QuitHandler? = nil) {
        self.model = model
        quitHandler?.model = model
    }

    public var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model).themed(model)
        } label: {
            MenuBarLabel(model: model)
                .modifier(ReduceMotionRoot(forced: ThemedRoot.forceReduceMotion))
        }
        .menuBarExtraStyle(.window)

        Window(Product.name, id: Self.detailsID) {
            DetailsView(model: model).themed(model)
                .onOpenURL { url in Task { await model.handleOpenURL(url) } }      // the sign-in link returns here
        }
        .handlesExternalEvents(matching: ["auth-callback"])
        .defaultSize(width: DetailsMetrics.defaultWidth, height: DetailsMetrics.minHeight + 160)
        .commands { SettingsCommand(model: model) }

        Window("Welcome to \(Product.name)", id: Self.onboardingID) {
            OnboardingView(model: model).themed(model)
        }
        .windowResizability(.contentSize)
    }
}

/// Item 9: ⌘, opens Settings, as in every Mac app. Settings is a page of the Dashboard, so the app menu's Settings item
/// (hidden with the menu bar of a menu bar app, but its shortcut works whenever Clepso is active: popover, Dashboard
/// or onboarding) opens the Dashboard on that page.
struct SettingsCommand: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(Copy.SettingsPage.title + "…") {
                model.detailsSection = .settings
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: ClepsoScenes.detailsID)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
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
            .modifier(ReduceMotionRoot(forced: Self.forceReduceMotion))
            .background { if model.environment.isolated { IsolatedWindowHook() } }
    }

    #if DEBUG
    static var forceReduceMotion: Bool { ProbeOverrides.reduceMotion }
    #else
    static let forceReduceMotion = false
    #endif

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

/// The status item: shape, optional text, the aggregate line as its accessibility label (AT-07) and the state in
/// words as its value.
/// It is also the first view SwiftUI creates, so it starts the model and opens onboarding on first run.
struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.reduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var tick = 0
    @State private var hovering = false

    private var rotationKey: String {
        guard model.showPercent, model.menuBarDisplay == .rotating, !reduceMotion, !voiceOver, !hovering,
              model.snapshot.rotatingReadouts.count > 1 else { return "" }
        return model.snapshot.rotatingReadouts.map(\.poolKey).joined(separator: "|")
    }

    var body: some View {
        let snapshot = model.snapshot
        let readout = model.showPercent ? snapshot.menuBarReadout(display: model.menuBarDisplay, tick: reduceMotion || voiceOver ? 0 : tick) : nil
        let shape = readout?.shape ?? snapshot.iconShape
        let staleMark = readout?.staleMark ?? snapshot.iconStaleMark
        // One template image, with the existing design-system state glyph and an attributed limit readout.
        Image(nsImage: MenuBarIcon.pixelImage(shape, staleMark: staleMark, text: readout?.text ?? snapshot.iconText,
                                            reservingText: readout == nil ? [] : reservedText))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Product.name): \(snapshot.menuBarHelp)")
        .accessibilityValue(MenuBarIcon.spokenState(shape, staleMark: staleMark))
        .accessibilityRemoveTraits(.isImage)
        .help(snapshot.menuBarHelp)
        .onHover { hovering = $0 } // hover-ok: pauses rotation; all readings are also in the accessible label and panel.
        .task(id: rotationKey) {
            guard !rotationKey.isEmpty else { return }
            tick = 0
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(MenuBarReadout.rotationInterval)) } catch { return }
                tick = (tick + 1) % max(1, model.snapshot.rotatingReadouts.count)
            }
        }
        .onChange(of: model.dashboardRequests) {                 // 2.1: a click on a limit alert opens Limits
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: ClepsoScenes.detailsID)
        }
        .task {
            await model.start()
            #if DEBUG
            if await PopoverProbe.runIfRequested(model: model, openWindow: { openWindow(id: ClepsoScenes.onboardingID) },
                                                openDetails: { openWindow(id: ClepsoScenes.detailsID) }) { return }
            #endif
            PopoverWarmUp.run(model)
            if !model.onboardingComplete {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: ClepsoScenes.onboardingID)
            }
        }
    }

    /// Enough room for every current frame and the longest normal reading, including its explicit stale suffix.
    /// This also keeps the width steady as a live percentage gains a digit.
    private var reservedText: [String] {
        model.snapshot.menuBarReadouts.map(\.text) + ["\(model.snapshot.isDemo ? "DEMO " : "")Claude 5h 100.0% OLD"]
    }
}

/// An isolated debug run's windows (`AppEnvironment.isolated`) keep no saved frame and are not reopened at the next
/// launch: both live in the installed app's defaults and saved state (same bundle identifier), where a probe's window
/// sizes would replace the user's.
struct IsolatedWindowHook: NSViewRepresentable {
    func makeNSView(context: Context) -> HookView { HookView() }
    func updateNSView(_ view: HookView, context: Context) {}

    final class HookView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            Self.detach(window)
            DispatchQueue.main.async { Self.detach(window) }      // again once SwiftUI has named the scene's frame
        }

        static func detach(_ window: NSWindow) {
            if !window.frameAutosaveName.isEmpty { window.setFrameAutosaveName("") }
            window.isRestorable = false
        }
    }
}
