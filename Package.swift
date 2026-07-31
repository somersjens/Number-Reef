// swift-tools-version: 6.0
//
//  Package.swift
//  Elephant Challenge: Math Memory
//
//  A test harness over the app's pure-logic `Core` folder. The very same files
//  are compiled into the iOS app by the Xcode project's synchronized group, so
//  there is nothing to keep in sync — `swift test` exercises the exact code
//  that ships.
//
//  The app target compiles these files in Swift 5 language mode, so the test
//  harness uses it too; otherwise the two would disagree on isolation rules.
//

import PackageDescription

let package = Package(
    name: "ElephantChallengeCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ElephantChallengeCore", targets: ["ElephantChallengeCore"])
    ],
    targets: [
        .target(
            name: "ElephantChallengeCore",
            path: "Elephant Challenge/Core",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ElephantChallengeCoreTests",
            dependencies: ["ElephantChallengeCore"],
            path: "Tests/ElephantChallengeCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
