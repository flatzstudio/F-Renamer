// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MultitrackCleaner",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MultitrackCleaner", targets: ["MultitrackCleaner"])
    ],
    targets: [
        .executableTarget(
            name: "MultitrackCleaner",
            exclude: ["App/Info.plist", "App/MultitrackCleaner.entitlements"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "MultitrackCleanerTests",
            dependencies: ["MultitrackCleaner"]
        )
    ]
)
