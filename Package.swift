// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ScreenPointer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ScreenPointer", path: "Sources/ScreenPointer")
    ]
)
