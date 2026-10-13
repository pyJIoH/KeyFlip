// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyFlip",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "KeyFlip", targets: ["KeyFlip"])],
    targets: [
        .target(name: "KeyFlipCore"),
        .executableTarget(name: "KeyFlip", dependencies: ["KeyFlipCore"]),
        // A standalone runner also works with Apple's Command Line Tools, without Xcode/XCTest.
        .executableTarget(name: "KeyFlipCoreTests", dependencies: ["KeyFlipCore"], path: "Tests/KeyFlipCoreTests")
    ]
)
