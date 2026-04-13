// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AmphetamineXL",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "AmphetamineXL",
            path: "Sources/AmphetamineXL"
        ),
        .testTarget(
            name: "AmphetamineXLTests",
            dependencies: ["AmphetamineXL"],
            path: "Tests/AmphetamineXLTests"
        ),
    ]
)
