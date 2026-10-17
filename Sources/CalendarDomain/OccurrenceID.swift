import Foundation

/// Identifies one occurrence without depending on JSON dictionary key ordering.
public struct OccurrenceID: Codable, Equatable {
  public let identifier: String
  public let start: Double
  public let calendar: String
  public static let prefix = "icli-occ:"
  public init(identifier: String, start: Date, calendar: String) {
    self.identifier = identifier
    self.start = start.timeIntervalSince1970
    self.calendar = calendar
  }
  public func encoded() -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return Self.prefix + (try! encoder.encode(self)).base64EncodedString()
  }
  public static func decode(_ value: String) throws -> OccurrenceID {
    guard value.hasPrefix(prefix),
      let data = Data(base64Encoded: String(value.dropFirst(prefix.count))),
      let result = try? JSONDecoder().decode(Self.self, from: data), result.start.isFinite,
      !result.identifier.isEmpty, !result.calendar.isEmpty
    else {
      throw CLIError.invalid("Invalid occurrence ID.")
    }
    return result
  }
}
