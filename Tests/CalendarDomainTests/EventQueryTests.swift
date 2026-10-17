import CalendarDomain
import XCTest

final class EventQueryTests: XCTestCase {
  private func event(
    _ id: String, title: String, calendar: String = "a", recurring: Bool = false,
    location: String? = nil, notes: String? = nil
  ) -> EventInfo {
    EventInfo(
      id: id, calendarID: calendar, title: title, start: "2026-10-14T10:00:00+08:00",
      end: "2026-10-14T11:00:00+08:00", allDay: false, timezone: "Asia/Shanghai",
      location: location, notes: notes, recurring: recurring, writable: !recurring)
  }
  func testSearchMatchesTitleLocationAndNotesIgnoringCaseAndAccents() throws {
    let values = [
      event("1", title: "Café meeting"), event("2", title: "Lunch", location: "CAFE"),
      event("3", title: "Review", notes: "Cafe agenda"), event("4", title: "Other"),
    ]
    XCTAssertEqual(try EventQuery.apply(values, query: "cafe").map(\.id), ["1", "2", "3"])
    XCTAssertEqual(try EventQuery.apply(values, query: "不存在").count, 0)
  }
  func testFilteringAndSortingHappenBeforeLimit() throws {
    let values = [
      event("1", title: "A", calendar: "excluded"), event("2", title: "B", recurring: true),
      event("3", title: "Zulu"), event("4", title: "Alpha"), event("5", title: "Alpha"),
    ]
    let result = try EventQuery.apply(
      values, excluded: ["excluded"], noRecurring: true, sort: "title", limit: 2)
    XCTAssertEqual(result.map(\.id), ["4", "5"])
    XCTAssertEqual(try EventQuery.apply(values, noRecurring: true, limit: 2).map(\.id), ["1", "3"])
  }
  func testQueryValidation() throws {
    XCTAssertThrowsError(try EventQuery.apply([], limit: 0))
    XCTAssertThrowsError(try EventQuery.apply([], sort: "unknown"))
    XCTAssertThrowsError(try EventQuery.apply([], query: "   "))
  }
  func testRelativeBoundariesUseChosenTimezoneAndCalendarDays() throws {
    let now = try EventTime.instant("2026-03-08T12:00:00-04:00", timezone: nil)
    let zone = try EventTime.zone("America/New_York")
    let week = try EventTime.range(
      from: "today", to: nil, timezone: zone.identifier, defaultDays: 7, now: now)
    XCTAssertEqual(week.0, try EventTime.day("2026-03-08", zone: zone))
    XCTAssertEqual(week.1, try EventTime.day("2026-03-15", zone: zone))
    XCTAssertEqual(week.1.timeIntervalSince(week.0), 7 * 86400 - 3600)
    let yesterday = try EventTime.range(
      from: "yesterday", to: "tomorrow", timezone: zone.identifier, now: now)
    XCTAssertEqual(yesterday.0, try EventTime.day("2026-03-07", zone: zone))
    XCTAssertEqual(yesterday.1, try EventTime.day("2026-03-09", zone: zone))
    XCTAssertThrowsError(try EventTime.range(from: nil, to: nil, timezone: nil, defaultDays: 0))
    XCTAssertThrowsError(try EventTime.range(from: nil, to: nil, timezone: nil, defaultDays: 366))
  }
}
