import ArgumentParser
import CLICore
import CalendarDomain
import Darwin
import EventKitCalendar
import Foundation

struct Calendars: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Discover local and synced calendars.",
    subcommands: [
      CalendarList.self, CalendarCreate.self, CalendarUpdate.self, CalendarDelete.self,
    ], defaultSubcommand: CalendarList.self)
  @OptionGroup var output: OutputOptions
}
struct CalendarList: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list", abstract: "List calendars and their IDs.")
  @OptionGroup var output: OutputOptions
  func run() throws {
    let values = try EventKitService().calendars()
    let rows = values.map {
      "\($0.id)\t\($0.title)\t\($0.writable ? "writable" : "read-only")\($0.isDefault ? " (default)" : "")\t\($0.source)"
    }
    try Output.emit(
      values, json: output.json,
      text: (["ID\tTITLE\tACCESS\tSOURCE"] + rows).joined(separator: "\n"))
  }
}

struct Sources: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "sources", abstract: "Discover calendar accounts.", subcommands: [SourceList.self],
    defaultSubcommand: SourceList.self)
  @OptionGroup var output: OutputOptions
}
struct SourceList: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list", abstract: "List account IDs for --source.")
  @OptionGroup var output: OutputOptions
  func run() throws {
    let values = try EventKitService().sources()
    try Output.emit(
      values, json: output.json,
      text: (["ID\tACCOUNT\tTYPE\tCREATE"]
        + values.map { "\($0.id)\t\($0.title)\t\($0.type)\t\($0.canCreateCalendars)" }).joined(
          separator: "\n"))
  }
}
struct CalendarCreate: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "create", abstract: "Create a calendar in a writable account.")
  @Argument var title: String
  @Option(help: "Account ID or unique name; default: system default account.") var source: String?
  @Option(help: "Calendar color: #RRGGBB.") var color: String?
  @Flag var dryRun = false
  @OptionGroup var output: OutputOptions
  func run() throws {
    if let color { _ = try CalendarColor.components(color) }
    try showCalendarMutation(
      EventKitService().createCalendar(title: title, source: source, color: color, dryRun: dryRun),
      output: output)
  }
}
struct CalendarUpdate: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "update", abstract: "Rename or recolor a calendar.")
  @Argument(help: "Calendar ID or unique exact name.") var id: String
  @Option var title: String?
  @Option var color: String?
  @Flag var dryRun = false
  @OptionGroup var output: OutputOptions
  func run() throws {
    if let color { _ = try CalendarColor.components(color) }
    try showCalendarMutation(
      EventKitService().updateCalendar(id: id, title: title, color: color, dryRun: dryRun),
      output: output)
  }
}
struct CalendarDelete: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "delete", abstract: "Delete a calendar AND ALL ITS EVENTS. Confirmation required.")
  @Argument(help: "Calendar ID or unique exact name.") var id: String
  @Flag(help: "Confirm deletion of the calendar and all its events.") var yes = false
  @Flag(help: "Preview without deleting the calendar or its events.") var dryRun = false
  @OptionGroup var output: OutputOptions
  func run() throws {
    let service = EventKitService()
    let prompt = try DeletePolicy.needsConfirmation(
      yes: yes, dryRun: dryRun, interactive: isatty(STDIN_FILENO) != 0)
    if prompt {
      let preview = try service.deleteCalendar(id: id, dryRun: true)
      Output.stderr("Delete calendar '\(preview.calendar.title)' AND ALL ITS EVENTS? [y/N] ")
      guard let reply = readLine(), ["y", "yes"].contains(reply.lowercased()) else {
        throw CLIError("CANCELLED", "Calendar deletion cancelled.")
      }
    }
    try showCalendarMutation(service.deleteCalendar(id: id, dryRun: dryRun), output: output)
  }
}
private func showCalendarMutation(_ value: CalendarMutation, output: OutputOptions) throws {
  let c = value.calendar
  let before = value.before.map { "\nBefore: \($0.title) \($0.color ?? "")" } ?? ""
  try Output.emit(
    value, json: output.json,
    text:
      "\(value.dryRun ? "Preview (not saved)" : "Completed"): calendar \(value.action)\(before)\n\(c.title)\t\(c.id)\t\(c.color ?? "")\t\(c.source)"
  )
}
