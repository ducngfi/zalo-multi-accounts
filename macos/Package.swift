// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ZaloProfiles",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "zalo-profiles", targets: ["zalo-profiles"]),
        .executable(name: "ZaloSwitcher", targets: ["ZaloSwitcher"]),
    ],
    targets: [
        .target(name: "ZaloProfilesCore"),
        .executableTarget(name: "zalo-profiles", dependencies: ["ZaloProfilesCore"]),
        .executableTarget(name: "ZaloSwitcher", dependencies: ["ZaloProfilesCore"]),
        .testTarget(name: "ZaloProfilesCoreTests", dependencies: ["ZaloProfilesCore"]),
    ]
)
