import AppKit
import CalendarDomain
import EventKit
import Foundation

extension EventKitService {
  public func sources() throws -> [SourceInfo] {
    try requireAccess()
    return store.sources.map { source in
      SourceInfo(
        id: source.sourceIdentifier, title: source.title,
        type: ["local", "exchange", "caldav", "mobileme", "subscribed", "birthdays"].indices
          .contains(source.sourceType.rawValue)
          ? ["local", "exchange", "caldav", "mobileme", "subscribed", "birthdays"][
            source.sourceType.rawValue] : "unknown",
        canCreateCalendars: [.local, .exchange, .calDAV, .mobileMe].contains(source.sourceType))
    }.sorted { ($0.title, $0.id) < ($1.title, $1.id) }
  }
  private func selectedSource(_ selector: String?) throws -> EKSource {
    let candidates = try sources().filter(\.canCreateCalendars)
    let id: String
    if let selector {
      if let exact = candidates.first(where: { $0.id == selector }) {
        id = exact.id
      } else {
        let matches = candidates.filter { $0.title == selector }
        guard matches.count == 1 else {
          throw CLIError.invalid(
            "Source must match one writable account. Use 'cal sources list' and its ID.")
        }
        id = matches[0].id
      }
    } else if let source = store.defaultCalendarForNewEvents?.source,
      candidates.contains(where: { $0.id == source.sourceIdentifier })
    {
      id = source.sourceIdentifier
    } else {
      let local = candidates.filter { $0.type == "local" }
      guard local.count == 1 else {
        throw CLIError.invalid("No default account. Provide --source <id>.")
      }
      id = local[0].id
    }
    guard let source = store.source(withIdentifier: id) else {
      throw CLIError("NOT_FOUND", "Calendar source disappeared.", exitCode: 4)
    }
    return source
  }
  private func setColor(_ color: String?, on calendar: EKCalendar) throws {
    if let color {
      let (red, green, blue) = try CalendarColor.components(color)
      calendar.cgColor = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1).cgColor
    }
  }
  private func manageable(_ calendar: EKCalendar) throws {
    guard calendar.allowsContentModifications && !calendar.isImmutable else {
      throw CLIError("READ_ONLY", "Calendar cannot be managed: \(calendar.title)", exitCode: 5)
    }
  }
  public func createCalendar(title: String, source: String?, color: String?, dryRun: Bool) throws
    -> CalendarMutation
  {
    try requireAccess()
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CLIError.invalid("Calendar title cannot be empty.")
    }
    let calendar = EKCalendar(for: .event, eventStore: store)
    calendar.source = try selectedSource(source)
    calendar.title = title
    try setColor(color, on: calendar)
    if !dryRun { try store.saveCalendar(calendar, commit: true) }
    return CalendarMutation(action: "create", dryRun: dryRun, calendar: calendarDTO(calendar))
  }
  public func updateCalendar(id: String, title: String?, color: String?, dryRun: Bool) throws
    -> CalendarMutation
  {
    guard title != nil || color != nil else {
      throw CLIError.invalid("Provide --title or --color.")
    }
    if let title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw CLIError.invalid("Calendar title cannot be empty.")
    }
    let calendar = try calendar(id)
    try manageable(calendar)
    let before = calendarDTO(calendar)
    if let title { calendar.title = title }
    try setColor(color, on: calendar)
    if !dryRun { try store.saveCalendar(calendar, commit: true) }
    return CalendarMutation(
      action: "update", dryRun: dryRun, calendar: calendarDTO(calendar), before: before)
  }
  public func deleteCalendar(id: String, dryRun: Bool) throws -> CalendarMutation {
    let calendar = try calendar(id)
    try manageable(calendar)
    let before = calendarDTO(calendar)
    if !dryRun { try store.removeCalendar(calendar, commit: true) }
    return CalendarMutation(action: "delete", dryRun: dryRun, calendar: before, before: before)
  }
}
