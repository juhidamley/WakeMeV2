// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WakemeShared",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "WakemeShared",
            targets: ["WakemeShared"]
        ),
    ],
    targets: [
        .target(
            name: "WakemeShared",
            path: "Sources/WakemeShared"
        ),
    ]
)
