// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AmphetamineXL",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "AmphetamineXL",
            dependencies: [
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
            ],
            path: "Sources/AmphetamineXL"
        ),
        .testTarget(
            name: "AmphetamineXLTests",
            dependencies: ["AmphetamineXL"],
            path: "Tests/AmphetamineXLTests"
        ),
    ]
)
