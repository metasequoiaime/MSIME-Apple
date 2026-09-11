// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "MSIMESnapshot",
    platforms: [.macOS(.v13)],
    products: [.library(name: "MSIMESnapshot", targets: ["MSIMESnapshot"])],
    targets: [
        .target(name: "MSIMESnapshot", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "MSIMESnapshotTests", dependencies: ["MSIMESnapshot"])
    ]
)
