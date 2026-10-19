// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PipVoice",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "PipVoice", targets: ["PipVoice"])],
    targets: [.executableTarget(
        name: "PipVoice", path: "Sources/Pip",
        swiftSettings: [.swiftLanguageMode(.v5)],
        linkerSettings: [.linkedFramework("Carbon")]
    )]
)
