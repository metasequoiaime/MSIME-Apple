import Foundation

// Tauri only receives bounded metadata and queue state. Snapshot files stay in
// the app process or are copied into the App Group queue; no private path is
// returned to the WebView.
enum TauriDictionarySnapshotBridge {
  static let maximumRequestBytes = 8 * 1024

  static func request(_ data: Data) throws -> [String: Any] {
    guard data.count <= maximumRequestBytes,
          let action = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let operation = action["operation"] as? String else { throw Failure.invalid }
    switch operation {
    case "inspect":
      guard let path = action["path"] as? String else { throw Failure.invalid }
      return try inspect(URL(fileURLWithPath: path, isDirectory: false))
    case "enqueue":
      guard let path = action["path"] as? String,
            let accountID = action["accountId"] as? String,
            let cloudRevision = integer(action["cloudRevision"]),
            let expectedLocalVersion = action["expectedLocalVersion"] as? String,
            let fileSHA256 = action["fileSha256"] as? String else { throw Failure.invalid }
      let queue = DictionarySnapshotQueue()
      _ = try queue.enqueue(file: URL(fileURLWithPath: path, isDirectory: false),
                            accountID: accountID, cloudRevision: cloudRevision,
                            expectedLocalVersion: expectedLocalVersion, fileSHA256: fileSHA256)
      return try state(queue)
    case "state":
      return try state(DictionarySnapshotQueue())
    case "cancel":
      guard let accountID = action["accountId"] as? String, !accountID.isEmpty else { throw Failure.invalid }
      let queue = DictionarySnapshotQueue()
      try queue.cancel(accountID: accountID)
      return try state(queue)
    default:
      throw Failure.invalid
    }
  }

  private static func inspect(_ url: URL) throws -> [String: Any] {
    guard url.isFileURL else { throw Failure.invalid }
    let prepared = try BackendPreparedSnapshot(copying: url)
    return [
      "cloudRevision": prepared.envelope.revision,
      "sha256": prepared.envelope.sha256,
      "fileSha256": prepared.fileSHA256,
      "bytes": (try FileManager.default.attributesOfItem(atPath: prepared.url.path)[.size] as? NSNumber)?.uint64Value ?? 0,
      "records": prepared.envelope.records,
      "entries": prepared.envelope.entries,
      "overlays": prepared.envelope.overlays,
      "positions": prepared.envelope.positions,
      "selections": prepared.envelope.selections,
    ]
  }

  private static func state(_ queue: DictionarySnapshotQueue) throws -> [String: Any] {
    let value = try queue.read()
    var response: [String: Any] = [:]
    if let localVersion = value.localVersion { response["localVersion"] = localVersion }
    if let request = value.request {
      response["request"] = [
        "id": request.id.uuidString,
        "accountId": request.accountID,
        "cloudRevision": request.cloudRevision,
        "expectedLocalVersion": request.expectedLocalVersion,
        "fileSha256": request.fileSHA256,
        "status": request.status.rawValue,
      ]
    }
    return response
  }

  private static func integer(_ value: Any?) -> Int64? {
    guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
          let integer = Int64(value.stringValue) else { return nil }
    return integer
  }

  enum Failure: Error { case invalid }
}

private func tauriDictionarySnapshotError(_ error: Error) -> String {
  if case DictionarySnapshotQueue.Failure.busy = error { return "snapshot_busy" }
  if case DictionarySnapshotQueue.Failure.conflict = error { return "snapshot_conflict" }
  if case DictionarySnapshotQueue.Failure.invalid = error { return "snapshot_invalid" }
  if case DictionarySnapshotQueue.Failure.unavailable = error { return "snapshot_unavailable" }
  if let failure = error as? BackendAccountClient.Failure, failure.status == 400 { return "snapshot_invalid" }
  return "snapshot_unavailable"
}

private func tauriDictionarySnapshotResponse(_ document: [String: Any]) -> UnsafeMutablePointer<CChar>? {
  guard JSONSerialization.isValidJSONObject(document),
        let data = try? JSONSerialization.data(withJSONObject: document),
        data.count <= 128 * 1024,
        let text = String(data: data, encoding: .utf8) else { return nil }
  return text.withCString { strdup($0) }
}

@_cdecl("msime_ios_dictionary_snapshot_request")
func msimeIOSDictionarySnapshotRequest(_ request: UnsafePointer<UInt8>?, _ length: UInt) -> UnsafeMutablePointer<CChar>? {
  guard let request, length <= UInt(TauriDictionarySnapshotBridge.maximumRequestBytes) else { return nil }
  do {
    let value = try TauriDictionarySnapshotBridge.request(Data(bytes: request, count: Int(length)))
    return tauriDictionarySnapshotResponse(["ok": true, "value": value])
  } catch {
    return tauriDictionarySnapshotResponse(["ok": false, "error": tauriDictionarySnapshotError(error)])
  }
}

@_cdecl("msime_ios_dictionary_snapshot_string_free")
func msimeIOSDictionarySnapshotStringFree(_ value: UnsafeMutablePointer<CChar>?) {
  free(value)
}
