import ArgumentParser
import CLICore
import CalendarDomain
import Darwin
import EventKitCalendar
import Foundation

struct Events: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Query and manage events.",
    subcommands: [
      EventList.self, EventGet.self, EventCreate.self, EventUpdate.self, EventDelete.self,
    ])
  @OptionGroup var output: OutputOptions
}
struct EventList: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list", abstract: "List overlapping events in [from, to), default: today.",
    aliases: ["ls"])
  @OptionGroup var output: OutputOptions
  @Option(name: .shortAndLong, help: "Start date, ISO timestamp, or today/tomorrow/yesterday.")
  var from: String?
  @Option(name: .shortAndLong, help: "Exclusive end date or timestamp; default: start + one day.")
  var to: String?
  @OptionGroup var query: QueryOptions
  func run() throws {
    let (start, end) = try EventTime.range(from: from, to: to, timezone: query.timezone)
    try showEvents(query.fetch(from: start, to: end), output: output)
  }
}
struct EventGet: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "get", abstract: "Read an event by ID returned by list.", aliases: ["show"])
  @OptionGroup var output: OutputOptions
  @Argument(help: "Opaque event or occurrence ID.") var id: String
  func run() throws {
    let value = try EventKitService().event(id: id)
    try Output.emit(value, json: output.json, text: describe(value))
  }
}
struct EventCreate: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "create", abstract: "Create an event with optional reminders and recurrence.",
    aliases: ["add"])
  @OptionGroup var output: OutputOptions
  @Option(
    name: .shortAndLong, help: "Calendar ID or unique name; default: system writable default.")
  var calendar: String?
  @Argument(help: "Event title; alternatively use --title.") var positionalTitle: String?
  @Option(help: "Event title; conflicts with positional title.") var title: String?
  @Option(name: .shortAndLong, help: "ISO 8601 timestamp; YYYY-MM-DD for all-day events.")
  var start: String
  @Option(name: .shortAndLong, help: "End timestamp or exclusive all-day end date.") var end: String
  @Flag(help: "Use date-only, all-day semantics.") var allDay = false
  @Option(help: "IANA timezone for local timestamps or all-day dates.") var timezone: String?
  @Option(help: "Location.") var location: String?
  @Option(help: "Notes.") var notes: String?
  @OptionGroup var reminders: ReminderOptions
  @OptionGroup var repeats: RepeatOptions
  @Flag(help: "Preview without writing.") var dryRun = false
  func run() throws {
    guard title == nil || positionalTitle == nil else {
      throw CLIError.invalid("Use a positional title or --title, not both.")
    }
    guard let resolvedTitle = title ?? positionalTitle,
      !resolvedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw CLIError.invalid("Provide a nonempty event title.")
    }
    let zone = try EventTime.zone(timezone)
    let begin = try EventTime.parse(start, allDay: allDay, timezone: timezone)
    let finish = try EventTime.parse(end, allDay: allDay, timezone: timezone)
    try EventTime.validate(start: begin, end: finish)
    let alerts = try reminders.offsets()
    let recurrence = try repeats.spec(zone: zone)
    try recurrence?.validate(start: begin)
    let draft = EventDraft(
      calendar: calendar, title: resolvedTitle, start: begin, end: finish, allDay: allDay,
      timezone: zone, location: location, notes: notes, alerts: alerts, recurrence: recurrence)
    let result = try EventKitService().create(draft, dryRun: dryRun)
    try mutation(result, output: output)
  }
}
struct EventUpdate: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "update", abstract: "Change supplied fields; recurring events require --scope.")
  @OptionGroup var output: OutputOptions
  @Argument var id: String
  @Option var title: String?
  @Option var calendar: String?
  @Option(help: "New start timestamp, or date for an all-day event.") var start: String?
  @Option(help: "New end timestamp, or exclusive date for an all-day event.") var end: String?
  @Option var timezone: String?
  @Option var location: String?
  @Option var notes: String?
  @Flag var clearLocation = false
  @Flag var clearNotes = false
  @OptionGroup var reminders: ReminderOptions
  @OptionGroup var repeats: RepeatOptions
  @OptionGroup var scopeOptions: ScopeOptions
  @Flag(help: "Remove the recurrence rule; recurring events require --scope future or all.")
  var clearRepeat = false
  @Flag(help: "Preview before and after without writing.") var dryRun = false
  func run() throws {
    let alerts = try reminders.offsets()
    let service = EventKitService()
    let recurrence = try repeats.spec(zone: EventTime.zone(timezone))
    let scope = try scopeOptions.value()
    var patch = EventPatch(
      calendar: calendar, title: title, start: start, end: end, timezone: timezone,
      location: location, notes: notes, clearLocation: clearLocation, clearNotes: clearNotes,
      alerts: alerts, recurrence: recurrence, clearRecurrence: clearRepeat)
    try patch.validate()
    if repeats.frequency != nil && timezone == nil {
      let original = try service.event(id: id)
      patch.recurrence = try repeats.spec(zone: EventTime.zone(original.timezone))
    }
    let result = try service.update(id: id, patch: patch, scope: scope, dryRun: dryRun)
    try mutation(result, output: output)
  }
}
public enum DeletePolicy {
  public static func needsConfirmation(yes: Bool, dryRun: Bool, interactive: Bool) throws -> Bool {
    if yes || dryRun { return false }
    guard interactive else {
      throw CLIError.invalid("Non-interactive deletion requires --yes; use --dry-run to preview.")
    }
    return true
  }
}
struct EventDelete: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "delete", abstract: "Delete an event; recurring events require --scope.")
  @OptionGroup var output: OutputOptions
  @Argument var id: String
  @OptionGroup var scopeOptions: ScopeOptions
  @Flag(help: "Confirm deletion without prompting.") var yes = false
  @Flag(help: "Preview without deleting.") var dryRun = false
  func run() throws {
    let scope = try scopeOptions.value()
    let prompt = try DeletePolicy.needsConfirmation(
      yes: yes, dryRun: dryRun, interactive: isatty(STDIN_FILENO) != 0)
    let service = EventKitService()
    if prompt {
      let event = try service.delete(id: id, scope: scope, dryRun: true).event
      Output.stderr(
        "Delete '\(event.title)' (\(event.start)), scope \(scope?.rawValue ?? "this")? [y/N] ")
      guard let reply = readLine(), ["y", "yes"].contains(reply.lowercased()) else {
        throw CLIError("CANCELLED", "Deletion cancelled.")
      }
    }
    try mutation(service.delete(id: id, scope: scope, dryRun: dryRun), output: output)
  }
}
private func describe(_ event: EventInfo) -> String {
  "\(event.title)\n\(event.start) → \(event.end)\nID: \(event.id)\nCalendar: \(event.calendarID)\nTimezone: \(event.timezone ?? "unknown")\nLocation: \(event.location ?? "")\nNotes: \(event.notes ?? "")\nRecurring: \(event.recurring)\nReminders: \(event.alarms.map { $0.absoluteDate ?? String($0.relativeSeconds ?? 0) + "s" }.joined(separator: ", "))\nRecurrence: \(event.recurrenceRules.map { "\($0.frequency) every \($0.interval)" }.joined(separator: ", "))\nAttendees: \(event.attendees.map { $0.email ?? $0.name ?? $0.url }.joined(separator: ", "))"
}
private func mutation(_ value: MutationResult, output: OutputOptions) throws {
  let prefix = value.dryRun ? "Preview (no changes saved)" : "Saved"
  let before = value.dryRun ? value.before.map { "\nBefore:\n\(describe($0))\nAfter:" } ?? "" : ""
  try Output.emit(
    value, json: output.json,
    text:
      "\(prefix): \(value.action)\(value.scope.map { " (scope: \($0.rawValue))" } ?? "")\(before)\n\(describe(value.event))"
  )
}
