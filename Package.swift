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
        .executableTarget(
            name: "xxMac",
            dependencies: ["HotKey"],
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
    ]
)
