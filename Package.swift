// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SmartTranslator",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SmartTranslatorCore"),
        .executableTarget(
            name: "SmartTranslator",
            dependencies: ["SmartTranslatorCore"]
        ),
        .testTarget(
            name: "SmartTranslatorTests",
            dependencies: ["SmartTranslatorCore"]
        ),
    ]
)
