import CryptoKit
import Domain
import Foundation
import ShimProtocol

/// Everything one frame contributes: observations plus the session facts the store keeps on the
/// `Session` row (DATA_MODEL §5.1).
public struct IngestBatch: Sendable, Equatable {
    public let sessionRef: String?
    public let modelID: String?
    public let modelDisplayName: String?
    public let sourceVersion: String?
    public let observedAt: Date
    public let receivedAt: Date
    public let observations: [IncomingObservation]
    /// Session observations dropped because the frame had no `session_ref`.
    public let droppedSessionObservations: Int
    /// `receivedAt − observedAt`; beyond `FrameMapper.skewLimit` the connector is flagged (§8 rule 8).
    public let clockSkew: TimeInterval
    public var skewFlagged: Bool { abs(clockSkew) > FrameMapper.skewLimit }
    public let scrubCount: Int
    public let unknownTopLevelKeys: Int
    /// Limit windows under `rate_limits` the helper does not read (DECISIONS C7): a count, never names or values.
    public var unknownRateLimitWindows: Int = 0
}

/// Frame v1 → observations, exactly per DATA_MODEL §5.1. Pure: no I/O, no clock read.
public enum FrameMapper {
    public static let skewLimit: TimeInterval = 5 * 60
    static let windows = ["five_hour", "seven_day"]

    /// Returns nil for a frame without `emitted_at_ms`, which the codec should already have prevented.
    public static func map(_ frame: JSONValue, connectionID: UUID, receivedAt: Date) -> IngestBatch? {
        guard case .value(.number(let emittedMs)) = frame.lookup(["emitted_at_ms"]) else { return nil }
        let observedAt = Date(timeIntervalSince1970: emittedMs / 1000)
        let sessionRef = string(frame.lookup(["session_ref"]))
        let modelID = string(frame.lookup(["model", "id"]))
        let sourceVersion = string(frame.lookup(["source_version"]))

        var observations: [IncomingObservation] = []
        var dropped = 0

        func emit(_ subject: SubjectKey, _ kind: MetricKind, _ value: MetricValue) {
            if case .session = subject, sessionRef == nil { dropped += 1; return }
            let quality: Quality
            switch value {
            case .absent: quality = .unknown
            case .usd: quality = .estimated
            default: quality = .reported
            }
            let observedMs = Int64(emittedMs.rounded())
            let fingerprint = [connectionID.uuidString, subject.canonical, kind.rawValue, value.canonical,
                               String(observedMs), sourceVersion ?? "-"].joined(separator: "|")
            observations.append(IncomingObservation(
                subject: subject, sessionRef: sessionRef, modelID: modelID, kind: kind, value: value,
                observedAt: observedAt, receivedAt: receivedAt, evidence: .officialLocalTelemetry, quality: quality,
                sourceVersion: sourceVersion, dedupeKey: sha256(fingerprint)))
        }

        // Pools: five_hour and seven_day always produce an observation, absent when not reported.
        for window in windows {
            let pool = SubjectKey.pool(providerPoolKey: "claude-code.rate_limits.\(window)")
            let present = frame.lookup(["rate_limits", window])
            if case .value(.object) = present {
                emit(pool, .quotaUsedPct, percent(frame.lookup(["rate_limits", window, "used_pct"])) ?? .absent(.providerOmitted))
                emit(pool, .resetAt, instant(frame.lookup(["rate_limits", window, "resets_at"])) ?? .absent(.providerOmitted))
            } else {
                emit(pool, .quotaUsedPct, .absent(.providerOmitted))
                emit(pool, .resetAt, .absent(.providerOmitted))
            }
        }
        // Gateway spend limit: only when present.
        if case .value(.object) = frame.lookup(["rate_limits", "spend_limit"]) {
            let pool = SubjectKey.pool(providerPoolKey: "claude-code.rate_limits.spend_limit")
            emit(pool, .quotaUsedPct, percent(frame.lookup(["rate_limits", "spend_limit", "used_pct"])) ?? .absent(.providerOmitted))
            emit(pool, .resetAt, instant(frame.lookup(["rate_limits", "spend_limit", "resets_at"])) ?? .absent(.providerOmitted))
        }

        // Session: only what the frame carries.
        let session = SubjectKey.session(sessionRef: sessionRef ?? "")
        if let v = percent(frame.lookup(["context", "used_pct"])) { emit(session, .contextUsedPct, v) }
        if let v = tokens(frame.lookup(["context", "total_input_tokens"])) { emit(session, .contextTokens, v) }
        if let v = tokens(frame.lookup(["context", "window_size"])) { emit(session, .contextWindowSize, v) }
        let usageMembers: [(String, MetricKind)] = [("input_tokens", .requestInputTokens), ("output_tokens", .requestOutputTokens),
                                                    ("cache_read_input_tokens", .cacheReadTokens),
                                                    ("cache_creation_input_tokens", .cacheCreationTokens)]
        switch frame.lookup(["context", "current_usage"]) {
        case .null:
            for (_, kind) in usageMembers { emit(session, kind, .absent(.providerNull)) }
        case .value(.object):
            for (member, kind) in usageMembers {
                if let v = tokens(frame.lookup(["context", "current_usage", member])) { emit(session, kind, v) }
            }
        default:
            break
        }
        if let v = usd(frame.lookup(["cost_usd_estimate"])) { emit(session, .apiCostUSD, v) }

        // Increment 1.7: the session detail. Each row only when the frame carries the field.
        if let v = tokens(frame.lookup(["context", "total_output_tokens"])) { emit(session, .sessionOutputTokens, v) }
        if let v = integer(frame.lookup(["activity", "wall_ms"]), as: { .duration(milliseconds: $0) }) { emit(session, .wallDuration, v) }
        if let v = integer(frame.lookup(["activity", "api_ms"]), as: { .duration(milliseconds: $0) }) { emit(session, .apiDuration, v) }
        if let v = integer(frame.lookup(["activity", "lines_added"]), as: MetricValue.count) { emit(session, .linesAdded, v) }
        if let v = integer(frame.lookup(["activity", "lines_removed"]), as: MetricValue.count) { emit(session, .linesRemoved, v) }
        if let v = ratioPercent(frame.lookup(["prompt_cache", "hit_ratio"])) { emit(session, .cacheHitPct, v) }
        if let v = integer(frame.lookup(["prompt_cache", "requests"]), as: MetricValue.count) { emit(session, .cacheRequests, v) }
        if let v = integer(frame.lookup(["prompt_cache", "misses"]), as: MetricValue.count) { emit(session, .cacheMisses, v) }
        if let v = flag(frame.lookup(["prompt_cache", "warm"])) { emit(session, .cacheWarm, v) }

        func count(_ key: String) -> Int {
            if case .value(.number(let n)) = frame.lookup(["health", key]) { return Int(n) }
            return 0
        }
        return IngestBatch(sessionRef: sessionRef, modelID: modelID,
                           modelDisplayName: string(frame.lookup(["model", "display_name"])), sourceVersion: sourceVersion,
                           observedAt: observedAt, receivedAt: receivedAt, observations: observations,
                           droppedSessionObservations: dropped, clockSkew: receivedAt.timeIntervalSince(observedAt),
                           scrubCount: count("scrub_count"), unknownTopLevelKeys: count("unknown_top_level_keys"),
                           unknownRateLimitWindows: count("unknown_rate_limit_windows"))
    }

    // MARK: - Value rules (§5.1): number → value, null → providerNull, missing → nil (row decides)

    static func percent(_ p: FieldPresence) -> MetricValue? {
        switch p {
        case .absent: nil
        case .null: .absent(.providerNull)
        case .value(.number(let n)): decimal(n).map(MetricValue.percent) ?? .absent(.rejectedBySanitizer)
        case .value: .absent(.rejectedBySanitizer)
        }
    }

    static func usd(_ p: FieldPresence) -> MetricValue? {
        switch p {
        case .absent: nil
        case .null: .absent(.providerNull)
        case .value(.number(let n)): decimal(n).map(MetricValue.usd) ?? .absent(.rejectedBySanitizer)
        case .value: .absent(.rejectedBySanitizer)
        }
    }

    static func tokens(_ p: FieldPresence) -> MetricValue? {
        switch p {
        case .absent: nil
        case .null: .absent(.providerNull)
        case .value(.number(let n)) where n.rounded() == n && abs(n) < 9.2e18: .tokens(Int64(n))
        case .value: .absent(.rejectedBySanitizer)
        }
    }

    /// A non-negative integer wrapped as the row's value kind.
    static func integer(_ p: FieldPresence, as wrap: (Int64) -> MetricValue) -> MetricValue? {
        switch p {
        case .absent: nil
        case .null: .absent(.providerNull)
        case .value(.number(let n)) where n.rounded() == n && n >= 0 && n < 9.2e18: wrap(Int64(n))
        case .value: .absent(.rejectedBySanitizer)
        }
    }

    /// A 0…1 ratio stored as a percent, multiplied exactly in decimal (0.73 → 73, never 73.00000000000001).
    static func ratioPercent(_ p: FieldPresence) -> MetricValue? {
        switch p {
        case .absent: nil
        case .null: .absent(.providerNull)
        case .value(.number(let n)) where (0...1).contains(n): decimal(n).map { .percent($0 * 100) } ?? .absent(.rejectedBySanitizer)
        case .value: .absent(.rejectedBySanitizer)
        }
    }

    static func flag(_ p: FieldPresence) -> MetricValue? {
        switch p {
        case .absent: nil
        case .null: .absent(.providerNull)
        case .value(.bool(let b)): .flag(b)
        case .value: .absent(.rejectedBySanitizer)
        }
    }

    static func instant(_ p: FieldPresence) -> MetricValue? {
        switch p {
        case .absent: nil
        case .null: .absent(.providerNull)
        case .value(.number(let seconds)): .instant(Date(timeIntervalSince1970: seconds))
        case .value: .absent(.rejectedBySanitizer)
        }
    }

    static func string(_ p: FieldPresence) -> String? {
        if case .value(.string(let s)) = p { return s }
        return nil
    }

    /// Through the shortest decimal text of the double, so 0.0412 stays 0.0412 rather than 0.04120000000000000512.
    static func decimal(_ n: Double) -> Decimal? {
        guard n.isFinite else { return nil }
        return Decimal(string: "\(n)", locale: Locale(identifier: "en_US_POSIX"))
    }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
