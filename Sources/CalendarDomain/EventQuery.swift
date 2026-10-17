import Foundation

public enum EventQuery {
  public static func validate(
    limit: Int?, sort: String, query: String? = nil, attendees: [String] = []
  ) throws {
    if attendees.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
      throw CLIError.invalid("Attendee filter cannot be empty.")
    }
    if let limit, limit < 1 { throw CLIError.invalid("--limit must be at least 1.") }
    guard ["start", "title"].contains(sort) else {
      throw CLIError.invalid("--sort must be start or title.")
    }
    if let query, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw CLIError.invalid("Search query cannot be empty.")
    }
  }
  /// Input is ordered chronologically by the CalendarService.
  public static func apply(
    _ events: [EventInfo], excluded: Set<String> = [], noRecurring: Bool = false,
    query: String? = nil, sort: String = "start", limit: Int? = nil, attendees: [String] = []
  ) throws -> [EventInfo] {
    try validate(limit: limit, sort: sort, query: query, attendees: attendees)
    var result = events.filter { event in
      guard !excluded.contains(event.calendarID), !(noRecurring && event.recurring) else {
        return false
      }
      if !attendees.isEmpty {
        let participants = event.attendees + (event.organizer.map { [$0] } ?? [])
        guard attendees.contains(where: { term in participants.contains { $0.matches(term) } })
        else { return false }
      }
      guard let query else { return true }
      return [event.title, event.location ?? "", event.notes ?? ""].contains {
        $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
      }
    }
    if sort == "title" {
      result.sort { ($0.title.lowercased(), $0.id) < ($1.title.lowercased(), $1.id) }
    }
    if let limit { return Array(result.prefix(limit)) }
    return result
  }
}
