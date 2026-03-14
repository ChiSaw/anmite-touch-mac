// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AnmiteTouchMac",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "TouchMonitorPOC",
            targets: ["TouchMonitorPOC"]
        ),
        .executable(
            name: "touch-monitor-cli",
            targets: ["TouchMonitorCLI"]
        ),
        .executable(
            name: "TouchMonitorMenuBarApp",
            targets: ["TouchMonitorMenuBarApp"]
        ),
    ],
    targets: [
        .target(
            name: "TouchMonitorPOC"
        ),
        .executableTarget(
            name: "TouchMonitorCLI",
            dependencies: ["TouchMonitorPOC"]
        ),
        .executableTarget(
            name: "TouchMonitorMenuBarApp",
            dependencies: ["TouchMonitorPOC"]
        ),
        .testTarget(
            name: "TouchMonitorPOCTests",
            dependencies: ["TouchMonitorPOC"]
        ),
    ]
)
