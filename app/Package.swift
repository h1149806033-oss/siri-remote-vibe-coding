// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BossRemote",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BossRemote", targets: ["BossRemoteApp"]),
        .executable(name: "BossRemoteHCIService", targets: ["BossRemoteHCIService"]),
    ],
    targets: [
        .target(name: "BossRemoteHCIProtocol"),
        .executableTarget(
            name: "BossRemoteHCIService",
            dependencies: ["BossRemoteHCIProtocol"],
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        ),
        .target(
            name: "BossRemoteCore",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .target(
            name: "BossRemoteHID",
            dependencies: ["BossRemoteCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
            ]
        ),
        .target(
            name: "BossRemoteVoice",
            dependencies: ["BossRemoteCore", "BossRemoteHCIProtocol"],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
            ]
        ),
        .target(
            name: "BossRemoteUI",
            dependencies: ["BossRemoteCore"]
        ),
        .executableTarget(
            name: "BossRemoteApp",
            dependencies: [
                "BossRemoteCore",
                "BossRemoteHID",
                "BossRemoteUI",
                "BossRemoteHCIProtocol",
                "BossRemoteVoice",
            ],
            linkerSettings: [
                .linkedFramework("CoreBluetooth"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
