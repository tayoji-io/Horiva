// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Horiva", platforms: [.macOS(.v13)], products: [.executable(name: "Horiva", targets: ["Horiva"])], targets: [.target(name: "ClockCore"), .executableTarget(name: "Horiva", dependencies: ["ClockCore"]), .testTarget(name: "ClockCoreTests", dependencies: ["ClockCore"])])
