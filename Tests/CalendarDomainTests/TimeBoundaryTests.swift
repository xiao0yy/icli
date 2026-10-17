import CalendarDomain
import EventKit
import Foundation
import XCTest

@testable import EventKitCalendar

final class TimeBoundaryTests: XCTestCase {
  func testFractionalRangeSurvivesFormattingAndParsing() throws {
    let start = try EventTime.instant("2026-10-14T10:00:00.100Z", timezone: nil)
    let end = try EventTime.instant("2026-10-14T10:00:00.900Z", timezone: nil)
    let zone = TimeZone(secondsFromGMT: 0)!
    let encodedStart = EventTime.string(start, allDay: false, zone: zone)
    let encodedEnd = EventTime.string(end, allDay: false, zone: zone)
    let decodedStart = try EventTime.instant(encodedStart, timezone: nil)
    let decodedEnd = try EventTime.instant(encodedEnd, timezone: nil)
    XCTAssertEqual(decodedStart, start)
    XCTAssertEqual(decodedEnd, end)
    XCTAssertNoThrow(try EventTime.validate(start: decodedStart, end: decodedEnd))
  }

  func testSupportedFractionsRoundTripInDifferentTimezones() throws {
    let cases = [
      "2026-10-14T10:00:00.1Z",
      "2026-10-14T10:00:00.123456789Z",
      "2026-10-14T10:00:00.000001Z",
      "2026-10-14T10:00:00.99999999Z",
      "1970-01-01T00:00:00.123456Z",
      "2000-12-31T23:59:59.9Z",
      "2026-10-14T10:00:00.123456+05:30",
    ]
    for text in cases {
      let original = try EventTime.instant(text, timezone: nil)
      for zone in [TimeZone(secondsFromGMT: 0)!, TimeZone(identifier: "Asia/Kolkata")!] {
        let encoded = EventTime.string(original, allDay: false, zone: zone)
        XCTAssertEqual(
          try EventTime.instant(encoded, timezone: nil), original, "\(text) -> \(encoded)")
      }
    }
  }

  func testSubMillisecondInputsRemainDistinct() throws {
    let start = try EventTime.instant("2026-10-14T10:00:00.1000001Z", timezone: nil)
    let end = try EventTime.instant("2026-10-14T10:00:00.1000009Z", timezone: nil)
    XCTAssertGreaterThan(end, start)
    XCTAssertNoThrow(try EventTime.validate(start: start, end: end))
  }

  func testWholeSecondsAndAllDayDatesKeepExistingFormat() throws {
    let zone = TimeZone(secondsFromGMT: 0)!
    let date = try EventTime.instant("2026-10-14T10:00:00Z", timezone: nil)
    XCTAssertEqual(EventTime.string(date, allDay: false, zone: zone), "2026-10-14T10:00:00Z")
    XCTAssertEqual(EventTime.string(date, allDay: true, zone: zone), "2026-10-14")
  }

  private func allDayEvent() throws -> EKEvent {
    let store = EKEventStore()
    let event = EKEvent(eventStore: store)
    let start = try EventTime.day("2026-10-14", zone: .current)
    let end = try EventTime.day("2026-10-15", zone: .current)
    EventKitDates.apply(
      EventDraft(
        calendar: nil, title: "Unsaved test", start: start, end: end,
        allDay: true, timezone: .current, location: nil, notes: nil), to: event)
    return event
  }

  func testAllDayEventOverlapsFinalFractionalSecond() throws {
    let event = try allDayEvent()
    let end = EventKitDates.exclusiveEnd(event)
    let from = end.addingTimeInterval(-0.5)
    XCTAssertLessThan(event.endDate, from)  // Original native-end filter missed this event.
    XCTAssertTrue(EventKitDates.overlaps(event, from: from, to: end))
    XCTAssertGreaterThan(event.endDate, EventKitDates.candidateStart(from))
    XCTAssertFalse(EventKitDates.overlaps(event, from: end, to: end.addingTimeInterval(1)))
    XCTAssertFalse(
      EventKitDates.overlaps(
        event, from: event.startDate.addingTimeInterval(-1), to: event.startDate))
  }

  func testCandidatePaddingDoesNotIncludeTimedEventsOutsideRange() throws {
    let store = EKEventStore()
    let event = EKEvent(eventStore: store)
    let from = try EventTime.instant("2026-10-14T10:00:00.5Z", timezone: nil)
    event.startDate = from.addingTimeInterval(-10)
    event.endDate = from
    XCTAssertGreaterThan(event.endDate, EventKitDates.candidateStart(from))
    XCTAssertFalse(EventKitDates.overlaps(event, from: from, to: from.addingTimeInterval(1)))
    event.endDate = from.addingTimeInterval(1)
    XCTAssertTrue(EventKitDates.overlaps(event, from: from, to: from.addingTimeInterval(2)))
  }
}
