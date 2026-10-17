import CalendarCommands
import CalendarDomain
import XCTest

final class CalendarTests: XCTestCase {
  func testOffsetRequiredAndInvalidDate() throws {
    XCTAssertThrowsError(try EventTime.instant("2026-10-14T10:00:00", timezone: nil))
    XCTAssertThrowsError(try EventTime.day("2026-02-30", zone: TimeZone(secondsFromGMT: 0)!))
    let a = try EventTime.instant("2026-10-14T10:00:00+08:00", timezone: nil)
    let b = try EventTime.instant("2026-10-14T02:00:00Z", timezone: nil)
    XCTAssertEqual(a, b)
  }
  func testDSTGapAndRepeatedTime() throws {
    XCTAssertThrowsError(try EventTime.instant("2026-03-08T02:30:00", timezone: "America/New_York"))
    XCTAssertThrowsError(try EventTime.instant("2026-11-01T01:30:00", timezone: "America/New_York"))
    XCTAssertNoThrow(try EventTime.instant("2026-11-01T01:30:00-04:00", timezone: nil))
    XCTAssertNoThrow(try EventTime.instant("2026-10-14T10:00", timezone: "Asia/Shanghai"))
  }
  func testAllDayDSTAndRange() throws {
    let zone = try EventTime.zone("America/New_York")
    let start = try EventTime.day("2026-03-08", zone: zone)
    let end = try EventTime.day("2026-03-09", zone: zone)
    XCTAssertEqual(end.timeIntervalSince(start), 23 * 3600)
    XCTAssertEqual(EventTime.string(start, allDay: true, zone: zone), "2026-03-08")
    let range = try EventTime.range(from: "2026-03-08", to: nil, timezone: "America/New_York")
    XCTAssertEqual(range.0, start)
    XCTAssertEqual(range.1, end)
    XCTAssertThrowsError(try EventTime.range(from: "2026-01-01", to: "2028-01-01", timezone: nil))
    XCTAssertThrowsError(try EventTime.validate(start: end, end: start))
  }
  func testCalendarSelection() throws {
    let values = [
      CalendarInfo(id: "a", title: "Work", source: "Local", writable: true, isDefault: true),
      CalendarInfo(id: "b", title: "Work", source: "Remote", writable: false, isDefault: false),
    ]
    XCTAssertEqual(try CalendarSelection.resolve(nil, in: values).id, "a")
    XCTAssertEqual(try CalendarSelection.resolve("a", in: values).id, "a")
    XCTAssertThrowsError(try CalendarSelection.resolve("Work", in: values))
    XCTAssertThrowsError(try CalendarSelection.resolve("b", in: values, requireWritable: true))
    XCTAssertThrowsError(try CalendarSelection.resolve(nil, in: []))
  }
  func testPatchValidation() throws {
    XCTAssertThrowsError(try EventPatch().validate())
    XCTAssertThrowsError(try EventPatch(title: "  ").validate())
    XCTAssertThrowsError(try EventPatch(location: "Office", clearLocation: true).validate())
    XCTAssertThrowsError(try EventPatch(notes: "text", clearNotes: true).validate())
    XCTAssertNoThrow(try EventPatch(clearNotes: true).validate())
  }
  func testDeletePolicy() throws {
    XCTAssertThrowsError(
      try DeletePolicy.needsConfirmation(yes: false, dryRun: false, interactive: false))
    XCTAssertFalse(try DeletePolicy.needsConfirmation(yes: true, dryRun: false, interactive: false))
    XCTAssertFalse(try DeletePolicy.needsConfirmation(yes: false, dryRun: true, interactive: false))
    XCTAssertTrue(try DeletePolicy.needsConfirmation(yes: false, dryRun: false, interactive: true))
  }
  private func draft(allDay: Bool = false) throws -> EventDraft {
    EventDraft(
      calendar: "a", title: "Original",
      start: try EventTime.instant("2026-10-14T10:00:00+08:00", timezone: nil),
      end: try EventTime.instant("2026-10-14T11:00:00+08:00", timezone: nil), allDay: allDay,
      timezone: try EventTime.zone("Asia/Shanghai"), location: "Office", notes: "Keep me")
  }
  func testPatchPreservesOmittedFieldsAndClearsExplicitly() throws {
    let original = try draft()
    let changed = try EventPatch(title: "Updated", clearLocation: true).applying(to: original)
    XCTAssertEqual(changed.title, "Updated")
    XCTAssertNil(changed.location)
    XCTAssertEqual(changed.notes, original.notes)
    XCTAssertEqual(changed.start, original.start)
    XCTAssertEqual(changed.end, original.end)
    XCTAssertEqual(changed.calendar, original.calendar)
    XCTAssertEqual(original.location, "Office")
  }
  func testPatchRejectsInvalidPartialRangeWithoutChangingOriginal() throws {
    let original = try draft()
    XCTAssertThrowsError(try EventPatch(start: "2026-10-14T12:00:00+08:00").applying(to: original))
    XCTAssertThrowsError(try EventPatch(timezone: "Invalid/Zone").applying(to: original))
    let changed = try EventPatch(end: "2026-10-14T12:00:00+08:00").applying(to: original)
    XCTAssertEqual(changed.end.timeIntervalSince(original.start), 7200)
    XCTAssertEqual(original.end.timeIntervalSince(original.start), 3600)
  }
  func testAllDayTimezoneChangeNeedsBothDates() throws {
    let original = try draft(allDay: true)
    XCTAssertThrowsError(try EventPatch(timezone: "America/New_York").applying(to: original))
    let changed = try EventPatch(
      start: "2026-03-08", end: "2026-03-09", timezone: "America/New_York"
    ).applying(to: original)
    XCTAssertEqual(changed.end.timeIntervalSince(changed.start), 23 * 3600)
    XCTAssertEqual(changed.timezone.identifier, "America/New_York")
  }
  func testRejectsInvalidOffsetTimestampDate() throws {
    XCTAssertThrowsError(try EventTime.instant("2026-02-30T10:00:00+08:00", timezone: nil))
  }
  func testOccurrenceIDIsDeterministicAndRoundTrips() throws {
    let value = OccurrenceID(
      identifier: "event-α", start: Date(timeIntervalSince1970: 1_234_567_890), calendar: "calendar"
    )
    let encoded = value.encoded()
    for _ in 0..<20 { XCTAssertEqual(value.encoded(), encoded) }
    XCTAssertEqual(try OccurrenceID.decode(encoded), value)
    XCTAssertThrowsError(try OccurrenceID.decode("icli-occ:invalid"))
    XCTAssertThrowsError(try OccurrenceID.decode("normal-event-id"))
  }
}
