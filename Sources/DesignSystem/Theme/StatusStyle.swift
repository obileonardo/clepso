import Foundation

/// Non-colour cue drawn on bars and badges, so states survive greyscale and colour blindness.
public enum FillPattern: String, Sendable, CaseIterable { case solid, hatched, outline, dashed }

/// The single lookup from a state to how it looks and reads. Labels are copy;
/// the founder may change symbols, roles and patterns, never the labels' meaning.
public struct StatusStyle: Sendable, Equatable {
    public let symbol: String                 // SF Symbol
    public let badge: String?                 // secondary SF Symbol when one shape is shared within a family
    public let label: String                  // visible text
    public let accessibility: String          // the {{status}} fragment of the VoiceOver sentence
    public let role: ColorToken
    public let pattern: FillPattern
}

public enum StatusStyles {
    public static func of(_ state: ValueState) -> StatusStyle {
        switch state {
        case .live: StatusStyle(symbol: "dot.radiowaves.left.and.right", badge: nil, label: "Live", accessibility: "live", role: .textSecondary, pattern: .solid)
        case .stale: StatusStyle(symbol: "clock.badge.exclamationmark", badge: nil, label: "Last seen", accessibility: "last seen", role: .statusStale, pattern: .hatched)
        case .notAvailable: StatusStyle(symbol: "minus.circle", badge: nil, label: "Not available", accessibility: "not available", role: .statusUnknown, pattern: .outline)
        case .notReportedYet: StatusStyle(symbol: "ellipsis.circle", badge: nil, label: "Not reported yet", accessibility: "not reported yet", role: .statusUnknown, pattern: .outline)
        case .notConnected: StatusStyle(symbol: "link.badge.plus", badge: nil, label: "Not connected", accessibility: "not connected", role: .statusUnknown, pattern: .dashed)
        case .providerError: StatusStyle(symbol: "exclamationmark.triangle", badge: nil, label: "Couldn't read last update", accessibility: "couldn't read last update", role: .statusBlocked, pattern: .outline)
        }
    }

    public static func of(_ state: CardState) -> StatusStyle {
        switch state {
        case .available: StatusStyle(symbol: "circle", badge: nil, label: "Available", accessibility: "available", role: .statusSuccess, pattern: .solid)
        case .approaching: StatusStyle(symbol: "circle.badge.exclamationmark", badge: nil, label: "Approaching limit", accessibility: "approaching limit", role: .statusAttention, pattern: .solid)
        case .critical: StatusStyle(symbol: "exclamationmark.circle.fill", badge: nil, label: "Nearly exhausted", accessibility: "nearly exhausted", role: .statusAttention, pattern: .solid)
        case .exhausted: StatusStyle(symbol: "nosign", badge: nil, label: "Limit reached", accessibility: "limit reached", role: .statusBlocked, pattern: .solid)
        case .exhaustedNoReset: StatusStyle(symbol: "nosign", badge: "questionmark", label: "Limit reached · reset time not reported", accessibility: "limit reached, reset time not reported", role: .statusBlocked, pattern: .solid)
        case .exhaustedOverage: StatusStyle(symbol: "nosign", badge: "creditcard", label: "Limit reached · paid usage may continue", accessibility: "limit reached, paid usage may continue", role: .statusBlocked, pattern: .solid)
        case .resetExpected: StatusStyle(symbol: "clock.arrow.circlepath", badge: nil, label: "Reset expected · awaiting next update", accessibility: "reset expected, awaiting next update", role: .statusAttention, pattern: .hatched)
        case .availableAgain: StatusStyle(symbol: "checkmark.circle", badge: nil, label: "Available again", accessibility: "available again", role: .statusSuccess, pattern: .solid)
        case .availableAgainUser: StatusStyle(symbol: "checkmark.circle", badge: "person", label: "Available again · you confirmed", accessibility: "available again, you confirmed", role: .statusSuccess, pattern: .solid)
        case .quotaNotAvailable: StatusStyle(symbol: "minus.circle", badge: nil, label: "Account quota not available", accessibility: "account quota not available", role: .statusUnknown, pattern: .outline)
        case .disconnected: StatusStyle(symbol: "bolt.slash", badge: nil, label: "Not connected", accessibility: "not connected", role: .statusUnknown, pattern: .dashed)
        }
    }

    public static func of(_ plan: PlanProvenance) -> StatusStyle {
        switch plan {
        case .providerVerified: StatusStyle(symbol: "checkmark.seal", badge: nil, label: "Provider verified", accessibility: "provider verified", role: .statusSuccess, pattern: .solid)
        case .userConfirmed: StatusStyle(symbol: "person.crop.circle.badge.checkmark", badge: nil, label: "User confirmed", accessibility: "user confirmed", role: .textSecondary, pattern: .solid)
        case .selectedUnverified: StatusStyle(symbol: "person.crop.circle", badge: nil, label: "Selected · not verified", accessibility: "selected, not verified", role: .statusUnknown, pattern: .outline)
        case .notSet: StatusStyle(symbol: "questionmark.circle", badge: nil, label: "Plan not set", accessibility: "plan not set", role: .statusUnknown, pattern: .outline)
        }
    }
}
