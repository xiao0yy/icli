import Foundation

public struct CLIError: Error, LocalizedError {
  public let code: String
  public let message: String
  public let exitCode: Int32
  public var errorDescription: String? { message }
  public init(_ code: String, _ message: String, exitCode: Int32 = 1) {
    self.code = code
    self.message = message
    self.exitCode = exitCode
  }
  public static func invalid(_ message: String) -> CLIError {
    .init("INVALID_ARGUMENT", message, exitCode: 2)
  }
}

public struct CalendarInfo: Codable, Equatable {
  public let id: String
  public let title: String
  public let source: String
  public let writable: Bool
  public let isDefault: Bool
  public let sourceID: String?
  public let color: String?
  public let manageable: Bool
  public init(
    id: String, title: String, source: String, writable: Bool, isDefault: Bool,
    sourceID: String? = nil, color: String? = nil, manageable: Bool = false
  ) {
    self.id = id
    self.title = title
    self.source = source
    self.writable = writable
    self.isDefault = isDefault
    self.sourceID = sourceID
    self.color = color
    self.manageable = manageable
  }
}

public struct EventInfo: Codable, Equatable {
  public let id: String
  public let calendarID: String
  public let title: String
  public let start: String
  public let end: String
  public let allDay: Bool
  public let timezone: String?
  public let location: String?
  public let notes: String?
  public let recurring: Bool
  public let writable: Bool
  public let alarms: [AlarmInfo]
  public let recurrenceRules: [RecurrenceInfo]
  public let attendees: [ParticipantInfo]
  public let organizer: ParticipantInfo?
  public init(
    id: String, calendarID: String, title: String, start: String, end: String, allDay: Bool,
    timezone: String?, location: String?, notes: String?, recurring: Bool, writable: Bool,
    alarms: [AlarmInfo] = [], recurrenceRules: [RecurrenceInfo] = [],
    attendees: [ParticipantInfo] = [], organizer: ParticipantInfo? = nil
  ) {
    self.id = id
    self.calendarID = calendarID
    self.title = title
    self.start = start
    self.end = end
    self.allDay = allDay
    self.timezone = timezone
    self.location = location
    self.notes = notes
    self.recurring = recurring
    self.writable = writable
    self.alarms = alarms
    self.recurrenceRules = recurrenceRules
    self.attendees = attendees
    self.organizer = organizer
  }
}

public struct EventDraft {
  public var calendar: String?
  public var title: String
  public var start: Date
  public var end: Date
  public var allDay: Bool
  public var timezone: TimeZone
  public var location: String?
  public var notes: String?
  public var alerts: [Double]?
  public var recurrence: RecurrenceSpec?
  public init(
    calendar: String?, title: String, start: Date, end: Date, allDay: Bool,
    timezone: TimeZone, location: String?, notes: String?, alerts: [Double]? = nil,
    recurrence: RecurrenceSpec? = nil
  ) {
    self.calendar = calendar
    self.title = title
    self.start = start
    self.end = end
    self.allDay = allDay
    self.timezone = timezone
    self.location = location
    self.notes = notes
    self.alerts = alerts
    self.recurrence = recurrence
  }
}

public struct EventPatch {
  public var calendar: String?
  public var title: String?
  public var start: String?
  public var end: String?
  public var timezone: String?
  public var location: String?
  public var notes: String?
  public var clearLocation: Bool
  public var clearNotes: Bool
  public var alerts: [Double]?
  public var recurrence: RecurrenceSpec?
  public var clearRecurrence: Bool
  public init(
    calendar: String? = nil, title: String? = nil, start: String? = nil, end: String? = nil,
    timezone: String? = nil, location: String? = nil, notes: String? = nil,
    clearLocation: Bool = false, clearNotes: Bool = false, alerts: [Double]? = nil,
    recurrence: RecurrenceSpec? = nil, clearRecurrence: Bool = false
  ) {
    self.calendar = calendar
    self.title = title
    self.start = start
    self.end = end
    self.timezone = timezone
    self.location = location
    self.notes = notes
    self.clearLocation = clearLocation
    self.clearNotes = clearNotes
    self.alerts = alerts
    self.recurrence = recurrence
    self.clearRecurrence = clearRecurrence
  }
  public func validate() throws {
    guard
      calendar != nil || title != nil || start != nil || end != nil || timezone != nil
        || location != nil || notes != nil || clearLocation || clearNotes || alerts != nil
        || recurrence != nil || clearRecurrence
    else {
      throw CLIError.invalid("Provide at least one field to update.")
    }
    if clearRecurrence && recurrence != nil {
      throw CLIError.invalid("--clear-repeat conflicts with --repeat.")
    }
    if clearLocation && location != nil {
      throw CLIError.invalid("--location conflicts with --clear-location.")
    }
    if clearNotes && notes != nil {
      throw CLIError.invalid("--notes conflicts with --clear-notes.")
    }
    if let title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw CLIError.invalid("Title cannot be empty.")
    }
  }
  public func applying(to original: EventDraft) throws -> EventDraft {
    try validate()
    var result = original
    let zone = try timezone.map { try EventTime.zone($0) } ?? original.timezone
    if original.allDay, timezone != nil, start == nil || end == nil {
      throw CLIError.invalid("Changing an all-day timezone requires both --start and --end dates.")
    }
    if let start {
      result.start = try EventTime.parse(
        start, allDay: original.allDay, timezone: timezone, fallbackZone: zone)
    }
    if let end {
      result.end = try EventTime.parse(
        end, allDay: original.allDay, timezone: timezone, fallbackZone: zone)
    }
    try EventTime.validate(start: result.start, end: result.end)
    if let title { result.title = title }
    if let calendar { result.calendar = calendar }
    result.timezone = zone
    if clearLocation { result.location = nil } else if let location { result.location = location }
    if clearNotes { result.notes = nil } else if let notes { result.notes = notes }
    if let alerts { result.alerts = alerts }
    if clearRecurrence {
      result.recurrence = nil
    } else if let recurrence {
      try recurrence.validate(start: result.start)
      result.recurrence = recurrence
    }
    return result
  }
}

public struct AuthInfo: Codable {
  public let status: String
  public let fullAccess: Bool
  public init(status: String, fullAccess: Bool) {
    self.status = status
    self.fullAccess = fullAccess
  }
}
public struct MutationResult: Codable {
  public let action: String
  public let dryRun: Bool
  public let event: EventInfo
  public let before: EventInfo?
  public let scope: EventScope?
  public init(
    action: String, dryRun: Bool, event: EventInfo, before: EventInfo? = nil,
    scope: EventScope? = nil
  ) {
    self.action = action
    self.dryRun = dryRun
    self.event = event
    self.before = before
    self.scope = scope
  }
}

public protocol CalendarService {
  func authorization() -> AuthInfo
  func requestAccess() throws -> AuthInfo
  func calendars() throws -> [CalendarInfo]
  func sources() throws -> [SourceInfo]
  func createCalendar(title: String, source: String?, color: String?, dryRun: Bool) throws
    -> CalendarMutation
  func updateCalendar(id: String, title: String?, color: String?, dryRun: Bool) throws
    -> CalendarMutation
  func deleteCalendar(id: String, dryRun: Bool) throws -> CalendarMutation
  func events(from: Date, to: Date, calendars: [String]) throws -> [EventInfo]
  func events(from: Date, to: Date, calendar: String?) throws -> [EventInfo]
  func event(id: String) throws -> EventInfo
  func create(_ draft: EventDraft, dryRun: Bool) throws -> MutationResult
  func update(id: String, patch: EventPatch, scope: EventScope?, dryRun: Bool) throws
    -> MutationResult
  func delete(id: String, scope: EventScope?, dryRun: Bool) throws -> MutationResult
}

public enum CalendarSelection {
  public static func resolve(
    _ selector: String?, in calendars: [CalendarInfo], requireWritable: Bool = false
  ) throws -> CalendarInfo {
    let selected: CalendarInfo
    if let selector {
      if let exact = calendars.first(where: { $0.id == selector }) {
        selected = exact
      } else {
        let matches = calendars.filter { $0.title == selector }
        guard !matches.isEmpty else {
          throw CLIError("NOT_FOUND", "Calendar not found: \(selector)", exitCode: 4)
        }
        guard matches.count == 1 else {
          throw CLIError.invalid(
            "Ambiguous calendar name. Use an ID: \(matches.map(\.id).joined(separator: ", "))")
        }
        selected = matches[0]
      }
    } else {
      guard let fallback = calendars.first(where: { $0.isDefault && $0.writable }) else {
        throw CLIError(
          "NO_DEFAULT_CALENDAR", "No writable default calendar. Provide --calendar <id>.",
          exitCode: 5)
      }
      selected = fallback
    }
    if requireWritable && !selected.writable {
      throw CLIError("READ_ONLY", "Calendar is read-only: \(selected.title)", exitCode: 5)
    }
    return selected
  }
}

extension CalendarService {
  public func update(id: String, patch: EventPatch, dryRun: Bool) throws -> MutationResult {
    try update(id: id, patch: patch, scope: nil, dryRun: dryRun)
  }
  public func delete(id: String, dryRun: Bool) throws -> MutationResult {
    try delete(id: id, scope: nil, dryRun: dryRun)
  }
}
