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
            name: "FlashbackKit",
            // ブランド2色（Slate / Action-Orange）の Color Set。`Color(_:bundle:.module)` で参照する。
            // それ以外の色は semantic system color を使うため、ここに資産は増やさない。
            resources: [
                .process("Resources/Media.xcassets")
            ]
        ),
        .testTarget(
            name: "FlashbackKitTests",
            dependencies: ["FlashbackKit"]
        )
    ]
)
