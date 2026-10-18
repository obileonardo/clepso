import DesignSystem
import Domain
import Foundation
import UsageEngine

/// One-tap Calendar (2.5; NOTIFICATIONS §3.1 "Add once", the `.ics` route). Weekly windows only (DECISIONS B9): the
/// five-hour reset moves with every request. Nothing is created by default: the file is written and handed to
/// Calendar only when the user taps the action, and Calendar asks which calendar to add it to. The action is hidden
/// in Stage A (UX_SPEC "Calendar actions: hidden") unless `AppEnvironment.calendarActions` is on.
///
/// EventKit write-only access (§3.1's first choice on macOS) would add the event without the Calendar dialog, but needs
/// the calendars entitlement under the hardened runtime and a usage string: a release decision (docs/RELEASE.md).
extension AppModel {
    /// The event for a pool's next reset, or nil when it can't have one: not a weekly window, no reported reset, or a
    /// reset already passed.
    public func calendarEvent(for row: PoolRow) -> CalendarFile.Event? {
        guard OverviewProjection.window(of: row.poolKey) == "seven_day", let reset = row.model.resetsAt.value,
              reset > environment.clock.now() else { return nil }
        let agent = row.poolKey.hasPrefix("codex.") ? Copy.Codex.name : "Claude Code"
        let scope = OverviewProjection.scope(of: row.poolKey)
        // One UID per reset instant: adding the same reset twice updates the event; a moved reset is a new one-shot event.
        return CalendarFile.Event(uid: "\(row.poolKey).\(Int64(reset.timeIntervalSince1970))@\(Product.name.lowercased())",
                                  start: reset, duration: 15 * 60, summary: Copy.CalendarAction.summary(agent, scope),
                                  notes: Copy.CalendarAction.notes(agent), alarm: true)
    }

    /// Writes this reset's `.ics` and opens it in Calendar. Returns the file, or nil when there is no event to add or
    /// the file couldn't be written.
    @discardableResult
    public func addResetToCalendar(_ row: PoolRow) -> URL? {
        guard let event = calendarEvent(for: row) else { return nil }
        let folder = environment.calendarDirectory
        let file = folder.appendingPathComponent(Copy.CalendarAction.fileName(event.summary))
        let text = CalendarFile.calendar([event], stamp: environment.clock.now(), product: Product.name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file, options: .atomic)
        } catch {
            return nil
        }
        environment.openFile(file)
        return file
    }
}
