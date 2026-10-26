// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DotDesk",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DotDesk",
            path: "Sources/DotDesk"
        ),
    ]
)
