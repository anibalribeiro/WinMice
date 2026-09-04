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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0")
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
            dependencies: [
                "SwipeGesturePoster",
                "ScrollEngine",
                "SideButtons",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/WinMice",
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors"])
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
                // SwiftPM has no equivalent of Xcode's "Embed & Sign", and it does not add
                // a Frameworks rpath to executables. Without this the app links fine and
                // then dies at launch with a dyld "Library not loaded: @rpath/Sparkle.framework".
                // NOTE: the combined "-Wl,-rpath,PATH" form is rejected by this toolchain's
                // swiftc driver ("unknown argument"); -Xlinker pairs produce the identical
                // LC_RPATH and are accepted. See task-1-report.md for verification.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks"])
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
