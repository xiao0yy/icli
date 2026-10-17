import Foundation

public enum EventScope: String, Codable { case this, future, all }

public struct AlarmInfo: Codable, Equatable {
  public let relativeSeconds: Double?
  public let absoluteDate: String?
  public init(relativeSeconds: Double?, absoluteDate: String?) {
    self.relativeSeconds = relativeSeconds
    self.absoluteDate = absoluteDate
  }
}
public enum AlertInput {
  public static func parse(_ values: [String], noAlert: Bool) throws -> [Double]? {
    if noAlert && !values.isEmpty { throw CLIError.invalid("--alert conflicts with --no-alert.") }
    if noAlert { return [] }
    if values.isEmpty { return nil }
    let result = try values.map { value -> Double in
      if value == "0" { return 0 }
      guard value.range(of: #"^\d+[smhd]$"#, options: .regularExpression) != nil,
        let amount = Double(value.dropLast())
      else { throw CLIError.invalid("Invalid alert: \(value). Use 0, 15m, 1h, 2d.") }
      let unit: Double = ["s": 1, "m": 60, "h": 3600, "d": 86400][String(value.suffix(1))]!
      let seconds = amount * unit
      guard seconds.isFinite, seconds <= 365 * 86400 else {
        throw CLIError.invalid("Alert must be at most 365 days before the event.")
      }
      return -seconds
    }
    return Array(Set(result)).sorted()
  }
}
public struct RecurrenceSpec: Equatable {
  public let frequency: String
  public let interval: Int
  public let weekdays: [Int]
  public let until: Date?
  public let count: Int?
  public let timezone: TimeZone?
  public let untilIsDate: Bool
  public init(
    frequency: String, interval: Int = 1, weekdays: [Int] = [], until: Date? = nil,
    count: Int? = nil, timezone: TimeZone? = nil, untilIsDate: Bool = false
  ) {
    self.frequency = frequency
    self.interval = interval
    self.weekdays = weekdays
    self.until = until
    self.count = count
    self.timezone = timezone
    self.untilIsDate = untilIsDate
  }
  public func validate(start: Date) throws {
    guard ["daily", "weekly", "monthly", "yearly"].contains(frequency) else {
      throw CLIError.invalid("--repeat must be daily, weekly, monthly, or yearly.")
    }
    guard (1...100000).contains(interval) else {
      throw CLIError.invalid("--repeat-interval must be between 1 and 100000.")
    }
    guard weekdays.isEmpty || frequency == "weekly" else {
      throw CLIError.invalid("--repeat-days is only supported with weekly recurrence.")
    }
    guard weekdays.allSatisfy({ (1...7).contains($0) }) else {
      throw CLIError.invalid("Invalid repeat weekday.")
    }
    if until != nil && count != nil {
      throw CLIError.invalid("--repeat-until conflicts with --repeat-count.")
    }
    if let count, !(1...100000).contains(count) {
      throw CLIError.invalid("--repeat-count must be between 1 and 100000.")
    }
    if let until, until < start {
      throw CLIError.invalid("Repeat end must not precede the event start.")
    }
  }
  public static func parse(
    frequency: String?, interval: Int?, days: String?, until: String?, count: Int?,
    timezone: TimeZone
  ) throws -> RecurrenceSpec? {
    guard let frequency else {
      if interval != nil || days != nil || until != nil || count != nil {
        throw CLIError.invalid("Repeat options require --repeat.")
      }
      return nil
    }
    let names = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]
    var weekdays: [Int] = []
    if let days {
      let parts = days.split(separator: ",", omittingEmptySubsequences: false)
      weekdays = try parts.map {
        guard let day = names[$0.trimmingCharacters(in: .whitespaces).lowercased()] else {
          throw CLIError.invalid("Repeat days must be comma-separated mon,tue,wed,thu,fri,sat,sun.")
        }
        return day
      }
      weekdays = Array(Set(weekdays)).sorted()
    }
    var end: Date?
    if let until {
      if until.count == 10 {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        end = cal.date(byAdding: .day, value: 1, to: try EventTime.day(until, zone: timezone))!
          .addingTimeInterval(-1)
      } else {
        end = try EventTime.instant(until, timezone: timezone.identifier)
      }
    }
    return RecurrenceSpec(
      frequency: frequency, interval: interval ?? 1, weekdays: weekdays, until: end, count: count,
      timezone: timezone, untilIsDate: until?.count == 10)
  }
}
public struct RecurrenceInfo: Codable, Equatable {
  public let frequency: String
  public let interval: Int
  public let weekdays: [Int]
  public let weekdayOrdinals: [Int]
  public let monthDays: [Int]
  public let months: [Int]
  public let yearDays: [Int]
  public let yearWeeks: [Int]
  public let setPositions: [Int]
  public let until: String?
  public let count: Int?
  public init(
    frequency: String, interval: Int, weekdays: [Int], weekdayOrdinals: [Int] = [],
    monthDays: [Int] = [], months: [Int] = [],
    yearDays: [Int] = [], yearWeeks: [Int] = [], setPositions: [Int] = [], until: String?,
    count: Int?
  ) {
    self.frequency = frequency
    self.interval = interval
    self.weekdays = weekdays
    self.weekdayOrdinals = weekdayOrdinals
    self.monthDays = monthDays
    self.months = months
    self.yearDays = yearDays
    self.yearWeeks = yearWeeks
    self.setPositions = setPositions
    self.until = until
    self.count = count
  }
}
public struct ParticipantInfo: Codable, Equatable {
  public let name: String?
  public let email: String?
  public let url: String
  public init(name: String?, email: String?, url: String) {
    self.name = name
    self.email = email
    self.url = url
  }
  public func matches(_ term: String) -> Bool {
    [name ?? "", email ?? "", url].contains {
      $0.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
  }
}
public struct SourceInfo: Codable {
  public let id: String
  public let title: String
  public let type: String
  public let canCreateCalendars: Bool
  public init(id: String, title: String, type: String, canCreateCalendars: Bool) {
    self.id = id
    self.title = title
    self.type = type
    self.canCreateCalendars = canCreateCalendars
  }
}
public struct CalendarMutation: Codable {
  public let action: String
  public let dryRun: Bool
  public let calendar: CalendarInfo
  public let before: CalendarInfo?
  public init(action: String, dryRun: Bool, calendar: CalendarInfo, before: CalendarInfo? = nil) {
    self.action = action
    self.dryRun = dryRun
    self.calendar = calendar
    self.before = before
  }
}
public enum CalendarColor {
  public static func components(_ value: String) throws -> (Double, Double, Double) {
    guard value.range(of: #"^#[0-9a-fA-F]{6}$"#, options: .regularExpression) != nil,
      let hex = UInt32(value.dropFirst(), radix: 16)
    else { throw CLIError.invalid("Color must be #RRGGBB.") }
    return (
      Double((hex >> 16) & 255) / 255, Double((hex >> 8) & 255) / 255, Double(hex & 255) / 255
    )
  }
}
public enum ScopePolicy {
  public static func resolve(recurring: Bool, scope: EventScope?, changingRule: Bool = false) throws
    -> EventScope
  {
    if recurring {
      guard let scope else {
        throw CLIError.invalid("Recurring events require explicit --scope this|future|all.")
      }
      if changingRule && scope == .this {
        throw CLIError.invalid("Changing recurrence requires --scope future or all.")
      }
      return scope
    }
    if let scope, scope != .this {
      throw CLIError.invalid("Non-recurring events only support --scope this.")
    }
    return .this
  }
}
