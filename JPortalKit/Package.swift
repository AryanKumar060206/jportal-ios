// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JPortalKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "JPortalKit", targets: ["JPortalKit"]),
    ],
    targets: [
        .target(name: "JPortalKit"),
        .testTarget(
            name: "JPortalKitTests",
            dependencies: ["JPortalKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
