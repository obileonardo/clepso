import DesignSystem
import Domain
import Foundation

/// A stored choice. Rotating reads each configured agent's two windows; pinning never silently substitutes another.
public enum MenuBarDisplay: String, Codable, CaseIterable, Sendable {
    case rotating, summary, claudeFiveHour, claudeSevenDay, codexFiveHour, codexSevenDay

    public var title: String {
        switch self {
        case .rotating: "Rotate all limits"
        case .summary: "Most pressing limit"
        case .claudeFiveHour: "Claude · 5-hour"
        case .claudeSevenDay: "Claude · 7-day"
        case .codexFiveHour: "Codex · 5-hour"
        case .codexSevenDay: "Codex · 7-day"
        }
    }

    var poolKey: String? {
        switch self {
        case .rotating, .summary: nil
        case .claudeFiveHour: "claude-code.rate_limits.five_hour"
        case .claudeSevenDay: "claude-code.rate_limits.seven_day"
        case .codexFiveHour: "codex.rate_limits.five_hour"
        case .codexSevenDay: "codex.rate_limits.seven_day"
        }
    }
}

/// A single, explicitly attributed frame. Percentages are used %, never remaining %.
public struct MenuBarReadout: Sendable {
    public let poolKey: String
    public let text: String
    public let shape: MenuBarIcon.Shape
    public let staleMark: Bool
    public let detail: String
    let enabled: Bool
    /// Severe states lead the rotation, without hiding the other windows indefinitely.
    let priority: Int

    static let rotationInterval: TimeInterval = 6

    static func make(poolKey: String, row: PoolRow?, enabled: Bool, waiting: Bool,
                     demo: Bool, now: Date, staleAfter: TimeInterval, zone: TimeZone, locale: Locale) -> Self {
        let claude = poolKey.hasPrefix("claude-code.")
        let agent = claude ? "Claude" : "Codex"
        let window = poolKey.hasSuffix("five_hour") ? "5h" : "7d"
        let scope = "\(claude ? "Claude Code" : "Codex") \(window == "5h" ? "5-hour" : "7-day")"
        let prefix = "\(demo ? "DEMO " : "")\(agent) \(window)"
        func frame(_ value: String, _ shape: MenuBarIcon.Shape, _ explanation: String,
                   stale: Bool = false, priority: Int = 0) -> Self {
            Self(poolKey: poolKey, text: "\(prefix) \(value)", shape: demo ? .demo : shape,
                 staleMark: !demo && stale, detail: "\(demo ? "Demo data. " : "")\(scope): \(explanation)",
                 enabled: enabled && shape != .notConnected, priority: priority)
        }
        guard enabled else { return frame("OFF", .notConnected, "not connected") }
        guard let model = row?.model else {
            return frame(waiting ? "WAIT" : "N/A", waiting ? .waiting : .stale,
                         waiting ? "waiting for the first reading" : "not reported by this agent")
        }
        let state = model.valueState(now: now, staleAfter: staleAfter)
        let stale = state == .stale
        let age = model.used.observedAt.map { Formatting.age(of: $0, now: now, zone: zone, locale: locale) } ?? "age unknown"
        let reset = model.resetsAt.value.map { " · reset expected \(Formatting.resetTime($0, now: now, zone: zone, locale: locale))" } ?? " · reset time not reported"
        if state == .notConnected { return frame("OFF", .notConnected, "not connected") }
        if state == .providerError { return frame("ERROR", .stale, "reading could not be validated") }
        guard let used = model.used.value else {
            return frame(state == .notReportedYet ? "WAIT" : "N/A", state == .notReportedYet ? .waiting : .stale,
                         state == .notReportedYet ? "waiting for the first reading" : "not reported by this agent")
        }
        let percent = Formatting.percent(used)
        if model.card == .resetExpected {
            return frame("RESET?", model.windowReachedLimit ? .flatline : .stale,
                         "reset expected; awaiting a fresh reading · last reported \(percent) used · \(age)" + reset,
                         stale: stale && model.windowReachedLimit, priority: model.windowReachedLimit ? 3 : 0)
        }
        let shape: MenuBarIcon.Shape
        let priority: Int
        switch model.card {
        case .exhausted, .exhaustedNoReset, .exhaustedOverage: shape = .flatline; priority = 3
        case .critical: shape = .approaching; priority = 2
        case .approaching: shape = .approaching; priority = 1
        default: shape = stale ? .stale : .beat; priority = 0
        }
        return frame(percent + (stale ? " OLD" : ""), shape,
                     "\(percent) used\(stale ? ", old reading" : "") · \(age)" + reset,
                     stale: stale && (shape == .flatline || shape == .approaching), priority: priority)
    }
}

extension OverviewSnapshot {
    /// The order is stable while percentages change. A newly exhausted/approaching window gets first place.
    var rotatingReadouts: [MenuBarReadout] {
        menuBarReadouts.filter(\.enabled).sorted {
            $0.priority == $1.priority ? $0.poolKey < $1.poolKey : $0.priority > $1.priority
        }
    }

    func menuBarReadout(display: MenuBarDisplay, tick: Int) -> MenuBarReadout? {
        if let key = display.poolKey { return menuBarReadouts.first { $0.poolKey == key } }
        guard display == .rotating else { return nil }
        let frames = rotatingReadouts
        guard !frames.isEmpty else { return nil }
        return frames[max(0, tick) % frames.count]
    }

    var menuBarHelp: String { ([aggregateLine] + menuBarReadouts.map(\.detail)).joined(separator: "\n") }
}
