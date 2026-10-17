import ArgumentParser
import CalendarDomain
import Foundation

public struct OutputOptions: ParsableArguments {
  @Flag(help: "Emit a machine-readable JSON envelope.") public var json = false
  public init() {}
}
public enum Output {
  private struct Success<T: Encodable>: Encodable {
    let ok = true
    let data: T
  }
  private struct Failure: Encodable {
    let ok = false
    let error: Detail
    struct Detail: Encodable {
      let code: String
      let message: String
    }
  }
  private static func encode<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
  }
  public static func emit<T: Encodable>(_ value: T, json: Bool, text: String) throws {
    print(json ? try encode(Success(data: value)) : safe(text))
  }
  public static func failure(_ error: CLIError, json: Bool) {
    if json, let body = try? encode(Failure(error: .init(code: error.code, message: error.message)))
    {
      print(body)
    } else {
      stderr("\(error.code): \(error.message)\n")
    }
  }
  public static func stderr(_ text: String) {
    FileHandle.standardError.write(Data(safe(text).utf8))
  }
  // Prevent event titles/notes from injecting terminal escape sequences.
  public static func safe(_ text: String) -> String {
    String(text.unicodeScalars.filter { $0.value >= 32 || $0 == "\n" || $0 == "\t" })
  }
}
