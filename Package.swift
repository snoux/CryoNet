// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "CryoNet",
    platforms: [.macOS(.v12),
                .iOS(.v13),
                .tvOS(.v12),
                .watchOS(.v4)],
    products: [
        .library(
            name: "CryoNet",
            targets: ["CryoNet"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.10.2"),
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", from: "5.0.2")
    ],
    targets: [
        .target(
            name: "CryoNet",
            dependencies: ["Alamofire", "SwiftyJSON"]
        ),
        .testTarget(
            name: "CryoNetTests",
            dependencies: ["CryoNet"]),
    ]
)

