// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Glassine",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
        // swift-markdown's own manifest depends on swift-cmark by *branch*, so
        // SwiftPM refuses a version range here; pin the revision instead.
        .package(url: "https://github.com/swiftlang/swift-markdown.git",
                 revision: "27b7fc1a19068bcea3d2072db0ce86360d1400ed")
    ],
    targets: [
        .executableTarget(
            name: "Glassine",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Markdown", package: "swift-markdown")
            ],
            path: "Sources/Glassine",
            swiftSettings: [.unsafeFlags(["-Onone"], .when(configuration: .debug))],
            // `swift build` does not embed frameworks the way Xcode does, so
            // build.sh copies Sparkle.framework into Contents/Frameworks and
            // the binary needs an rpath pointing there.
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        )
    ]
)
