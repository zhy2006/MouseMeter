// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MouseMeter",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "MouseMeter",
            path: "Sources/MouseMeter",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
