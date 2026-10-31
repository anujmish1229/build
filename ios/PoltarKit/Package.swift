// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PoltarKit",
    platforms: [.iOS(.v16), .macOS(.v14)],
    products: [.library(name: "PoltarKit", targets: ["PoltarKit"])],
    targets: [
        .target(name: "PoltarKit", resources: [.process("Resources")]),
        .testTarget(name: "PoltarKitTests", dependencies: ["PoltarKit"], resources: [.copy("Fixtures")]),
    ]
)
