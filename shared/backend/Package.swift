// swift-tools-version: 5.9
import PackageDescription
let package = Package(
  name: "MSIMEBackend", platforms: [.macOS(.v12), .iOS(.v15)],
  products: [.library(name: "MSIMEBackend", targets: ["MSIMEBackend"])],
  targets: [
    .target(name: "MSIMEBackend", path: ".", exclude: ["Tests", "README.md"], sources: ["BackendAccountClient.swift", "BackendAccountSession.swift", "BackendClipboardClient.swift"]),
    .testTarget(name: "MSIMEBackendTests", dependencies: ["MSIMEBackend"], path: "Tests")
  ])
