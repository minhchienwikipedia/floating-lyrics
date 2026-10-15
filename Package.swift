// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FloatingLyrics",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "FloatingLyrics", path: "Sources/FloatingLyrics"),
        .executableTarget(name: "FloatingLyricsHelper", path: "Sources/FloatingLyricsHelper"),
    ],
    swiftLanguageModes: [.v5]
)
