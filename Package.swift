// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BleWidget",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "BleWidget", targets: ["BleWidget"]),
    ],
    targets: [
        .target(name: "BleWidgetCore"),
        .executableTarget(
            name: "BleWidget",
            dependencies: ["BleWidgetCore"]
        ),
        .testTarget(
            name: "BleWidgetTests",
            dependencies: ["BleWidgetCore"]
        ),
    ]
)
