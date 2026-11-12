// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Galmuri",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Galmuri", targets: ["GalmuriApp"]),
               .executable(name: "GalmuriBridgeHost", targets: ["GalmuriBridgeHost"])],
    targets: [
        .target(name: "GalmuriCore"),
        .executableTarget(name: "GalmuriApp", dependencies: ["GalmuriCore"]),
        .executableTarget(name: "GalmuriBridgeHost", dependencies: ["GalmuriCore"]),
        .testTarget(name: "GalmuriCoreTests", dependencies: ["GalmuriCore"]),
        .testTarget(name: "GalmuriAppTests", dependencies: ["GalmuriApp", "GalmuriCore"])
    ]
)
