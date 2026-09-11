// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "MSIMEBackend",
  platforms: [.macOS(.v12), .iOS(.v15)],
  products: [.library(name: "MSIMEBackend", targets: ["MSIMEBackend"])],
  targets: [
    .target(
      name: "MSIMEBackend",
      path: ".",
      exclude: ["Package.swift", "Tests"],
      sources: [
        "BackendAccountClient.swift",
        "BackendChatClient.swift",
        "BackendAccountSession.swift",
        "BackendCandidateClient.swift",
        "BackendClipboardClient.swift",
        "BackendCommunityResourceClient.swift",
        "BackendDictionaryClient.swift",
        "BackendPreferencesClient.swift",
        "BackendSkinArtworkClient.swift",
        "IOSPreferencePlan.swift",
        "BackendSnapshotClient.swift",
      ]
    ),
    .testTarget(
      name: "MSIMEBackendTests",
      dependencies: ["MSIMEBackend"],
      path: "Tests"
    )
  ]
)
