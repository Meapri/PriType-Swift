// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PriType",
    platforms: [
        .macOS(.v13)
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
        )
    ]
)
