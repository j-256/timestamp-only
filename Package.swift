// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TimestampOnly",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "TimestampOnlyCore",
            targets: ["TimestampOnlyCore"]
        ),
        .executable(
            name: "TimestampOnly",
            targets: ["TimestampOnlyApp"]
        ),
        .executable(
            name: "TimestampOnlyLoginItem",
            targets: ["TimestampOnlyLoginItem"]
        ),
    ],
    targets: [
        .target(
            name: "TimestampOnlyCore",
            linkerSettings: [
                .linkedFramework("CoreServices"),
                .linkedFramework("UniformTypeIdentifiers"),
            ]
        ),
        .executableTarget(
            name: "TimestampOnlyApp",
            dependencies: ["TimestampOnlyCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "TimestampOnlyLoginItem",
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "TimestampOnlyCoreTests",
            dependencies: ["TimestampOnlyCore"]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
