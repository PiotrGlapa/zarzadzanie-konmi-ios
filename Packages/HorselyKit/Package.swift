// swift-tools-version: 6.0
import PackageDescription

// Wejście/wyjście: SQLite (GRDB), sieć, pliki, kopia zapasowa (ZIP), system. Zależności zewnętrzne uzasadnione w research R3 i R5.
let package = Package(
    name: "HorselyKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "HorselyKit", targets: ["HorselyKit"]),
    ],
    dependencies: [
        .package(path: "../HorselyCore"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", .upToNextMinor(from: "0.9.0")),
    ],
    targets: [
        .target(
            name: "HorselyKit",
            dependencies: [
                "HorselyCore",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(
            name: "HorselyKitTests",
            dependencies: [
                "HorselyKit",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            resources: [.copy("Resources")],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
    ]
)
