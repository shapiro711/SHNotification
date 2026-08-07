// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SHNotification",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "SHNotificationKit",
            targets: ["SHNotificationKit"]
        ),
    ],
    targets: [
        .target(
            name: "SHNotificationKit",
            path: "Sources/SHNotificationKit",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "SHNotificationTests",
            dependencies: ["SHNotificationKit"],
            path: "Tests/SHNotificationTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)
