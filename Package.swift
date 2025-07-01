// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "SafeContinuation",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "SafeContinuation",
            targets: ["SafeContinuation"]),
    ],
    targets: [
        .target(
            name: "SafeContinuation"),
        .testTarget(
            name: "SafeContinuationTests",
            dependencies: ["SafeContinuation"]
        ),
    ]
)
