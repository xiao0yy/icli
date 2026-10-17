import CalendarDomain
import EventKit
import XCTest

@testable import EventKitCalendar

final class AdvancedTests: XCTestCase {
  func testAlertsReplaceClearAndValidate() throws {
    XCTAssertNil(try AlertInput.parse([], noAlert: false))
    XCTAssertEqual(try AlertInput.parse([], noAlert: true), [])
    XCTAssertEqual(
      try AlertInput.parse(["15m", "1h", "15m", "0"], noAlert: false), [-3600, -900, 0])
    XCTAssertThrowsError(try AlertInput.parse(["15m"], noAlert: true))
    XCTAssertThrowsError(try AlertInput.parse(["-5m"], noAlert: false))
    XCTAssertThrowsError(try AlertInput.parse(["366d"], noAlert: false))
    let a = EKAlarm(relativeOffset: -900)
    XCTAssertEqual(EventKitDates.alarmInfo(a).relativeSeconds, -900)
    let absolute = EKAlarm(absoluteDate: Date(timeIntervalSince1970: 0))
    XCTAssertNotNil(EventKitDates.alarmInfo(absolute).absoluteDate)
    XCTAssertNil(EventKitDates.alarmInfo(absolute).relativeSeconds)
  }
  func testRecurrenceConfigurationAndNativeMapping() throws {
    let zone = try EventTime.zone("Asia/Shanghai")
    let start = try EventTime.day("2026-10-14", zone: zone)
    let spec = try XCTUnwrap(
      RecurrenceSpec.parse(
        frequency: "weekly", interval: 2, days: "mon,wed,mon", until: nil, count: 4, timezone: zone)
    )
    try spec.validate(start: start)
    XCTAssertEqual(spec.weekdays, [2, 4])
    let rule = try EventKitDates.rule(spec, start: start)
    XCTAssertEqual(rule.frequency, .weekly)
    XCTAssertEqual(rule.interval, 2)
    XCTAssertEqual(rule.recurrenceEnd?.occurrenceCount, 4)
    XCTAssertEqual(EventKitDates.ruleInfo(rule).weekdays, [2, 4])
    XCTAssertEqual(EventKitDates.ruleInfo(rule).count, 4)
    XCTAssertThrowsError(
      try EventKitDates.rule(
        RecurrenceSpec(frequency: "weekly", weekdays: [2], timezone: zone), start: start))
    for frequency in ["daily", "monthly", "yearly"] {
      XCTAssertNoThrow(try EventKitDates.rule(RecurrenceSpec(frequency: frequency), start: start))
    }
    XCTAssertThrowsError(
      try RecurrenceSpec(frequency: "weekly", interval: 0).validate(start: start))
    XCTAssertThrowsError(
      try RecurrenceSpec(frequency: "daily", weekdays: [2]).validate(start: start))
    XCTAssertThrowsError(
      try RecurrenceSpec(frequency: "daily", until: start, count: 2).validate(start: start))
    XCTAssertThrowsError(try RecurrenceSpec(frequency: "daily", count: 0).validate(start: start))
    XCTAssertThrowsError(
      try RecurrenceSpec.parse(
        frequency: nil, interval: 2, days: nil, until: nil, count: nil, timezone: zone))
    XCTAssertThrowsError(
      try RecurrenceSpec.parse(
        frequency: "weekly", interval: nil, days: "mon,", until: nil, count: nil, timezone: zone))
  }
  func testInclusiveRecurrenceEndUsesCalendarDayAcrossDST() throws {
    let zone = try EventTime.zone("America/New_York")
    let spec = try XCTUnwrap(
      RecurrenceSpec.parse(
        frequency: "daily", interval: nil, days: nil, until: "2026-03-08", count: nil,
        timezone: zone))
    XCTAssertEqual(spec.until, try EventTime.day("2026-03-09", zone: zone).addingTimeInterval(-1))
  }
  func testScopesAreExplicitAndRuleChangeCannotDetachOne() throws {
    XCTAssertThrowsError(try ScopePolicy.resolve(recurring: true, scope: nil))
    XCTAssertEqual(try ScopePolicy.resolve(recurring: true, scope: .this), .this)
    XCTAssertEqual(try ScopePolicy.resolve(recurring: true, scope: .future), .future)
    XCTAssertEqual(try ScopePolicy.resolve(recurring: true, scope: .all), .all)
    XCTAssertThrowsError(try ScopePolicy.resolve(recurring: true, scope: .this, changingRule: true))
    XCTAssertThrowsError(try ScopePolicy.resolve(recurring: false, scope: .all))
    XCTAssertEqual(try ScopePolicy.resolve(recurring: false, scope: nil), .this)
  }
  func testAlarmOnlyAndRuleOnlyPatchesAreValid() throws {
    XCTAssertNoThrow(try EventPatch(alerts: []).validate())
    XCTAssertNoThrow(try EventPatch(recurrence: RecurrenceSpec(frequency: "daily")).validate())
    XCTAssertNoThrow(try EventPatch(clearRecurrence: true).validate())
    XCTAssertThrowsError(
      try EventPatch(recurrence: RecurrenceSpec(frequency: "daily"), clearRecurrence: true)
        .validate())
  }
  func testCalendarColor() throws {
    let (r, g, b) = try CalendarColor.components("#FF8000")
    XCTAssertEqual(r, 1)
    XCTAssertEqual(g, 128.0 / 255)
    XCTAssertEqual(b, 0)
    XCTAssertThrowsError(try CalendarColor.components("FF8000"))
    XCTAssertThrowsError(try CalendarColor.components("#GG8000"))
  }
  func testAttendeeAndOrganizerFiltering() throws {
    let alice = ParticipantInfo(
      name: "Alice", email: "alice@example.com", url: "mailto:alice@example.com")
    let bob = ParticipantInfo(name: "Bob", email: "bob@example.com", url: "mailto:bob@example.com")
    let one = EventInfo(
      id: "1", calendarID: "a", title: "One", start: "2026-10-14", end: "2026-10-15", allDay: true,
      timezone: nil, location: nil, notes: nil, recurring: false, writable: false,
      attendees: [alice])
    let two = EventInfo(
      id: "2", calendarID: "b", title: "Two", start: "2026-10-14", end: "2026-10-15", allDay: true,
      timezone: nil, location: nil, notes: nil, recurring: false, writable: false, organizer: bob)
    XCTAssertEqual(try EventQuery.apply([one, two], attendees: ["ALICE"]).map(\.id), ["1"])
    XCTAssertEqual(try EventQuery.apply([one, two], attendees: ["bob@example"]).map(\.id), ["2"])
    XCTAssertEqual(
      try EventQuery.apply([one, two], attendees: ["Alice", "Bob"]).map(\.id), ["1", "2"])
    XCTAssertEqual(
      try EventQuery.apply([one, two], excluded: ["a"], attendees: ["Alice", "Bob"]).map(\.id),
      ["2"])
    XCTAssertThrowsError(try EventQuery.apply([], attendees: [" "]))
  }
}
