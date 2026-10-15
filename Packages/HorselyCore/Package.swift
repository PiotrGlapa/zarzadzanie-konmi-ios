// swift-tools-version: 6.0
import PackageDescription

// Czysty rdzeń: model, reguły, raporty, CSV, logika synchronizacji i format kopii. Bez UI, SQLite i sieci,
// bez zależności zewnętrznych (plan.md, R2) — testowany `swift test` bez symulatora.
let package = Package(
    name: "HorselyCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "HorselyCore", targets: ["HorselyCore"]),
    ],
    targets: [
        .target(
            name: "HorselyCore",
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(
            name: "HorselyCoreTests",
            dependencies: ["HorselyCore"],
            // `.copy` zachowuje strukturę katalogów (wiele plików o tej samej nazwie: parity/*/export.json).
            resources: [.copy("Resources")],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
    ]
)
