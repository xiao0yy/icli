import ArgumentParser
import CLICore
import EventKitCalendar

struct Auth: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Calendar authorization.", subcommands: [AuthStatus.self, AuthRequest.self])
  @OptionGroup var output: OutputOptions
}
struct AuthStatus: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "status", abstract: "Show access status without prompting.")
  @OptionGroup var output: OutputOptions
  func run() throws {
    let value = EventKitService().authorization()
    try Output.emit(value, json: output.json, text: "Calendar access: \(value.status)")
  }
}
struct AuthRequest: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "request", abstract: "Request full calendar access through macOS.")
  @OptionGroup var output: OutputOptions
  func run() throws {
    let value = try EventKitService().requestAccess()
    try Output.emit(value, json: output.json, text: "Calendar access: \(value.status)")
  }
}
