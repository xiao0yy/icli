// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "icli",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "icli", targets: ["ICLI"])],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
  ],
  targets: [
    .target(name: "CalendarDomain"),
    .target(
      name: "CLICore",
      dependencies: [
        "CalendarDomain", .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]),
    .target(name: "EventKitCalendar", dependencies: ["CalendarDomain"]),
    .target(
      name: "CalendarCommands",
      dependencies: [
        "CalendarDomain", "CLICore", "EventKitCalendar",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]),
    .executableTarget(
      name: "ICLI",
      dependencies: [
        "CalendarCommands", "CLICore", "CalendarDomain", "EventKitCalendar",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]),
    .testTarget(
      name: "CalendarDomainTests",
      dependencies: ["CalendarDomain", "CalendarCommands", "CLICore", "EventKitCalendar"]),
  ]
)
