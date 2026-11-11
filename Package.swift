// swift-tools-version:6.2
import PackageDescription

let package = Package(
  name: "OrionTerminal",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.99.3"),
  ],
  targets: [
    .executableTarget(
      name: "OrionTerminal",
      dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")],
      path: "Sources/OrionTerminal",
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .executableTarget(name: "orion", path: "Sources/orion", swiftSettings: [.swiftLanguageMode(.v5)]),
  ]
)
