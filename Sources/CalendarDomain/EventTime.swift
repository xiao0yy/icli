import Foundation

public enum EventTime {
  public static func zone(_ name: String?) throws -> TimeZone {
    guard let name else { return .current }
    guard let zone = TimeZone(identifier: name) else {
      throw CLIError.invalid("Unknown timezone: \(name)")
    }
    return zone
  }
  private static func formatter(_ format: String, zone: TimeZone) -> DateFormatter {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.calendar = Calendar(identifier: .gregorian)
    f.timeZone = zone
    f.dateFormat = format
    f.isLenient = false
    return f
  }
  public static func day(_ text: String, zone: TimeZone) throws -> Date {
    let f = formatter("yyyy-MM-dd", zone: zone)
    guard text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
      let date = f.date(from: text), f.string(from: date) == text
    else {
      throw CLIError.invalid("Expected a valid date YYYY-MM-DD: \(text)")
    }
    return date
  }
  public static func instant(_ text: String, timezone: String?) throws -> Date {
    if text.range(of: #"(Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil {
      guard
        text.range(
          of:
            #"^\d{4}-\d{2}-\d{2}T([01]\d|2[0-3]):[0-5]\d(:[0-5]\d(\.\d{1,9})?)?(Z|[+-]([01]\d|2[0-3]):[0-5]\d)$"#,
          options: .regularExpression) != nil
      else {
        throw CLIError.invalid("Invalid ISO 8601 timestamp: \(text)")
      }
      // ISO8601DateFormatter normalizes impossible dates such as February 30.
      // Validate the wall date independently before interpreting its UTC offset.
      _ = try day(String(text.prefix(10)), zone: TimeZone(secondsFromGMT: 0)!)
      let suffixLength = text.hasSuffix("Z") ? 1 : 6
      let wallTime = String(text.dropLast(suffixLength))
      let parts = wallTime.split(separator: ".", maxSplits: 1)
      let wholeTime = String(parts[0])
      let normalized =
        (wholeTime.count == 16 ? wholeTime + ":00" : wholeTime)
        + text.suffix(suffixLength)
      let f = ISO8601DateFormatter()
      if let date = f.date(from: normalized) {
        // Foundation's fractional parser truncates to milliseconds. Add the
        // fraction to the exact whole second to retain Date's available precision.
        let fraction = parts.count == 2 ? Double("0." + parts[1])! : 0
        return date.addingTimeInterval(fraction)
      }
      throw CLIError.invalid("Invalid ISO 8601 timestamp: \(text)")
    }
    guard let timezone else {
      throw CLIError.invalid("Timestamp needs Z/UTC offset or --timezone: \(text)")
    }
    let zone = try zone(timezone)
    let format: String
    if text.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$"#, options: .regularExpression) != nil {
      format = "yyyy-MM-dd'T'HH:mm"
    } else if text.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$"#, options: .regularExpression)
      != nil
    {
      format = "yyyy-MM-dd'T'HH:mm:ss"
    } else {
      throw CLIError.invalid("Expected YYYY-MM-DDTHH:mm[:ss]: \(text)")
    }
    let f = formatter(format, zone: zone)
    guard let date = f.date(from: text), f.string(from: date) == text else {
      throw CLIError.invalid("Invalid or nonexistent local time: \(text)")
    }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = zone
    let components = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    let anchor = cal.startOfDay(for: date).addingTimeInterval(-1)
    let first = cal.nextDate(
      after: anchor, matching: components, matchingPolicy: .strict, repeatedTimePolicy: .first)
    let last = cal.nextDate(
      after: anchor, matching: components, matchingPolicy: .strict, repeatedTimePolicy: .last)
    guard first != nil, first == last else {
      throw CLIError.invalid("Ambiguous local time; supply an explicit UTC offset: \(text)")
    }
    return date
  }
  public static func parse(
    _ text: String, allDay: Bool, timezone: String?, fallbackZone: TimeZone = .current
  ) throws -> Date {
    allDay
      ? try day(text, zone: timezone.map { try zone($0) } ?? fallbackZone)
      : try instant(text, timezone: timezone)
  }
  public static func validate(start: Date, end: Date) throws {
    guard end > start else { throw CLIError.invalid("End must be later than start.") }
  }
  public static func range(
    from: String?, to: String?, timezone: String?, defaultDays: Int = 1, now: Date = Date()
  ) throws -> (Date, Date) {
    let zone = try zone(timezone)
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = zone
    func boundary(_ text: String) throws -> Date {
      if let offset = ["today": 0, "tomorrow": 1, "yesterday": -1][text.lowercased()] {
        return cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))!
      }
      return text.count == 10 ? try day(text, zone: zone) : try instant(text, timezone: timezone)
    }
    guard (1...365).contains(defaultDays) else {
      throw CLIError.invalid("--days must be between 1 and 365.")
    }
    let start = try from.map(boundary) ?? cal.startOfDay(for: now)
    let end = try to.map(boundary) ?? cal.date(byAdding: .day, value: defaultDays, to: start)!
    try validate(start: start, end: end)
    guard end.timeIntervalSince(start) <= 366 * 86400 else {
      throw CLIError.invalid("Query range cannot exceed 366 days.")
    }
    return (start, end)
  }
  public static func string(_ date: Date, allDay: Bool, zone: TimeZone) -> String {
    if allDay { return formatter("yyyy-MM-dd", zone: zone).string(from: date) }
    let f = ISO8601DateFormatter()
    f.timeZone = zone
    let seconds = date.timeIntervalSinceReferenceDate
    let whole = floor(seconds)
    let base = Date(timeIntervalSinceReferenceDate: whole)
    let timestamp = f.string(from: base)
    let fraction = seconds - whole
    guard fraction != 0 else { return timestamp }

    // Emit the shortest supported decimal that reconstructs the same Date.
    // This avoids both millisecond truncation and binary floating-point noise.
    var scale = 1.0
    for precision in 1...9 {
      scale *= 10
      let digits = Int((fraction * scale).rounded())
      if base.addingTimeInterval(Double(digits) / scale) == date || precision == 9 {
        let suffixLength = timestamp.hasSuffix("Z") ? 1 : 6
        return timestamp.dropLast(suffixLength) + "."
          + String(format: "%0*d", precision, digits) + timestamp.suffix(suffixLength)
      }
    }
    return timestamp
  }
}
