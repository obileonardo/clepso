#if DEBUG
import AppKit
import DesignSystem
import SwiftUI

/// Item 9, debug probe only (`-PulseProbeFocusGallery YES`): every kind of control the app draws itself, beside the
/// native ones for comparison, in a window of its own. The probe moves keyboard focus through them with SwiftUI's own
/// `@FocusState` (no key event is posted) and captures each, so the focus indicator of every style can be seen.
@MainActor @Observable
final class FocusGalleryState {
    /// The control the probe wants focused, and the one SwiftUI reports focused.
    var request: Int?
    var reported: Int?
}

struct FocusGallery: View {
    @Bindable var state: FocusGalleryState
    @State private var on = true
    @State private var segment = 0
    @State private var text = ""
    @FocusState private var focused: Int?
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    static let names = ["pixel-button", "pixel-prominent", "pixel-destructive", "pixel-quiet", "plain-row", "pixel-toggle",
                        "pixel-segmented", "native-textfield"]

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
            HStack(spacing: theme.spacing(.spacious)) {
                Button("Secondary") {}.buttonStyle(PixelButtonStyle()).focused($focused, equals: 0)
                Button("Primary") {}.buttonStyle(PixelButtonStyle(prominent: true)).focused($focused, equals: 1)
                Button("Delete") {}.buttonStyle(PixelButtonStyle(destructive: true)).focused($focused, equals: 2)
                Button("Quit") {}.buttonStyle(PixelQuietButtonStyle()).focused($focused, equals: 3)
            }
            Button {} label: {
                Text("Plain row (sidebar, limit card, chip)").font(theme.font(.label))
                    .foregroundStyle(theme.color(.textPrimary, scheme))
                    .padding(theme.spacing(.standard))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($focused, equals: 4)
            Toggle("Alerts", isOn: $on).toggleStyle(PixelToggleStyle()).focused($focused, equals: 5)
            PixelSegmented("Range", options: [(0, "All time"), (1, "30 days"), (2, "7 days")], selection: $segment)
                .focused($focused, equals: 6)
            TextField("Name", text: $text).textFieldStyle(.roundedBorder).focused($focused, equals: 7)
        }
        .padding(theme.spacing(.section))
        .background(theme.color(.background, scheme))
        .onChange(of: state.request) { focused = state.request }
        .onChange(of: focused) { state.reported = focused }
    }
}
#endif
