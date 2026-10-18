import struct CodexAdapter.CodexUsage
import Foundation

/// Codex's tokens for one Stats range (increment 3.4b): the chart's series and the figures above it. Days are Codex's
/// own (the local day each turn ended); tokens are Codex's `total_tokens` (input, cached input included, plus output).
struct CodexStats: Equatable {
    let series: TokenSeries
    let from: String
    let to: String
    let total: Int64
    let output: Int64
    let activeDays: Int
    let dayCount: Int
    /// The model with the most tokens in the range, and its share in whole percent.
    let topModel: String?
    let topShare: Int

    static func make(_ days: [CodexUsage.Day], range: StatsSummary.Range, today: String) -> CodexStats? {
        guard let firstEver = days.map(\.day).min() else { return nil }
        let from: String = switch range {
        case .allTime: firstEver
        case .last30: StatsSummary.Day.adding(-29, to: today)
        case .last7: StatsSummary.Day.adding(-6, to: today)
        }
        let inRange = days.filter { $0.day >= from && $0.day <= today }
        var byModel: [String: Int64] = [:], byDate: [String: [String: Int64]] = [:]
        for d in inRange {
            let id = d.model ?? ""
            byModel[id, default: 0] += d.tokens.sum
            byDate[d.day, default: [:]][id, default: 0] += d.tokens.sum
        }
        let ids = byModel.keys.sorted { (byModel[$0]!, $1) > (byModel[$1]!, $0) }
        let total = byModel.values.reduce(0, +)
        return CodexStats(series: TokenSeries(ids: ids, names: ids.map { $0.isEmpty ? Copy.Codex.unknownModel : $0 }, byDate: byDate),
                          from: from, to: today, total: total, output: inRange.reduce(0) { $0 + $1.tokens.output },
                          activeDays: Set(inRange.filter { $0.tokens.sum > 0 }.map(\.day)).count,
                          dayCount: StatsSummary.Day.between(from, today) + 1,
                          topModel: ids.first.map { $0.isEmpty ? Copy.Codex.unknownModel : $0 },
                          topShare: total > 0 ? Int((Double(byModel[ids[0]]!) / Double(total) * 100).rounded()) : 0)
    }
}

extension TokenSeries: Equatable {
    static func == (a: Self, b: Self) -> Bool { a.ids == b.ids && a.names == b.names && a.byDate == b.byDate }
}
