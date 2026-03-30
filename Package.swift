// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ClaudePet",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudePet",
            resources: [
                .copy("Resources/default"),
                .copy("Resources/statusbar_icon.png"),
                .copy("Resources/statusbar_icon@2x.png"),
                .copy("Resources/jf-openhuninn-2.1.ttf"),
            ]
        )
    ]
)
