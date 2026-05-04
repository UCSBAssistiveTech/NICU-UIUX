// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NICUWebSocket",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "NICUWebSocket", targets: ["NICUWebSocket"]),
        .library(name: "NICUWebSocketServer", targets: ["NICUWebSocketServer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
    ],
    targets: [
        .target(name: "NICUWebSocket"),
        .target(
            name: "NICUWebSocketServer",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
            ]
        ),
        .testTarget(name: "NICUWebSocketTests", dependencies: ["NICUWebSocket"]),
    ]
)
