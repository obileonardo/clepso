import DesignSystem
import SwiftUI

/// Item 9: a chart's hover readout without a pointer. The chart takes keyboard focus (Tab), shows the pixel focus ring,
/// starts at the latest bar, and ← → move the same `hover` index the pointer sets, so the readout under the chart
/// follows. VoiceOver reads the readout as the chart's value and steps through bars with its adjust gestures.
enum ChartCursor {
    /// The bar after an arrow (`delta` −1 or +1): from none, the latest bar; otherwise one step, held at the ends.
    static func step(_ current: Int?, count: Int, by delta: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let current, current < count else { return count - 1 }
        return min(max(current + delta, 0), count - 1)
    }
}

struct ChartKeyboard: ViewModifier {
    @Binding var index: Int?
    let count: Int
    /// The readout for `index`, or nil when no bar is chosen.
    let readout: String?
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($focused)
            .focusEffectDisabled()                       // the pixel ring instead of the system's rounded one
            .pixelFocusRing(focused)
            .onChange(of: focused) { _, now in index = now ? ChartCursor.step(index, count: count, by: 0) : nil }
            .onMoveCommand { direction in
                switch direction {
                case .left: index = ChartCursor.step(index, count: count, by: -1)
                case .right: index = ChartCursor.step(index, count: count, by: 1)
                default: break
                }
            }
            .accessibilityValue(readout ?? "")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: index = ChartCursor.step(index, count: count, by: 1)
                case .decrement: index = ChartCursor.step(index, count: count, by: -1)
                @unknown default: break
                }
            }
    }
}

extension View {
    /// Makes a hover-readout chart reachable from the keyboard and VoiceOver (`ChartKeyboard`).
    func chartKeyboard(_ index: Binding<Int?>, count: Int, readout: String?) -> some View {
        modifier(ChartKeyboard(index: index, count: count, readout: readout))
    }
}
