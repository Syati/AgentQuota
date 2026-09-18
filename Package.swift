// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentQuota",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AgentQuota", targets: ["UsageBarNative"])
    ],
    targets: [
        .executableTarget(name: "UsageBarNative")
    ]
)
