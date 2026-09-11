import Foundation

// Each prepared object has a single owner; staging runs off the main thread,
// and only the finished result is handed back for main-thread publication.
final class MacPreparedLocalSnapshot: @unchecked Sendable {
  let context: NSDictionary
  let snapshot: BackendPreparedSnapshot
  let identifier = UUID().uuidString
  private var prepared: UInt64?
  private var stagingRoot: URL?
  init(context: NSDictionary, snapshot: BackendPreparedSnapshot) { self.context = context; self.snapshot = snapshot }
  static func invoke(_ selector: String, _ parameters: NSDictionary? = nil) throws -> NSDictionary {
    guard let type = NSClassFromString("MSIMEMacDictionarySync") as? NSObject.Type,
          let result = type.perform(NSSelectorFromString(selector), with: parameters)?.takeUnretainedValue() as? NSDictionary else {
      throw BackendAccountClient.Failure(status: 503)
    }
    if let error = result["error"] as? NSError { throw error }
    return result
  }
  func stage() throws {
    let stream = try BackendSnapshotRecordStream(snapshot: snapshot)
    let next: @convention(block) (AutoreleasingUnsafeMutablePointer<NSError?>?) -> NSDictionary? = { failure in
      do { return try stream.next().map { $0 as NSDictionary } }
      catch { failure?.pointee = error as NSError; return nil }
    }
    let versionResult = try Self.invoke("snapshotVersion:", context)
    guard let version = versionResult["version"] as? String else { throw BackendAccountClient.Failure(status: 409) }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("msime-snapshot-stage-" + identifier, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    stagingRoot = root
    let request: NSDictionary = ["options": context, "staging_root": root.path,
      "expected_version": version, "records": snapshot.envelope.records]
    let result = try Self.invoke("prepareSnapshot:", ["request": request, "nextRecord": next])
    guard let number = result["handle"] as? NSNumber else { throw BackendAccountClient.Failure(status: 500) }
    prepared = number.uint64Value
  }
  @MainActor func activate() throws {
    guard prepared != nil else { throw BackendAccountClient.Failure(status: 400) }
    throw BackendAccountClient.Failure(status: 501)
  }
  deinit {
    if let prepared { _ = try? Self.invoke("discardSnapshot:", ["handle": prepared]) }
    if let stagingRoot { try? FileManager.default.removeItem(at: stagingRoot) }
  }
}
