// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "xxMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "xxMac",
            targets: ["xxMac"]),
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.1.3")
    ],
    targets: [
        // Official Sparkle 2.10.1 SwiftPM artifact and checksum from its release manifest.
        .binaryTarget(
            name: "Sparkle",
            url: "https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-for-Swift-Package-Manager.zip",
            checksum: "4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a"
        ),
        .target(
            name: "TodoWidgetShared"
        ),
        .executableTarget(
            name: "xxMac",
            dependencies: ["HotKey", "TodoWidgetShared", "Sparkle"],
            exclude: ["Info.plist"], // Exclude from default build rules to avoid "forbidden resource" error
            resources: [],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/xxMac/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "xxMacTests",
            dependencies: ["xxMac"]
        ),
        .testTarget(
            name: "TodoWidgetSharedTests",
            dependencies: ["TodoWidgetShared"]
        ),
    ]
)
