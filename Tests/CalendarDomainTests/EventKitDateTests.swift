import CalendarDomain
import EventKit
import XCTest

@testable import EventKitCalendar

final class EventKitDateTests: XCTestCase {
  func testNativeAllDayUsesFloatingDatesAndExclusiveEnd() throws {
    let store = EKEventStore()
    let event = EKEvent(eventStore: store)  // Unsaved object; no access request or store writes.
    let zone = try EventTime.zone("Pacific/Kiritimati")
    let draft = EventDraft(
      calendar: nil, title: "Test", start: try EventTime.day("2026-10-14", zone: zone),
      end: try EventTime.day("2026-10-15", zone: zone), allDay: true, timezone: zone, location: nil,
      notes: nil)
    EventKitDates.apply(draft, to: event)
    XCTAssertTrue(event.isAllDay)
    XCTAssertNil(event.timeZone)
    XCTAssertEqual(EventTime.string(event.startDate, allDay: true, zone: .current), "2026-10-14")
    XCTAssertEqual(
      EventTime.string(EventKitDates.exclusiveEnd(event), allDay: true, zone: .current),
      "2026-10-15")
    EventKitDates.apply(draft, to: event)
    XCTAssertTrue(event.isAllDay)
    XCTAssertEqual(
      EventTime.string(EventKitDates.exclusiveEnd(event), allDay: true, zone: .current),
      "2026-10-15")
  }
  func testTimedDatesPreserveInstantsAndTimezone() throws {
    let store = EKEventStore()
    let event = EKEvent(eventStore: store)
    let start = try EventTime.instant("2026-10-14T10:00:00+08:00", timezone: nil)
    let end = start.addingTimeInterval(3600)
    let zone = try EventTime.zone("America/New_York")
    EventKitDates.apply(
      EventDraft(
        calendar: nil, title: "Test", start: start, end: end, allDay: false,
        timezone: zone, location: nil, notes: nil), to: event)
    XCTAssertFalse(event.isAllDay)
    XCTAssertEqual(event.startDate, start)
    XCTAssertEqual(EventKitDates.exclusiveEnd(event), end)
    XCTAssertEqual(event.timeZone, zone)
  }
}
