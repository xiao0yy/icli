import ArgumentParser
import CLICore
import CalendarCommands
import CalendarDomain
import Darwin
import EventKitCalendar
import Foundation

struct ICLI: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "icli", abstract: "Native macOS tools for people, scripts, and AI.",
    version: Version.current, subcommands: [Cal.self, Doctor.self])
  @OptionGroup var output: OutputOptions
}
struct Doctor: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Show runtime and permission diagnostics without requesting access.")
  @OptionGroup var output: OutputOptions
  struct Report: Codable {
    let version: String
    let macOS: String
    let executable: String
    let calendar: AuthInfo
  }
  func run() throws {
    let report = Report(
      version: Version.current, macOS: ProcessInfo.processInfo.operatingSystemVersionString,
      executable: CommandLine.arguments[0], calendar: EventKitService().authorization())
    try Output.emit(
      report, json: output.json,
      text:
        "icli \(report.version)\n\(report.macOS)\nExecutable: \(report.executable)\nCalendar access: \(report.calendar.status)"
    )
  }
}
@main enum Main {
  static func main() {
    // Allow the global output switch before or after any subcommand.
    let raw = Array(CommandLine.arguments.dropFirst())
    let separator = raw.firstIndex(of: "--") ?? raw.endIndex
    let json = raw[..<separator].contains("--json")
    var args = Array(raw[..<separator].filter { $0 != "--json" }) + Array(raw[separator...])
    if json {
      if let index = args.firstIndex(of: "--") {
        args.insert("--json", at: index)
      } else {
        args.append("--json")
      }
    }
    do {
      var command = try ICLI.parseAsRoot(args)
      try command.run()
    } catch let error as CLIError {
      Output.failure(error, json: json)
      Darwin.exit(error.exitCode)
    } catch {
      let parserCode = ICLI.exitCode(for: error)
      if parserCode == .success { ICLI.exit(withError: error) }
      let message = ICLI.message(for: error)
      if error is ValidationError || parserCode == .validationFailure {
        Output.failure(.invalid(message), json: json)
        Darwin.exit(2)
      }
      Output.failure(CLIError("EXECUTION_FAILED", message), json: json)
      Darwin.exit(1)
    }
  }
}
