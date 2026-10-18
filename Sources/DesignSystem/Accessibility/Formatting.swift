import Domain
import Foundation

/// Text for numbers and times. Time zone and locale are passed in, so the same instant always renders
/// the same way for a given setting, and changing zones changes text only (fixture F16).
public enum Formatting {
    public static func percent(_ value: Decimal) -> String {
        var rounded = Decimal(), copy = value
        NSDecimalRound(&rounded, &copy, value.isInteger ? 0 : 1, .plain)
        return "\(rounded)%"
    }

    public static func tokens(_ value: Int64, locale: Locale) -> String {
        value.formatted(.number.locale(locale))
    }

    /// "just now", "4m ago", then clock time within 24 hours, then the date.
    public static func age(of date: Date, now: Date, zone: TimeZone, locale: Locale) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400 { return clock(date, zone: zone, locale: locale) }
        return format(date, template: "MMMd", zone: zone, locale: locale)
    }

    /// The same age read aloud: "1 minute ago", "42 minutes ago".
    public static func spokenAge(of date: Date, now: Date, zone: TimeZone, locale: Locale) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { let m = Int(seconds / 60); return m == 1 ? "1 minute ago" : "\(m) minutes ago" }
        return "at " + clock(date, zone: zone, locale: locale)
    }

    /// "8:30 AM" or "08:30": the locale's own hour cycle (`j`), so the Mac's 12/24-hour setting is honoured.
    public static func clock(_ date: Date, zone: TimeZone, locale: Locale) -> String { format(date, template: "jmm", zone: zone, locale: locale) }

    /// A reset time: clock time today, weekday and time within a week, the date beyond.
    public static func resetTime(_ date: Date, now: Date, zone: TimeZone, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        if calendar.isDate(date, inSameDayAs: now) { return clock(date, zone: zone, locale: locale) }
        if date.timeIntervalSince(now) < 6 * 86_400 { return format(date, template: "EEEjmm", zone: zone, locale: locale) }
        return format(date, template: "MMMd", zone: zone, locale: locale)
    }

    /// "16.5B", "27.7M", "193.2K", "940" (increment 1.7): how /stats writes token counts.
    public static func compact(_ value: Int64) -> String {
        let n = Double(value), units: [(Double, String)] = [(1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")]
        for (size, unit) in units where abs(n) >= size {
            let scaled = (n / size * 10).rounded() / 10
            return (scaled == scaled.rounded() ? String(Int(scaled)) : String(format: "%.1f", scaled)) + unit
        }
        return String(value)
    }

    /// "7d 19h 35m", "2h 0m", "4m 12s", "38s": elapsed time as Claude Code's /stats and /usage write it.
    public static func duration(milliseconds ms: Int64) -> String {
        let s = max(0, ms / 1000), d = s / 86_400, h = s % 86_400 / 3600, m = s % 3600 / 60, sec = s % 60
        if d > 0 { return "\(d)d \(h)h \(m)m" }
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(sec)s" }
        return "\(sec)s"
    }

    /// "in 2h 15m", "in 3 days"; nil once the time has passed.
    public static func countdown(to date: Date, now: Date) -> String? {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "in \(max(minutes, 1))m" }
        if minutes < 48 * 60 { return "in \(minutes / 60)h \(minutes % 60)m" }
        return "in \(minutes / 1440) days"
    }

    /// Formats from a skeleton (`jmm`, `EEEjmm`, `MMMd`): the locale picks order, separators and hour cycle, so a
    /// British Mac reads "Sun 01:30" and "1 Nov" where an American one reads "Sun 1:30 AM" and "Nov 1". ICU puts a
    /// narrow no-break space before AM/PM; it becomes a plain space, as the fixed patterns wrote it, so notification
    /// bodies, VoiceOver sentences and Diagnostics stay plain text.
    static func format(_ date: Date, template: String, zone: TimeZone, locale: Locale) -> String {
        DateFormatterCache.shared.string(from: date, template: template, zone: zone, locale: locale)
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }
}

/// One `DateFormatter` per skeleton, zone and locale (item 8, popover open speed). Making one costs about a millisecond
/// (ICU builds the locale's pattern generator and symbols), and a popover render formats a dozen times; profiling the
/// first open after launch showed ICU formatter construction on the main thread. A formatter's pattern is fixed when it
/// is made, so the key holds everything the pattern depends on (the locale's identifier and hour cycle: the Mac's 12/24-
/// hour setting), each formatter keeps a fixed copy of the zone, and the cache empties when the system locale changes.
/// Formatting happens under the lock, so a formatter is never used from two threads at once.
final class DateFormatterCache: @unchecked Sendable {
    static let shared = DateFormatterCache()

    struct Key: Hashable {
        let template: String
        let zone: String
        let locale: String
        let hourCycle: Locale.HourCycle
    }

    private let lock = NSLock()
    private var formatters: [Key: DateFormatter] = [:]
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: nil) {
            [weak self] _ in self?.removeAll()
        }
    }

    func string(from date: Date, template: String, zone: TimeZone, locale: Locale) -> String {
        lock.withLock { formatterLocked(template: template, zone: zone, locale: locale).string(from: date) }
    }

    /// The cached formatter itself, for tests (identity).
    func formatter(template: String, zone: TimeZone, locale: Locale) -> DateFormatter {
        lock.withLock { formatterLocked(template: template, zone: zone, locale: locale) }
    }

    func removeAll() { lock.withLock { formatters.removeAll() } }

    private func formatterLocked(template: String, zone: TimeZone, locale: Locale) -> DateFormatter {
        let key = Key(template: template, zone: zone.identifier, locale: locale.identifier, hourCycle: locale.hourCycle)
        if let formatter = formatters[key] { return formatter }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: zone.identifier) ?? zone     // fixed: an autoupdating zone would drift from the key
        formatter.setLocalizedDateFormatFromTemplate(template)
        formatters[key] = formatter
        return formatter
    }
}

extension Decimal {
    var isInteger: Bool {
        var rounded = Decimal(), copy = self
        NSDecimalRound(&rounded, &copy, 0, .plain)
        return rounded == self
    }
}

/// VoiceOver sentences in the UX spec's order: scope, value, source, freshness, status.
public enum AccessibilityText {
    public static func poolRow(_ model: PoolCardModel, now: Date, staleAfter: TimeInterval, zone: TimeZone, locale: Locale,
                               isDemo: Bool = false) -> String {
        let state = model.valueState(now: now, staleAfter: staleAfter)
        let value: String = switch (state, model.used.value) {
        case (.live, let v?), (.stale, let v?): "\(Formatting.percent(v).dropLast()) percent used"
        default: StatusStyles.of(state).accessibility
        }
        var parts = [model.scope, value, model.source.isEnteredByUser ? "entered by you" : model.source.displayName]
        if let at = model.used.observedAt ?? model.resetsAt.observedAt {
            let age = Formatting.spokenAge(of: at, now: now, zone: zone, locale: locale)
            parts.append(state == .stale ? "last seen \(age)" : age)
        }
        if model.card != .available || state == .live || state == .stale { parts.append(StatusStyles.of(model.card).accessibility) }
        if let reset = model.resetsAt.value, model.card != .resetExpected {
            parts.append("resets \(Formatting.resetTime(reset, now: now, zone: zone, locale: locale))")
        }
        let sentence = parts.joined(separator: ", ")
        return isDemo ? "Demo data, " + sentence : sentence
    }
}
