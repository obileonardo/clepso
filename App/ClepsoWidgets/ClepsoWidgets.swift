import DesignSystem
import Foundation
import IntegrationSnapshot
import SwiftUI
import WidgetKit

struct LimitEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
}

struct LimitsProvider: TimelineProvider {
    func placeholder(in context: Context) -> LimitEntry { .init(date: Date(), snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (LimitEntry) -> Void) { completion(read(at: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LimitEntry>) -> Void) {
        let now = Date(), entry = read(at: Date())
        // Re-evaluate labels at freshness/reset boundaries even if the app no longer publishes.
        let boundaries = (entry.snapshot?.limits ?? []).flatMap { limit in
            [limit.observedAt?.addingTimeInterval(600), limit.resetsAt].compactMap { $0 }
        }.filter { $0 > now && $0 < now.addingTimeInterval(3600) }
        let dates = Set(boundaries + [now.addingTimeInterval(600)])
        let entries = [entry] + dates.sorted().map { LimitEntry(date: $0, snapshot: entry.snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
    }
    private func read(at date: Date) -> LimitEntry {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "ClepsoWidgetGroup") as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group),
              let snapshot = try? SnapshotFile(dataDirectory: container).load(), !snapshot.demo else { return .init(date: date, snapshot: nil) }
        return .init(date: date, snapshot: snapshot)
    }
}

struct LimitsWidgetView: View {
    let entry: LimitEntry
    let family: WidgetFamily
    @Environment(\.colorScheme) private var scheme
    private let theme = Theme.phosphor
    private var rows: [UsageSnapshot.Limit] {
        Array((entry.snapshot?.limits ?? []).sorted {
            if $0.source != $1.source { return $0.source == .automatic }
            if $0.provider != $1.provider { return $0.provider.rawValue < $1.provider.rawValue }
            return $0.window.rawValue < $1.window.rawValue
        }.prefix(family == .systemSmall ? 2 : 4))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            HStack {
                Text("CLEPSO").font(theme.font(.title))
                Spacer()
                if let date = entry.snapshot?.generatedAt {
                    Text(age(date)).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .accessibilityLabel("Snapshot updated \(date.formatted())")
                }
            }
            if rows.isEmpty {
                Text("Your limits, here.").font(theme.font(.label))
                Text("Open Clepso → Settings → Integrations to share widget readings.")
                    .font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
            } else {
                if family == .systemMedium {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: theme.spacing(.spacious)), GridItem(.flexible())], alignment: .leading, spacing: theme.spacing(.standard)) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in reading(row) }
                    }
                } else {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in reading(row) }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(theme.color(.textPrimary, scheme))
        .containerBackground(theme.color(.background, scheme), for: .widget)
        .widgetURL(URL(string: "clepso://dashboard"))
    }
    private func reading(_ row: UsageSnapshot.Limit) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.compact)) {
            VStack(alignment: .leading, spacing: theme.spacing(.compact) / 2) {
                Text(provider(row.provider) + " · " + window(row.window)).font(theme.font(.micro))
                    .lineLimit(1).minimumScaleFactor(0.75)
                Text(detail(row)).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Text(row.usedPercent.map { String(format: "%.0f%%", $0) } ?? "—")
                .font(theme.font(.metricMedium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                .accessibilityLabel(row.usedPercent.map { "\($0) percent used" } ?? "Usage not reported")
        }
        .accessibilityElement(children: .combine)
    }
    private func provider(_ provider: UsageSnapshot.Provider) -> String {
        switch provider {
        case .claudeCode: "CLAUDE"
        case .claudeChat: "CLAUDE CHAT"
        default: provider.rawValue.uppercased()
        }
    }
    private func window(_ window: UsageSnapshot.Window) -> String {
        switch window { case .fiveHour: "5H"; case .weekly: "7D"; case .daily: "DAY" }
    }
    private func detail(_ row: UsageSnapshot.Limit) -> String {
        let source = row.source == .manual ? "Manual · " : ""
        if row.effectiveState(at: entry.date) == .resetExpected { return source + "Reset expected" }
        if row.usedPercent == nil { return source + "Not reported" }
        if row.freshness(at: entry.date) == "stale" { return source + "Old reading" }
        return source + "Reported used"
    }
    private func age(_ date: Date) -> String {
        let minutes = max(0, Int(entry.date.timeIntervalSince(date) / 60))
        if minutes >= 60 { return "\(minutes / 60)H OLD" }
        if minutes >= 10 { return "\(minutes)M OLD" }
        return minutes == 0 ? "JUST NOW" : "\(minutes)M AGO"
    }
}

struct LimitsWidgetHost: View {
    let entry: LimitEntry
    @Environment(\.widgetFamily) private var family
    var body: some View { LimitsWidgetView(entry: entry, family: family) }
}

@main
struct ClepsoLimitsWidget: Widget {
    init() { PixelFonts.ensureRegistered() }
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClepsoLimits", provider: LimitsProvider()) { LimitsWidgetHost(entry: $0) }
            .configurationDisplayName("Clepso limits")
            .description("Reported usage, with source and freshness. Open Clepso to choose widget sharing.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
