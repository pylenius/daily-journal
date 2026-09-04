// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JournalKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "JournalKit", targets: ["JournalKit"]),
    ],
    targets: [
        .target(name: "JournalKit"),
        .testTarget(
            name: "JournalKitTests",
            dependencies: ["JournalKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
