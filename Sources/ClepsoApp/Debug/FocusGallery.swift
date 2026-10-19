#if DEBUG
import AppKit
import DesignSystem
import SwiftUI

/// Item 9, debug probe only (`-ClepsoProbeFocusGallery YES`): every kind of control the app draws itself, beside the
/// native ones for comparison, in a window of its own. The probe moves keyboard focus through them with SwiftUI's own
/// `@FocusState`, then with Tab key events handed to this window, and captures each, so the focus indicator of every
/// style can be seen and judged (one pixel ring, no system ring).
@MainActor @Observable
final class FocusGalleryState {
    /// The control the probe wants focused, and the one SwiftUI reports focused.
    var request: Int?
    var reported: Int?
    var day: String?
    /// How many pixel focus rings the window draws (`PixelFocusRingCount`): one while a self-drawn control is focused.
    var rings = 0
    /// Each control's action, by name, in the order they ran (Space, Return and Escape from the probe's key events).
    var activations: [String] = []
    var toggleOn = true
}

struct FocusGallery: View {
    @Bindable var state: FocusGalleryState
    @State private var segment = 0
    @State private var text = ""
    @State private var day: String?
    @FocusState private var focused: Int?
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    static let names = ["pixel-button", "pixel-prominent", "pixel-destructive", "pixel-quiet", "plain-row", "pixel-toggle",
                        "pixel-segmented", "native-textfield", "chart", "calendar"]

    static let bars: [(day: String, value: Int64)] = (1...14).map { (String(format: "2026-10-%02d", $0), Int64(($0 * 37) % 90 + 10)) }
    static let grid = StatsCalendar.Grid(
        weeks: (0..<4).map { w in (0..<7).map { d in
            let n = w * 7 + d + 1
            return StatsCalendar.Cell(date: String(format: "2026-09-%02d", n), state: n > 26 ? .noData : .level(n % 5), messages: n * 3, sessions: n % 4)
        } },
        months: [(0, "Sep")])

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
            HStack(spacing: theme.spacing(.spacious)) {
                // Escape and Return reach these through their shortcuts, as in the app's sheets and onboarding.
                Button("Secondary") { ran(0) }.keyboardShortcut(.cancelAction).buttonStyle(PixelButtonStyle()).focused($focused, equals: 0)
                Button("Primary") { ran(1) }.buttonStyle(PixelButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
                    .focused($focused, equals: 1)
                Button("Delete") { ran(2) }.buttonStyle(PixelButtonStyle(destructive: true)).focused($focused, equals: 2)
                Button("Quit") { ran(3) }.buttonStyle(PixelQuietButtonStyle()).focused($focused, equals: 3)
            }
            Button { ran(4) } label: {
                Text("Plain row (sidebar, limit card, chip)").font(theme.font(.label))
                    .foregroundStyle(theme.color(.textPrimary, scheme))
                    .padding(theme.spacing(.standard))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PixelPlainButtonStyle())
            .focused($focused, equals: 4)
            Toggle("Alerts", isOn: $state.toggleOn).toggleStyle(PixelToggleStyle()).focused($focused, equals: 5)
            PixelSegmented("Range", options: [(0, "All time"), (1, "30 days"), (2, "7 days")], selection: $segment)
                .focused($focused, equals: 6)
            TextField("Name", text: $text).textFieldStyle(.roundedBorder).focused($focused, equals: 7)
            DailyBars(values: Self.bars, unit: "Messages").frame(height: DetailsMetrics.chartHeight).focused($focused, equals: 8)
            CalendarGridView(grid: Self.grid, cell: theme.spacing(.spacious), showDayNumbers: false, selected: day, onSelect: { day = $0 })
                .focused($focused, equals: 9)
        }
        .padding(theme.spacing(.section))
        .frame(width: DetailsMetrics.settingsColumn)
        .background(theme.color(.background, scheme))
        .onChange(of: state.request) { focused = state.request }
        .onChange(of: day) { state.day = day }
        .onChange(of: focused) { state.reported = focused }
        .onPreferenceChange(PixelFocusRingCount.self) { [state] rings in MainActor.assumeIsolated { state.rings = rings } }
    }

    private func ran(_ index: Int) { state.activations.append(Self.names[index]) }
}
#endif
