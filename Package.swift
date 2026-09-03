// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WinMice",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WinMice", targets: ["WinMice"])
    ],
    targets: [
        .target(
            name: "SwipeGesturePoster",
            path: "Sources/SwipeGesturePoster",
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors"])
            ],
            linkerSettings: [
                .linkedFramework("ApplicationServices")
            ]
        ),
        .target(
            name: "ScrollEngine",
            path: "Sources/ScrollEngine",
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors"])
            ]
        ),
        .target(
            name: "SideButtons",
            path: "Sources/SideButtons",
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors"])
            ]
        ),
        .executableTarget(
            name: "WinMice",
            dependencies: ["SwipeGesturePoster", "ScrollEngine", "SideButtons"],
            path: "Sources/WinMice",
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors"])
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "SwipeGesturePosterTests",
            dependencies: ["SwipeGesturePoster"],
            path: "Tests/SwipeGesturePosterTests",
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "ScrollEngineTests",
            dependencies: ["ScrollEngine"],
            path: "Tests/ScrollEngineTests"
        ),
        .testTarget(
            name: "SideButtonsTests",
            dependencies: ["SideButtons"],
            path: "Tests/SideButtonsTests"
        )
    ]
)
