// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Folio",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0")
    ],
    targets: [
        .executableTarget(
            name: "Folio",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Folio",
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
