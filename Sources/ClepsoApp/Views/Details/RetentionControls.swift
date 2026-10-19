import DesignSystem
import SwiftUI

extension SettingsSection {
    var retentionControls: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            row("clock", Copy.Retention.title, Copy.Retention.subtitle) { EmptyView() }
            retentionChoice(Copy.Retention.readings, options: DataRetention.readingOptions, key: \.readings)
            retentionChoice(Copy.Retention.sessions, options: DataRetention.sessionOptions, key: \.sessions)
            retentionChoice(Copy.Retention.receipts, options: DataRetention.sessionOptions, key: \.receipts)
            retentionChoice(Copy.Retention.logs, options: DataRetention.logOptions, key: \.logs)
            Text(Copy.Retention.warning).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, theme.spacing(.standard))
    }

    func retentionChoice(_ label: String, options: [Int], key: WritableKeyPath<DataRetention, Int>) -> some View {
        HStack(spacing: theme.spacing(.standard)) {
            Text(label).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
            Spacer()
            PixelSegmented(label, options: options.map { ($0, Copy.Retention.days($0)) },
                           selection: Binding(get: { model.dataRetention[keyPath: key] }, set: { days in
                var value = model.dataRetention
                value[keyPath: key] = days
                Task { await model.setDataRetention(value) }
            }))
        }
    }
}
