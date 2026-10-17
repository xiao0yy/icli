import ArgumentParser
import CLICore
import CalendarDomain
import EventKitCalendar
import Foundation

struct QueryOptions: ParsableArguments {
  @Option(
    name: .shortAndLong, help: "Calendar ID or unique name; repeatable; default: all calendars.")
  var calendar: [String] = []
  @Option(help: "Exclude a calendar by ID or unique name; repeatable.") var excludeCalendar:
    [String] = []
  @Option(help: "Match attendee or organizer name/email; repeatable, matches any term.")
  var attendee: [String] = []
  @Flag(help: "Hide recurring events and detached occurrences.") var noRecurring = false
  @Option(
    name: [.customShort("n"), .long],
    help: "Maximum number of results, applied after filtering and sorting.") var limit: Int?
  @Option(help: "Sort by start or title.") var sort = "start"
  @Option(help: "IANA timezone for date boundaries, e.g. Asia/Shanghai.") var timezone: String?

  func fetch(
    from: Date, to: Date, search: String? = nil, service: any CalendarService = EventKitService()
  ) throws -> [EventInfo] {
    try EventQuery.validate(limit: limit, sort: sort, query: search, attendees: attendee)
    var excluded = Set<String>()
    if !excludeCalendar.isEmpty {
      let calendars = try service.calendars()
      for selector in excludeCalendar {
        excluded.insert(try CalendarSelection.resolve(selector, in: calendars).id)
      }
    }
    let events = try service.events(from: from, to: to, calendars: calendar)
    return try EventQuery.apply(
      events, excluded: excluded, noRecurring: noRecurring, query: search, sort: sort, limit: limit,
      attendees: attendee)
  }
}

struct Today: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Show today's agenda in the chosen timezone.")
  @OptionGroup var output: OutputOptions
  @OptionGroup var query: QueryOptions
  func run() throws {
    let (start, end) = try EventTime.range(from: nil, to: nil, timezone: query.timezone)
    try showEvents(query.fetch(from: start, to: end), output: output)
  }
}

struct Upcoming: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Show N calendar days starting today (default: 7).")
  @OptionGroup var output: OutputOptions
  @OptionGroup var query: QueryOptions
  @Option(name: .shortAndLong, help: "Number of calendar days, 1...365.") var days = 7
  func run() throws {
    let (start, end) = try EventTime.range(
      from: nil, to: nil, timezone: query.timezone, defaultDays: days)
    try showEvents(query.fetch(from: start, to: end), output: output)
  }
}

struct Search: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Search titles, locations, and notes; default range: today + 30 days.")
  @Argument(help: "Case-insensitive substring.") var text: String
  @OptionGroup var output: OutputOptions
  @OptionGroup var query: QueryOptions
  @Option(name: .shortAndLong, help: "Start date or timestamp; default: today.") var from: String?
  @Option(name: .shortAndLong, help: "Exclusive end; default: start + 30 calendar days.") var to:
    String?
  func run() throws {
    let (start, end) = try EventTime.range(
      from: from, to: to, timezone: query.timezone, defaultDays: 30)
    try showEvents(query.fetch(from: start, to: end, search: text), output: output)
  }
}

func showEvents(_ values: [EventInfo], output: OutputOptions) throws {
  let rows = values.map {
    "\($0.start) → \($0.end)\t\($0.title)\($0.recurring ? " [recurring]" : "")\n  ID: \($0.id)\n  Calendar: \($0.calendarID)"
  }
  try Output.emit(
    values, json: output.json, text: rows.isEmpty ? "No events." : rows.joined(separator: "\n"))
}
