import CalendarDomain
import EventKit
import Foundation

enum EventKitDates {
  static func candidateStart(_ from: Date) -> Date {
    // Native all-day endDate stops one second before our exclusive boundary.
    // Widen retrieval so the final fractional second is still a candidate.
    from.addingTimeInterval(-1)
  }
  static func overlaps(_ event: EKEvent, from: Date, to: Date) -> Bool {
    event.startDate < to && exclusiveEnd(event) > from
  }
  static func exclusiveEnd(_ event: EKEvent) -> Date {
    guard event.isAllDay else { return event.endDate }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = .current
    let midnight = cal.startOfDay(for: event.endDate)
    // EventKit represents an all-day end as the last second of its last day.
    if event.endDate == midnight { return midnight }
    return cal.date(byAdding: .day, value: 1, to: midnight)!
  }
  static func floatingDate(_ date: Date, from zone: TimeZone) -> Date {
    var input = Calendar(identifier: .gregorian)
    input.timeZone = zone
    var native = Calendar(identifier: .gregorian)
    native.timeZone = .current
    return native.date(from: input.dateComponents([.year, .month, .day], from: date))!
  }
  static func apply(_ draft: EventDraft, to event: EKEvent) {
    // Setting timeZone after isAllDay resets isAllDay. Setting dates on an
    // already all-day event also changes exclusive-end semantics.
    event.isAllDay = false
    event.timeZone = draft.allDay ? nil : draft.timezone
    event.startDate = draft.allDay ? floatingDate(draft.start, from: draft.timezone) : draft.start
    event.endDate = draft.allDay ? floatingDate(draft.end, from: draft.timezone) : draft.end
    event.isAllDay = draft.allDay
  }
}
