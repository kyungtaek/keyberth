// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "MicroCompanion", platforms: [.macOS(.v13)], products: [.executable(name: "MicroCompanion", targets: ["MicroCompanion"])], targets: [.target(name: "MicroCore"), .executableTarget(name: "MicroCompanion", dependencies: ["MicroCore"], resources: [.copy("Resources/keypad.png")]), .testTarget(name: "MicroCoreTests", dependencies: ["MicroCore"]), .testTarget(name: "MicroCompanionTests", dependencies: ["MicroCompanion"])])
