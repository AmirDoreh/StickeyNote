// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StickeyNote",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "StickeyCore", targets: ["StickeyCore"]),
        .executable(name: "StickeyNote", targets: ["StickeyNote"])
    ],
    targets: [
        .target(name: "StickeyCore"),
        .executableTarget(name: "StickeyNote", dependencies: ["StickeyCore"], exclude: ["Integrations/README.md"]),
        .testTarget(name: "StickeyCoreTests", dependencies: ["StickeyCore"])
    ]
)
