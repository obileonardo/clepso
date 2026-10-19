import CryptoKit
import Domain
import Foundation

/// Thresholds and timings. Defaults are the founder-confirmed values.
public struct EngineConfig: Sendable, Equatable {
    public var warning: Decimal = 80
    public var critical: Decimal = 95
    public var exhausted: Decimal = 100
    public var hysteresis: Decimal = 3
    public var materialDrop: Decimal = 5
    public var windowTolerance: TimeInterval = 15 * 60
    public var freshnessTTL: TimeInterval = Freshness.localTelemetryTTL
    /// One source per window (docs/specs/mod-bridge.md §7): a reading from Clepso's mod observed less than this after
    /// the status line's latest reading of the same window is kept as history only.
    public var sourceHoldOff: TimeInterval = 60
    public init() {}
}

/// One provider window instance (DATA_MODEL §6.3). Its id is derived, never random, so a rebuild
/// from the ledger reproduces it exactly.
public struct WindowState: Codable, Sendable, Equatable {
    public let id: UUID
    public let openedAt: Date
    public var resetsAt: Date?
    public var closedAt: Date?
    public var version: Int64

    static func open(poolKey: String, at: Date, resetsAt: Date?) -> WindowState {
        WindowState(id: derivedUUID("window|\(poolKey)|\(Int64((at.timeIntervalSince1970 * 1000).rounded()))"),
                    openedAt: at, resetsAt: resetsAt, closedAt: nil, version: 1)
    }
}

/// Total order for latest-wins (DATA_MODEL §6.1): observed time, then source priority, then arrival.
public struct OrderKey: Codable, Sendable, Equatable, Comparable {
    public let observedAt: Date
    public let priority: Int
    public let receivedAt: Date
    public static func < (a: OrderKey, b: OrderKey) -> Bool {
        (a.observedAt, a.priority, a.receivedAt) < (b.observedAt, b.priority, b.receivedAt)
    }
}

/// Everything the engine knows about one allowance pool. Persisted as `pool_snapshots.snapshot_json`.
public struct PoolState: Codable, Sendable, Equatable {
    public let poolKey: String
    public var limit: LimitState = .unknown
    public var usedPct: Decimal?                 // last measured value, kept while the provider omits it
    public var usedAbsence: AbsenceReason?       // set when nothing was ever measured
    public var lastProviderMeasured: Date?
    public var lastSeen: Date?
    public var omittedSince: Date?
    public var highWater: Decimal?               // within the current window, for crossing detection
    public var window: WindowState?
    public var resetExpectedWindow: UUID?        // G9 emitted once per window
    public var readyAgainWindow: UUID?           // G6 emitted once per window
    public var staleEpisode = false              // G13 emitted once per stale episode
    public var latest: OrderKey?
    /// When the status line (or another adapter, never the mod) last moved this pool: the start of its hold (§7).
    public var lastStatusLineAt: Date?
    public var version: Int64 = 0

    public init(poolKey: String) { self.poolKey = poolKey }
    public var resetsAt: Date? { window?.resetsAt }
}

/// Engine output, stored in `derived_events` and fed to the notification engine (2.1).
public struct EngineEvent: Codable, Sendable, Equatable {
    public let kind: DerivedEventKind
    public let poolKey: String
    public let windowID: UUID?
    public let level: ThresholdLevel?
    public let occurredAt: Date
}

/// One frame's observations for one pool.
public struct PoolUpdate: Sendable {
    public let used: IncomingObservation?
    public let reset: IncomingObservation?
    public init(used: IncomingObservation?, reset: IncomingObservation?) {
        self.used = used
        self.reset = reset
    }
    var anchor: IncomingObservation? { used ?? reset }
}

public struct Reduction: Sendable {
    public let state: PoolState
    public let events: [EngineEvent]
    public let closedWindows: [WindowState]
}

/// Limit and reset state machines, DATA_MODEL §7.1–§7.2. Pure: time is passed in.
public enum PoolReducer {
    public static func reduce(_ input: PoolState, _ update: PoolUpdate, now: Date, overageEvidence: Bool = false,
                              config: EngineConfig = EngineConfig()) -> Reduction {
        guard let anchor = update.anchor else { return Reduction(state: input, events: [], closedWindows: []) }
        let at = anchor.observedAt
        let key = OrderKey(observedAt: at, priority: anchor.evidence.priority, receivedAt: anchor.receivedAt)
        // §6.1: an older sample is history only; it never changes the snapshot.
        if let latest = input.latest, key < latest { return Reduction(state: input, events: [], closedWindows: []) }
        // mod-bridge.md §7: while the status line reports this window, the mod's reading of it (another app's session,
        // as of that session's last reply) is history only, so the two never take turns moving it.
        if anchor.channel == .mod, let held = input.lastStatusLineAt, at.timeIntervalSince(held) < config.sourceHoldOff {
            return Reduction(state: input, events: [], closedWindows: [])
        }

        var events: [EngineEvent] = []
        var closed: [WindowState] = []
        // Step 1: reset expectation as of the observation's own time (no stale event here).
        var s = tick(input, now: at, includeStale: false, config: config, events: &events)
        s.latest = key
        if anchor.channel != .mod { s.lastStatusLineAt = max(s.lastStatusLineAt ?? at, at) }
        s.lastSeen = max(s.lastSeen ?? at, at)
        s.staleEpisode = false                       // any reading ends a silence episode
        let fresh = now.timeIntervalSince(at) < config.freshnessTTL

        let reportedReset: Date? = { if case .instant(let d) = update.reset?.value { return d } else { return nil } }()

        switch update.used?.value {
        case .percent(let used):
            let previous = s.limit
            let previousUsed = s.usedPct
            let oldWindow = s.window

            // G6: the only path to "ready again".
            var ready = false
            if fresh, let window = oldWindow, let resetsAt = window.resetsAt, at > resetsAt,
               previous.isAboveAvailable || previous == .resetExpected,
               let before = previousUsed, before - used >= config.materialDrop || used < config.warning {
                ready = true
            }

            if ready, let window = oldWindow {
                var old = window
                old.closedAt = at
                closed.append(old)
                if s.readyAgainWindow != window.id {
                    events.append(EngineEvent(kind: .readyAgain, poolKey: s.poolKey, windowID: window.id, level: nil, occurredAt: at))
                    s.readyAgainWindow = window.id
                }
                s.window = .open(poolKey: s.poolKey, at: at, resetsAt: reportedReset)
                s.highWater = nil
                events.append(EngineEvent(kind: .windowOpened, poolKey: s.poolKey, windowID: s.window?.id, level: nil, occurredAt: at))
            } else {
                applyReset(reportedReset, to: &s, at: at, closed: &closed, events: &events, config: config)
            }

            // G2–G4: upward crossings of the high-water mark, fresh observations only, never on the first value.
            if fresh, let highWater = s.highWater {
                for (threshold, kind, level) in [(config.warning, DerivedEventKind.thresholdCrossed, ThresholdLevel.warning),
                                                 (config.critical, .thresholdCrossed, .critical),
                                                 (config.exhausted, .exhausted, nil)]
                    where used >= threshold && highWater < threshold {
                    events.append(EngineEvent(kind: kind, poolKey: s.poolKey, windowID: s.window?.id, level: level, occurredAt: at))
                }
            }
            s.highWater = max(s.highWater ?? used, used)

            var next: LimitState
            if ready {
                next = classify(used, previous: .available, config: config)
            } else if (previous == .exhausted || previous == .paidOverage) && used < config.exhausted {
                next = previous                      // 100 → 99 is not a reset; only G6 leaves exhausted
            } else {
                next = classify(used, previous: previous, config: config)
            }
            if next == .exhausted && overageEvidence {    // G5: evidence-gated
                next = .paidOverage
                if previous != .paidOverage && fresh {
                    events.append(EngineEvent(kind: .paidOverageDetected, poolKey: s.poolKey, windowID: s.window?.id, level: nil, occurredAt: at))
                }
            }
            s.limit = next
            s.usedPct = used
            s.usedAbsence = nil
            s.lastProviderMeasured = at
            s.omittedSince = nil

        case .absent(let reason):
            if s.usedPct == nil {
                s.limit = .unknown                   // G11: nothing ever measured
                s.usedAbsence = reason
            } else if s.omittedSince == nil {
                s.omittedSince = at                  // G10: windows are dropped after reset; keep the state
            }

        default:
            if case .instant = update.reset?.value { applyReset(reportedReset, to: &s, at: at, closed: &closed, events: &events, config: config) }
        }

        // Step 3: reset expectation and staleness as of now.
        s = tick(s, now: now, includeStale: true, config: config, events: &events)
        s.version += 1
        return Reduction(state: s, events: events, closedWindows: closed)
    }

    /// Time passing with no new observation: G9 (reset expected) and, when asked, G13 (stale).
    public static func tick(_ state: PoolState, now: Date, config: EngineConfig = EngineConfig()) -> (PoolState, [EngineEvent]) {
        var events: [EngineEvent] = []
        // `version` counts applied observation groups only, so it is a function of the ledger and a
        // rebuild reproduces it; timer ticks change state but not the version.
        let s = tick(state, now: now, includeStale: true, config: config, events: &events)
        return (s, events)
    }

    static func tick(_ input: PoolState, now: Date, includeStale: Bool, config: EngineConfig, events: inout [EngineEvent]) -> PoolState {
        var s = input
        if let window = s.window, let resetsAt = window.resetsAt, now >= resetsAt, s.limit != .unknown,
           s.limit != .resetExpected, (s.lastProviderMeasured ?? .distantPast) <= resetsAt {
            s.limit = .resetExpected
            if s.resetExpectedWindow != window.id {
                events.append(EngineEvent(kind: .resetExpected, poolKey: s.poolKey, windowID: window.id, level: nil, occurredAt: resetsAt))   // stamped with the reset time: deterministic on rebuild
                s.resetExpectedWindow = window.id
            }
        }
        // G13 as an event means the source went silent: nothing has touched this pool for the TTL. A pool
        // whose window the provider omits while frames keep arriving is old (display freshness uses
        // lastProviderMeasured) but its source is alive, so no staleSource event.
        if includeStale, s.lastProviderMeasured != nil, let seen = s.lastSeen, now.timeIntervalSince(seen) >= config.freshnessTTL, !s.staleEpisode {
            events.append(EngineEvent(kind: .staleSource, poolKey: s.poolKey, windowID: s.window?.id, level: nil, occurredAt: now))
            s.staleEpisode = true
        }
        return s
    }

    /// §6.3: open a window, move it in place within tolerance, or replace it beyond tolerance.
    static func applyReset(_ reported: Date?, to s: inout PoolState, at: Date, closed: inout [WindowState],
                           events: inout [EngineEvent], config: EngineConfig) {
        guard var window = s.window else {
            s.window = .open(poolKey: s.poolKey, at: at, resetsAt: reported)
            events.append(EngineEvent(kind: .windowOpened, poolKey: s.poolKey, windowID: s.window?.id, level: nil, occurredAt: at))
            return
        }
        guard let reported else { return }
        if let current = window.resetsAt, abs(reported.timeIntervalSince(current)) > config.windowTolerance {
            window.closedAt = at
            closed.append(window)
            s.window = .open(poolKey: s.poolKey, at: at, resetsAt: reported)
            s.highWater = nil
            events.append(EngineEvent(kind: .windowOpened, poolKey: s.poolKey, windowID: s.window?.id, level: nil, occurredAt: at))
        } else if window.resetsAt != reported {
            window.resetsAt = reported
            window.version += 1
            s.window = window
            events.append(EngineEvent(kind: .windowRescheduled, poolKey: s.poolKey, windowID: window.id, level: nil, occurredAt: at))
        }
    }

    /// Level from a fresh value, with hysteresis t − 3 on the way down (G7, G8).
    static func classify(_ used: Decimal, previous: LimitState, config: EngineConfig) -> LimitState {
        if used >= config.exhausted { return .exhausted }
        if used >= config.critical { return .approaching(.critical) }
        if previous == .approaching(.critical), used > config.critical - config.hysteresis { return .approaching(.critical) }
        if used >= config.warning { return .approaching(.warning) }
        if case .approaching = previous, used > config.warning - config.hysteresis { return .approaching(.warning) }
        return .available
    }
}

extension LimitState {
    var isAboveAvailable: Bool {
        switch self {
        case .approaching, .exhausted, .paidOverage: true
        default: false
        }
    }

    /// Stable text form used in fixtures and the `pool_snapshots.state` column.
    public var label: String {
        switch self {
        case .unknown: "unknown"
        case .available: "available"
        case .approaching(let level): "approaching.\(level.rawValue)"
        case .exhausted: "exhausted"
        case .paidOverage: "paidOverage"
        case .resetExpected: "resetExpected"
        }
    }
}

/// Name-based UUID from SHA-256, so ids derived from the ledger are identical on every rebuild.
public func derivedUUID(_ name: String) -> UUID {
    var bytes = Array(SHA256.hash(data: Data(name.utf8)).prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x50          // version 5 layout, SHA-256 based
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                       bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
}
