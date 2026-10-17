import Foundation

/// One stored usage reading for charts and the pace estimate.
public struct UsagePoint: Sendable, Equatable, Codable {
    public let at: Date
    public let usedPct: Double
    public init(at: Date, usedPct: Double) {
        self.at = at
        self.usedPct = usedPct
    }
}

/// "At this pace…" (increment 1.7c). Always presented as an estimate: it extrapolates a straight line through recent
/// readings in the current window and knows nothing about what the user will do next. Pure; the clock is passed in.
public enum PaceEstimate: Sendable, Equatable {
    case reachesLimit(at: Date)               // the line crosses 100% before the reported reset (or no reset is known)
    case belowAtReset(projectedPct: Double)   // the window resets first; roughly this much used by then
    case notRising                            // flat or falling: no estimate to give
    case notEnoughData                        // fewer than `minPoints` readings, or spanning less than `minSpan`
    case atLimit                              // already at or above 100%

    public static let minPoints = 3
    public static let minSpan: TimeInterval = 10 * 60
    /// Below this slope (percentage points per hour) usage is treated as flat.
    public static let flatSlope = 0.5
    /// The estimate never looks further ahead than this many times the history it rests on (an hour of readings
    /// cannot speak for the next two days).
    public static let maxLookAhead = 8.0

    /// `points` in any order; only those after `windowOpenedAt` and within `lookback` of `now` count, so a reset
    /// inside the period never bends the line.
    public static func estimate(_ points: [UsagePoint], windowOpenedAt: Date?, resetsAt: Date?, now: Date,
                                lookback: TimeInterval) -> PaceEstimate {
        let from = max(windowOpenedAt ?? .distantPast, now.addingTimeInterval(-lookback))
        let recent = points.filter { $0.at >= from && $0.at <= now }.sorted { $0.at < $1.at }
        guard let latest = recent.last else { return .notEnoughData }
        if latest.usedPct >= 100 { return .atLimit }
        guard recent.count >= minPoints, let first = recent.first, latest.at.timeIntervalSince(first.at) >= minSpan else { return .notEnoughData }

        // Least squares on (hours since first, percent).
        let xs = recent.map { $0.at.timeIntervalSince(first.at) / 3600 }, ys = recent.map(\.usedPct)
        let n = Double(recent.count), meanX = xs.reduce(0, +) / n, meanY = ys.reduce(0, +) / n
        let sxx = zip(xs, xs).map { ($0 - meanX) * ($1 - meanX) }.reduce(0, +)
        guard sxx > 0 else { return .notEnoughData }
        let slope = zip(xs, ys).map { ($0 - meanX) * ($1 - meanY) }.reduce(0, +) / sxx      // points per hour
        guard slope > flatSlope else { return .notRising }

        let hoursToLimit = (100 - latest.usedPct) / slope
        let hit = latest.at.addingTimeInterval(hoursToLimit * 3600)
        let span = latest.at.timeIntervalSince(first.at)
        let horizon = min(hit, resetsAt.flatMap { $0 > now ? $0 : nil } ?? hit).timeIntervalSince(latest.at)
        guard horizon <= span * maxLookAhead else { return .notEnoughData }
        if let resetsAt, resetsAt > now, hit >= resetsAt {
            let projected = latest.usedPct + slope * resetsAt.timeIntervalSince(latest.at) / 3600
            return .belowAtReset(projectedPct: min(projected, 100))
        }
        return .reachesLimit(at: hit)
    }
}
