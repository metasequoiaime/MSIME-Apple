import Foundation

@MainActor
enum MacCloudFileTransfer {
  static func save(_ file: URL, to destination: URL, authorize: () async throws -> Void) async throws {
    guard file.isFileURL, destination.isFileURL else { throw BackendAccountClient.Failure(status: 400) }
    try await authorize()
    let scoped = destination.startAccessingSecurityScopedResource()
    defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
    let temporary = destination.deletingLastPathComponent().appendingPathComponent("." + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let copy = Task.detached(priority: .utility) {
      try Task.checkCancellation()
      try FileManager.default.copyItem(at: file, to: temporary)
      try Task.checkCancellation()
    }
    try await withTaskCancellationHandler(operation: { try await copy.value }, onCancel: { copy.cancel() })
    try await authorize()
    if FileManager.default.fileExists(atPath: destination.path) { _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary) }
    else { try FileManager.default.moveItem(at: temporary, to: destination) }
  }
}
