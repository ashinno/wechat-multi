// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "WeChatMulti",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "WeChatMulti",
            path: "Sources/WeChatMulti"
        )
    ]
)
