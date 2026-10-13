// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIStudio",
    platforms: [
        .macOS("26.0") // 严格指定 macOS 26 Tahoe 专有特性
    ],
    products: [
        .executable(name: "AIStudio", targets: ["AIStudio"])
    ],
    targets: [
        .executableTarget(
            name: "AIStudio",
            path: "Sources/AIStudio"
        )
    ]
)
