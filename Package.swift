// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HytaleUIStudio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "HytaleUICore", targets: ["HytaleUICore"]),
        .library(name: "HytaleUIRender", targets: ["HytaleUIRender"]),
        .executable(name: "uivalidate", targets: ["HytaleUIValidate"]),
        .executable(name: "HytaleUIStudio", targets: ["HytaleUIStudioApp"])
    ],
    targets: [
        .target(
            name: "HytaleUICore"
        ),
        .target(
            name: "HytaleUIRender",
            dependencies: ["HytaleUICore"]
        ),
        .executableTarget(
            name: "HytaleUIValidate",
            dependencies: ["HytaleUICore", "HytaleUIRender"]
        ),
        .executableTarget(
            name: "HytaleUIStudioApp",
            dependencies: ["HytaleUICore", "HytaleUIRender"]
        ),
        .testTarget(
            name: "HytaleUICoreTests",
            dependencies: ["HytaleUICore"]
        )
    ]
)
