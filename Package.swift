// swift-tools-version: 6.0
//
// Three targets, layered so the rules can be tested without a window or a
// socket:
//
//   EagleBoardsCore   records, the CSV files, the board rules and every
//                     lifecycle step. No UI, no server.
//   CheckInServer     the small web server the sign-in tablets talk to. It
//                     serves the sign-in pages and nothing an operator uses.
//   EagleBoards       the SwiftUI app: scheduler, records and settings.

import PackageDescription

let package = Package(
    name: "EagleBoards",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "EagleBoards", targets: ["EagleBoards"])
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.27.0")
    ],
    targets: [
        .target(
            name: "EagleBoardsCore"
        ),
        .target(
            name: "CheckInServer",
            dependencies: [
                "EagleBoardsCore",
                .product(name: "Hummingbird", package: "hummingbird")
            ],
            resources: [
                .copy("Resources/CheckIn")
            ]
        ),
        .executableTarget(
            name: "EagleBoards",
            dependencies: [
                "EagleBoardsCore",
                "CheckInServer"
            ]
        ),
        .testTarget(
            name: "EagleBoardsCoreTests",
            dependencies: ["EagleBoardsCore"],
            resources: [
                // The rule and auto-select cases all three versions share
                // (SPEC.md D-5), pinned by test-cases.lock.
                .copy("Resources/cases")
            ]
        ),
        .testTarget(
            name: "CheckInServerTests",
            dependencies: [
                "CheckInServer",
                "EagleBoardsCore",
                .product(name: "HummingbirdTesting", package: "hummingbird")
            ]
        )
    ]
)
