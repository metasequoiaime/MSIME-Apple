import Foundation

// Each prepared object has a single owner; staging runs off the main thread,
// and only the finished result is handed back for main-thread publication.
final class MacPreparedLocalSnapshot: @unchecked Sendable {
  let context: NSDictionary
  let snapshot: BackendPreparedSnapshot
  let identifier = UUID().uuidString
  private var prepared: NSObject?
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
    let result = try Self.invoke("prepare:", ["context": context, "identifier": identifier,
      "maximumRecords": snapshot.envelope.records, "nextRecord": next])
    guard let object = result["prepared"] as? NSObject else { throw BackendAccountClient.Failure(status: 500) }
    prepared = object
  }
  @MainActor func activate() throws {
    guard let prepared, let version = context["version"] as? String else { throw BackendAccountClient.Failure(status: 400) }
    _ = try Self.invoke("activate:", ["prepared": prepared, "version": version])
  }
  deinit {
    if prepared != nil, let user = context["user"] as? URL {
      _ = try? Self.invoke("discard:", ["identifier": identifier, "user": user])
    }
  }
}
