// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlashbackKit",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "FlashbackKit",
            targets: ["FlashbackKit"]
        )
    ],
    // 依存ゼロ方針: Firebase / Alamofire / Rx を入れない
    targets: [
        .target(
            name: "FlashbackKit"
        ),
        .testTarget(
            name: "FlashbackKitTests",
            dependencies: ["FlashbackKit"]
        )
    ]
)
