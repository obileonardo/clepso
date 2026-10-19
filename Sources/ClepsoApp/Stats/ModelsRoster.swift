import ClaudeCodeAdapter
import DesignSystem
import Foundation

/// The Models page as the founder chose it (19 Oct 2026, docs/design-concepts/models, proposal A "Roster + Dossier"):
/// every model in a ranked roster, one model's dossier at a time, and the level ladder as a track with each model
/// standing at its level. Pure, so the selection rules, the track and every fact the page shows are tested here.
struct ModelsRoster: Equatable {
    /// One kind of token in a model's all-time breakdown.
    struct Kind: Equatable {
        let kind: ModelSpecialty.Kind
        let tokens: Int64
        /// Of this model's all-time tokens, 0…1.
        let fraction: Double
        /// Only output drives the level.
        var countsForLevel: Bool { kind == .output }
    }

    struct Entry: Identifiable, Equatable {
        let share: StatsSummary.ModelShare
        /// The model's place in `StatsSummary.models` (largest first): its colour and pattern, the same in the strip,
        /// the roster, the chart and the track.
        let style: Int
        /// 1-based: by level (output), then output, then tokens (`Copy.Stats.rankRule`).
        let rank: Int
        /// Nil when Claude Code has no tokens-by-kind record for the model: its output, and so its level, are unknown.
        let level: ModelLevel?
        let specialty: ModelSpecialty?
        /// Days in the range on which the model used any tokens.
        let activeDays: Int
        var id: String { share.model }
        var name: String { share.name }

        /// Output first (it is the one that counts for level), then input, cache read, cache write. Nil without a
        /// tokens-by-kind record, or when that record is all zeros.
        var kinds: [Kind]? {
            guard let totals = share.totals, totals.total > 0 else { return nil }
            return ModelsRoster.kindOrder.map { kind in
                Kind(kind: kind, tokens: kind.of(totals), fraction: Double(kind.of(totals)) / Double(totals.total))
            }
        }
    }

    static let kindOrder: [ModelSpecialty.Kind] = [.output, .input, .cacheRead, .cacheWrite]

    let entries: [Entry]
    let total: Int64
    let range: StatsSummary.Range

    init(_ summary: StatsSummary) {
        let party = summary.models.compactMap(\.totals)
        var active: [String: Int] = [:]
        for day in summary.dailyTokens { for (id, n) in day.byModel where n > 0 { active[id, default: 0] += 1 } }
        let ordered = summary.models.enumerated().sorted { a, b in
            let x = (a.element.totals?.output ?? -1, a.element.tokens), y = (b.element.totals?.output ?? -1, b.element.tokens)
            return x != y ? x > y : a.element.model < b.element.model
        }
        entries = ordered.enumerated().map { rank, item in
            Entry(share: item.element, style: item.offset, rank: rank + 1, level: item.element.totals.map { ModelLevel(output: $0.output) },
                  specialty: ModelSpecialty.of(item.element.totals, party: party), activeDays: active[item.element.model] ?? 0)
        }
        total = summary.totalTokens
        range = summary.range
    }

    var isEmpty: Bool { entries.isEmpty }
    /// One model needs no list to choose from: the dossier stands alone.
    var showsRoster: Bool { entries.count > 1 }

    // MARK: Selection

    /// The chosen model: the one asked for while it is still in the range, otherwise #1 (nil when there are none).
    func resolve(_ selected: String?) -> Entry? {
        entries.first { $0.id == selected } ?? entries.first
    }

    /// ↑ (−1) and ↓ (+1): one row from the current choice, held at the ends.
    func step(_ selected: String?, by delta: Int) -> String? {
        guard let current = resolve(selected), let index = entries.firstIndex(of: current) else { return nil }
        return entries[min(max(index + delta, 0), entries.count - 1)].id
    }

    var firstID: String? { entries.first?.id }
    var lastID: String? { entries.last?.id }

    /// Typing a letter: the next model after the current one whose name starts with it, wrapping round.
    func typeSelect(_ prefix: String, after selected: String?) -> String? {
        let prefix = prefix.lowercased()
        guard !prefix.isEmpty, !entries.isEmpty else { return nil }
        let start = resolve(selected).flatMap { entries.firstIndex(of: $0) } ?? -1
        for offset in 1...entries.count {
            let entry = entries[(start + offset) % entries.count]
            if entry.name.lowercased().hasPrefix(prefix) { return entry.id }
        }
        return nil
    }

    // MARK: Roster zones

    /// Duolingo's "promotion zone", for output: the roster is split where output crosses 1K, 1M, 1B… (levels 2, 11,
    /// 20…, the track's big steps). Rows are ranked by output, so each zone is one run of rows; models with no
    /// tokens-by-kind record come last, in a zone of their own (`floorLevel` nil).
    struct Zone: Equatable {
        let floorLevel: Int?
        let entries: [Entry]
    }

    /// 0 below 1K output (level 1), 1 from 1K (level 2), 2 from 1M (level 11), 3 from 1B (level 20)…
    static func zone(of level: Int) -> Int { level <= 1 ? 0 : (level - 2) / 9 + 1 }
    static func zoneFloor(_ zone: Int) -> Int { zone == 0 ? 1 : 2 + (zone - 1) * 9 }

    var zones: [Zone] {
        var zones: [Zone] = []
        for entry in entries {
            let floor = entry.level.map { Self.zoneFloor(Self.zone(of: $0.level)) }
            if let last = zones.last, last.floorLevel == floor {
                zones[zones.count - 1] = Zone(floorLevel: floor, entries: last.entries + [entry])
            } else {
                zones.append(Zone(floorLevel: floor, entries: [entry]))
            }
        }
        return zones
    }

    // MARK: Level track

    /// One cell of the track: a level, the all-time output it starts at, and the models standing on it (in rank order).
    struct Slot: Equatable {
        let level: Int
        let target: Int64
        let models: [Entry]
        /// Which run of 1-2-5 targets it belongs to: 0 for level 1 (no target), then one group per power of ten
        /// (levels 2–4 are 1K, 2K, 5K; 5–7 are 10K, 20K, 50K…).
        var decade: Int { Self.decade(of: level) }
        static func decade(of level: Int) -> Int { level <= 1 ? 0 : (level - 2) / 3 + 1 }
    }

    /// Levels 1 to 20, or one past the highest model when a model has gone beyond 20.
    var trackLength: Int { max(20, (entries.compactMap(\.level?.level).max() ?? 0) + 1) }

    var track: [Slot] {
        (1...trackLength).map { level in
            Slot(level: level, target: Self.target(of: level), models: entries.filter { $0.level?.level == level })
        }
    }

    /// Output needed to stand on `level`: 0 for level 1, then the 1-2-5 ladder.
    static func target(of level: Int) -> Int64 {
        level <= 1 ? 0 : ModelLevel.targets[min(level - 2, ModelLevel.targets.count - 1)]
    }

    /// Models with no tokens-by-kind record: they cannot stand on the track, so the track names them below it.
    var unplaced: [Entry] { entries.filter { $0.level == nil } }

    /// The cell marked NEXT for the selected model.
    func nextLevel(for selected: String?) -> Int? { resolve(selected)?.level.map { $0.level + 1 } }

    // MARK: Activity

    /// The selected model's tokens across the range as one row of cells, oldest first: one cell per day, or per week
    /// when the range is longer than 120 days (as the chart buckets). 0 is no tokens; 1…4 are quarters of the model's
    /// own busiest cell, so a quiet model still shows its rhythm.
    static func activity(_ id: String, summary: StatsSummary, from: String) -> [Int] {
        let byDate = Dictionary(summary.dailyTokens.map { ($0.date, $0.byModel[id] ?? 0) }, uniquingKeysWith: { a, _ in a })
        let days = max(1, StatsSummary.Day.between(from, summary.today) + 1)
        let width = days > 120 ? 7 : 1
        let cells = stride(from: 0, to: days, by: width).map { offset in
            (0..<width).filter { offset + $0 < days }.reduce(Int64(0)) { $0 + (byDate[StatsSummary.Day.adding(offset + $1, to: from)] ?? 0) }
        }
        let top = cells.max() ?? 0
        guard top > 0 else { return cells.map { _ in 0 } }
        return cells.map { $0 == 0 ? 0 : max(1, Int((Double($0) / Double(top) * 4).rounded(.up))) }
    }

    // MARK: Formatting

    /// A share or a kind's part to one decimal everywhere ("75.1%"), so a small model never reads "0%" in one place
    /// and "0.1%" in another; a part too small for one decimal reads "<0.1%", never "0.0%".
    static func percent(_ fraction: Double) -> String {
        let pct = fraction * 100
        if pct > 0 && pct < 0.05 { return "<0.1%" }
        return String(format: "%.1f%%", pct)
    }

    /// The same, as VoiceOver should say it.
    static func spokenPercent(_ fraction: Double) -> String {
        let pct = fraction * 100
        if pct > 0 && pct < 0.05 { return "less than 0.1 percent" }
        return String(format: "%.1f percent", pct)
    }

    /// "12.2B" read as "12.2 billion".
    static func spoken(_ value: Int64) -> String {
        let text = Formatting.compact(value)
        let words: [Character: String] = ["K": " thousand", "M": " million", "B": " billion", "T": " trillion"]
        guard let last = text.last, let word = words[last] else { return text }
        return String(text.dropLast()) + word
    }
}
