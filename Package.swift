// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "WeChatMulti",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // Pure, Foundation-only logic — fully unit-tested, no AppKit, no UI.
        // This is where the clone engine's bug-prone bits live: ps parsing,
        // slot ordering, version comparison, naming conventions, settings
        // persistence, and backup/restore.
        .target(
            name: "WeChatMultiCore",
            path: "Sources/WeChatMultiCore"
        ),
        // The menu bar app: AppKit/SwiftUI UI + filesystem orchestration that
        // composes WeChatMultiCore.
        .executableTarget(
            name: "WeChatMulti",
            dependencies: ["WeChatMultiCore"],
            path: "Sources/WeChatMulti"
        ),
        // Unit tests for the Core library — run via `swift test` on every CI push.
        .testTarget(
            name: "WeChatMultiCoreTests",
            dependencies: ["WeChatMultiCore"],
            path: "Tests/WeChatMultiCoreTests"
        )
    ]
)
