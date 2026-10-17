import ArgumentParser
import CalendarDomain
import Foundation

struct ReminderOptions: ParsableArguments {
  @Option(help: "Replace reminders with these offsets before start: 0, 15m, 1h, 2d; repeatable.")
  var alert: [String] = []
  @Flag(help: "Remove all reminders, including calendar defaults.") var noAlert = false
  func offsets() throws -> [Double]? { try AlertInput.parse(alert, noAlert: noAlert) }
}
struct RepeatOptions: ParsableArguments {
  @Option(
    name: .customLong("repeat"),
    help: "Recurrence frequency: daily, weekly, monthly, yearly. Replaces the rule.") var frequency:
    String?
  @Option(help: "Repeat every N units; requires --repeat.") var repeatInterval: Int?
  @Option(help: "Weekly days: mon,tue,wed,thu,fri,sat,sun; requires --repeat weekly.")
  var repeatDays: String?
  @Option(help: "Inclusive last date or timestamp; requires --repeat.") var repeatUntil: String?
  @Option(help: "Number of occurrences; conflicts with --repeat-until.") var repeatCount: Int?
  func spec(zone: TimeZone) throws -> RecurrenceSpec? {
    let value = try RecurrenceSpec.parse(
      frequency: frequency, interval: repeatInterval, days: repeatDays, until: repeatUntil,
      count: repeatCount, timezone: zone)
    try value?.validate(start: .distantPast)
    return value
  }
}
struct ScopeOptions: ParsableArguments {
  @Option(help: "Recurring mutation scope: this, future, all. Required for recurring events.")
  var scope: String?
  func value() throws -> EventScope? {
    guard let scope else { return nil }
    guard let value = EventScope(rawValue: scope) else {
      throw CLIError.invalid("--scope must be this, future, or all.")
    }
    return value
  }
}
