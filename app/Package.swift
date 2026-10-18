// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BigodinhoApple",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "BigodinhoApple",
            path: "Sources/BigodinhoApple"
        )
    ]
)
