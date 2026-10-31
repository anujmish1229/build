// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RoomScanKit",
    platforms: [.iOS(.v16), .macOS(.v14)],
    products: [.library(name: "RoomScanKit", targets: ["RoomScanKit"])],
    targets: [
        .target(name: "RoomScanKit"),
        .testTarget(name: "RoomScanKitTests", dependencies: ["RoomScanKit"], resources: [.copy("Fixtures")]),
    ]
)
