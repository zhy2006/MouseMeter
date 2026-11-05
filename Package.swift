// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MouseMeter",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "MouseMeter",
            path: "Sources/MouseMeter",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "MouseMeterTests", dependencies: ["MouseMeter"]),
    ]
)
