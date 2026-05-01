// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PriType",
    defaultLocalization: "ko",
    platforms: [
        .macOS(.v15)  // Tahoe or later (required for native Liquid Glass APIs)
    ],
    products: [
        .executable(
            name: "PriType",
            targets: ["PriType"]),
        .library(
            name: "PriTypeCore",
            targets: ["PriTypeCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Meapri/libhangul-swift", branch: "main"),
    ],
    targets: [
        .target(
            name: "PriTypeCore",
            dependencies: [
                .product(name: "LibHangul", package: "libhangul-swift")
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-strict-concurrency=complete"])
            ],
            linkerSettings: [
                .unsafeFlags(["-framework", "InputMethodKit"])
            ]
        ),
        .executableTarget(
            name: "PriType",
            dependencies: [
                "PriTypeCore",
                .product(name: "LibHangul", package: "libhangul-swift")
            ],
            linkerSettings: [
                .unsafeFlags(["-framework", "InputMethodKit"])
            ]
        ),
        .executableTarget(
            name: "PriTypeVerify",
            dependencies: ["PriTypeCore"]
        ),
        .testTarget(
            name: "PriTypeCoreTests",
            dependencies: ["PriTypeCore"]
        ),
        .executableTarget(
            name: "PriTypeBenchmark",
            dependencies: ["PriTypeCore"],
            linkerSettings: [
                .unsafeFlags(["-framework", "InputMethodKit"])
            ]
        )
    ]
)
