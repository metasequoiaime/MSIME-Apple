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
      exclude: ["Package.swift"],
      sources: [
        "BackendAccountClient.swift",
        "BackendAccountSession.swift",
        "BackendCandidateClient.swift",
        "BackendClipboardClient.swift",
        "BackendCommunityResourceClient.swift",
        "BackendDictionaryClient.swift",
        "BackendPreferencesClient.swift",
        "BackendSnapshotClient.swift",
      ]
    )
  ]
)
