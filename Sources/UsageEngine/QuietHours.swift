import Foundation

/// Quiet hours (NOTIFICATIONS_AND_SCHEDULING §1.6): a daily span of wall-clock time, stored as minutes of the day and
/// read in the zone the Mac is in when a decision is made, so "22:00 to 07:00" follows the user across zones and
/// daylight-saving changes. A span whose end is before its start crosses midnight. Off by default; switched off, the
/// times are kept for when it is switched on again.
public struct QuietHours: Codable, Sendable, Equatable {
    public var enabled: Bool
    /// Minutes after local midnight, 0..<1440.
    public var start: Int
    public var end: Int

    public static let minutesPerDay = 24 * 60

    public init(enabled: Bool = false, start: Int = 22 * 60, end: Int = 7 * 60) {
        self.enabled = enabled
        self.start = Self.normalized(start)
        self.end = Self.normalized(end)
    }

    public static func normalized(_ minute: Int) -> Int { ((minute % minutesPerDay) + minutesPerDay) % minutesPerDay }

    /// Whether `date` falls inside the span, whether or not the span is switched on. Start counts, end doesn't;
    /// equal start and end is an empty span (never quiet), not a whole day.
    public func covers(_ date: Date, in zone: TimeZone) -> Bool {
        let minute = Self.minuteOfDay(date, in: zone)
        if start == end { return false }
        return start < end ? (start <= minute && minute < end) : (minute >= start || minute < end)
    }

    /// Quiet now: switched on and inside the span.
    public func isActive(at date: Date, in zone: TimeZone) -> Bool { enabled && covers(date, in: zone) }

    /// The first moment after `date` at which the span ends: when the digest of what it held back is due. On a
    /// spring-forward day an end inside the skipped hour is the first moment after it.
    public func end(after date: Date, in zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let components = DateComponents(hour: end / 60, minute: end % 60, second: 0)
        return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime, direction: .forward)
            ?? date.addingTimeInterval(TimeInterval(Self.minutesPerDay * 60))
    }

    static func minuteOfDay(_ date: Date, in zone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
