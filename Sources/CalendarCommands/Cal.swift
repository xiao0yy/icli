import ArgumentParser
import CLICore

public struct Cal: ParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "cal", abstract: "Read and manage Apple Calendar.",
    subcommands: [
      Auth.self, Sources.self, Calendars.self, Events.self, EventList.self, Today.self,
      Upcoming.self, Search.self, EventGet.self, EventCreate.self, EventUpdate.self,
      EventDelete.self,
    ])
  public init() {}
  @OptionGroup var output: OutputOptions
}
