// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "WeChatMulti",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "WeChatMulti",
            path: "Sources/WeChatMulti"
        )
    ]
)
