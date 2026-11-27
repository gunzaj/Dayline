// swift-tools-version: 5.9
import PackageDescription

// Dayline builds with the Command Line Tools alone (no Xcode), so the
// package has no external dependencies and no XCTest target. `dayline-checks`
// is a plain executable that runs the same assertions `swift test` would.
let package = Package(
    name: "Dayline",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DaylineCore", targets: ["DaylineCore"]),
        .executable(name: "Dayline", targets: ["Dayline"]),
        .executable(name: "dayline-checks", targets: ["DaylineChecks"]),
    ],
    targets: [
        .target(name: "DaylineCore"),
        .executableTarget(name: "Dayline", dependencies: ["DaylineCore"]),
        .executableTarget(name: "DaylineChecks", dependencies: ["DaylineCore"]),
    ]
)
