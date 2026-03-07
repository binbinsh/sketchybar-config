// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "BatteryBluetooth",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "BatteryBluetooth",
            path: "Sources/BatteryBluetooth",
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("IOKit"),
                .linkedFramework("IOBluetooth")
            ]
        )
    ]
)
