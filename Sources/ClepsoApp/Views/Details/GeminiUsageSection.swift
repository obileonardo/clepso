import DesignSystem
import SwiftUI

struct GeminiUsageSection: View {
    let model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if model.geminiEnabled, !model.demo {
            PageSection("GEMINI CLI · RECORDED ACTIVITY", "The newest 16 retained recordings on this Mac. These token counts do not measure your subscription allowance.") {
                if let usage = model.geminiUsage {
                    VStack(alignment: .leading, spacing: 0) {
                        FactRow(label: "Recorded total tokens", value: Formatting.tokens(usage.total, locale: model.environment.locale))
                        FactRow(label: "Input · cache included", value: Formatting.tokens(usage.input, locale: model.environment.locale))
                        FactRow(label: "Output", value: Formatting.tokens(usage.output, locale: model.environment.locale))
                        FactRow(label: "Cached input", value: Formatting.tokens(usage.cachedInput, locale: model.environment.locale))
                        FactRow(label: "Reasoning", value: Formatting.tokens(usage.reasoning, locale: model.environment.locale))
                        FactRow(label: "Tool tokens", value: Formatting.tokens(usage.tool, locale: model.environment.locale))
                        FactRow(label: "Recorded messages", value: Formatting.tokens(Int64(usage.messages), locale: model.environment.locale))
                        FactRow(label: "Last activity", value: Formatting.age(of: usage.observedAt, now: model.snapshot.now, zone: model.environment.timeZone, locale: model.environment.locale))
                        Text(usage.incomplete ? "Partial record coverage. Oversized, unreadable or additional recordings were excluded. Deleted history can reduce these counts." : "Automatic local recording read. Deleted history can reduce these counts. Quota percentage and reset time are unavailable from this source.")
                            .font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                            .fixedSize(horizontal: false, vertical: true).padding(.top, theme.spacing(.standard))
                    }
                } else {
                    Text("Awaiting a recorded Gemini response with token counters. Your allowance is unknown; no zero is inferred.")
                        .font(theme.font(.label)).foregroundStyle(theme.color(.textSecondary, scheme))
                }
            }
        }
    }
}
