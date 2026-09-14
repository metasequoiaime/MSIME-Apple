import Foundation

protocol DesktopCloudDictionaryAPI {
  func dictionary(_ kind: BackendAccountClient.DictionaryKind, search: String, offset: Int, token: String) async throws -> BackendAccountClient.DictionaryPage
  func addDictionary(_ kind: BackendAccountClient.DictionaryKind, value: BackendAccountClient.DictionaryValue, token: String) async throws -> BackendAccountClient.DictionaryChange
  func updateDictionary(_ entry: BackendAccountClient.DictionaryEntry, value: BackendAccountClient.DictionaryValue, token: String) async throws -> BackendAccountClient.DictionaryChange
  func deleteDictionary(_ entry: BackendAccountClient.DictionaryEntry, token: String) async throws -> BackendAccountClient.DictionaryChange
  func importDictionary(_ kind: BackendAccountClient.DictionaryKind, text: String, format: BackendAccountClient.DictionaryFileFormat, token: String) async throws -> BackendAccountClient.DictionaryImportResult
  func exportDictionary(_ kind: BackendAccountClient.DictionaryKind, format: BackendAccountClient.DictionaryFileFormat, token: String) async throws -> URL
}
extension BackendAccountClient: DesktopCloudDictionaryAPI {}

/// Account credentials stay in the native actor. Only dictionary values and a
/// private, bounded export descriptor cross the authenticated desktop channel.
@MainActor @objc(MSIMEBackendCloudDictionaryProvider)
final class BackendCloudDictionaryProvider: NSObject {
  private let client: any DesktopCloudDictionaryAPI
  private let credentials: () async throws -> String
  private var exported: URL?
  init(client: any DesktopCloudDictionaryAPI, credentials: @escaping () async throws -> String) {
    self.client = client; self.credentials = credentials
  }
  deinit { if let exported { try? FileManager.default.removeItem(at: exported.deletingLastPathComponent()) } }

  @objc static func prepare(completion: @escaping (BackendCloudDictionaryProvider?) -> Void) {
    Task {
      do {
        guard let user = try await BackendAccountSession.shared.user() else { completion(nil); return }
        completion(BackendCloudDictionaryProvider(client: BackendAccountClient(), credentials: {
          try await BackendAccountSession.shared.credentials(matchingUserID: user.id).token
        }))
      } catch { completion(nil) }
    }
  }

  private static func number(_ value: Any?, minimum: Int64 = 0, maximum: Int64 = 9_007_199_254_740_991) throws -> Int64 {
    guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
          value.doubleValue.isFinite, value.doubleValue.rounded() == value.doubleValue,
          value.doubleValue >= Double(minimum), value.doubleValue <= Double(maximum) else { throw BackendAccountClient.Failure(status: 400) }
    return value.int64Value
  }
  private static func text(_ value: Any?, limit: Int, empty: Bool = false, multiline: Bool = false) throws -> String {
    guard let value = value as? String, (empty || !value.isEmpty), value.utf8.count <= limit,
          !value.unicodeScalars.contains(where: { $0.properties.generalCategory == .control && !(multiline && [9,10,13].contains($0.value)) }) else { throw BackendAccountClient.Failure(status: 400) }
    return value
  }
  private static func identity(_ value: Any?) throws -> String {
    let value = try text(value, limit: 64)
    guard value.utf8.count == 64, value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw BackendAccountClient.Failure(status: 400) }
    return value
  }
  private static func dictionaryValue(_ request: NSDictionary, kind: BackendAccountClient.DictionaryKind) throws -> BackendAccountClient.DictionaryValue {
    let maximum = kind == .wubi ? 4 : kind == .quick ? 32 : kind == .english ? 64 : 256
    let code = try text(request["code"], limit: maximum)
    let word = try text(request["word"], limit: 1024)
    guard code.utf8.allSatisfy({ byte in
      switch kind {
      case .pinyin: return (97...122).contains(byte) || byte == 39 || byte == 32
      case .wubi: return (97...122).contains(byte)
      case .quick: return (97...122).contains(byte) || (48...57).contains(byte)
      case .english: return (97...122).contains(byte) || (65...90).contains(byte)
      }
    }), kind != .quick || word.utf16.count <= 199 else { throw BackendAccountClient.Failure(status: 400) }
    return .init(code: code, word: word, weight: try number(request["weight"]))
  }
  private enum Action {
    case list(BackendAccountClient.DictionaryKind, Int, String)
    case add(BackendAccountClient.DictionaryKind, BackendAccountClient.DictionaryValue)
    case update(BackendAccountClient.DictionaryEntry, BackendAccountClient.DictionaryValue)
    case delete(BackendAccountClient.DictionaryEntry)
    case `import`(BackendAccountClient.DictionaryKind, BackendAccountClient.DictionaryFileFormat, String)
    case export(BackendAccountClient.DictionaryKind, BackendAccountClient.DictionaryFileFormat)
    @MainActor init(_ request: NSDictionary) throws {
      guard let name = request["kind"] as? String, let kind = BackendAccountClient.DictionaryKind(rawValue: name) else { throw BackendAccountClient.Failure(status: 400) }
      switch request["operation"] as? String {
      case "list": self = .list(kind, Int(try number(request["offset"], maximum: 1_000_000)), try text(request["search"], limit: 1024, empty: true))
      case "add": self = .add(kind, try dictionaryValue(request, kind: kind))
      case "update", "delete":
        let entry = BackendAccountClient.DictionaryEntry(id: try identity(request["id"]), kind: kind, code: "", word: "", weight: 0, revision: try number(request["revision"], minimum: 1))
        self = request["operation"] as? String == "delete" ? .delete(entry) : .update(entry, try dictionaryValue(request, kind: kind))
      case "import", "export":
        guard let name = request["format"] as? String, let format = BackendAccountClient.DictionaryFileFormat(rawValue: name),
              format != .hans || (kind == .pinyin && request["operation"] as? String == "import") else { throw BackendAccountClient.Failure(status: 400) }
        self = request["operation"] as? String == "export" ? .export(kind, format) : .import(kind, format, try text(request["text"], limit: 65536, multiline: true))
      default: throw BackendAccountClient.Failure(status: 400)
      }
    }
  }
  private func entry(_ value: BackendAccountClient.DictionaryEntry) throws -> [String: Any] {
    let id = try Self.identity(value.id)
    let code = try Self.text(value.code, limit: 256), word = try Self.text(value.word, limit: 1024)
    guard value.weight >= 0, value.revision > 0 else { throw BackendAccountClient.Failure(status: 0) }
    return ["id":id, "kind":value.kind.rawValue, "code":code, "word":word, "weight":value.weight, "revision":value.revision]
  }
  private func change(_ value: BackendAccountClient.DictionaryChange) throws -> [String: Any] {
    guard value.revision > 0 else { throw BackendAccountClient.Failure(status: 0) }
    return ["revision":value.revision, "previous":try value.previous.map(entry) as Any? ?? NSNull(), "replacement":try value.replacement.map(entry) as Any? ?? NSNull()]
  }
  func execute(_ request: NSDictionary) async throws -> [String: Any] {
    let action = try Action(request)
    let token = try await credentials()
    try Task.checkCancellation()
    var pendingExport: URL?
    defer { if let pendingExport { try? FileManager.default.removeItem(at: pendingExport.deletingLastPathComponent()) } }
    let result: [String: Any]
    switch action {
    case .list(let kind, let offset, let search):
      let page = try await client.dictionary(kind, search: search, offset: offset, token: token)
      guard page.entries.count <= 100, page.offset == offset, page.entries.allSatisfy({ $0.kind == kind }) else { throw BackendAccountClient.Failure(status: 0) }
      result = ["entries":try page.entries.map(entry), "offset":page.offset, "has_more":page.has_more]
    case .add(let kind, let value): result = try change(await client.addDictionary(kind, value: value, token: token))
    case .update(let entry, let value): result = try change(await client.updateDictionary(entry, value: value, token: token))
    case .delete(let entry): result = try change(await client.deleteDictionary(entry, token: token))
    case .import(let kind, let format, let text):
      let imported = try await client.importDictionary(kind, text: text, format: format, token: token)
      result = ["imported":imported.imported, "revision":imported.revision]
    case .export(let kind, let format):
      let file = try await client.exportDictionary(kind, format: format, token: token)
      guard file.isFileURL, file.lastPathComponent == "dictionary-" + kind.rawValue + ".tsv",
            file.deletingLastPathComponent().lastPathComponent.hasPrefix("msime-export-") else { throw BackendAccountClient.Failure(status: 0) }
      pendingExport = file
      let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
      guard let bytes = attributes[.size] as? NSNumber, bytes.int64Value <= 384 * 1024 * 1024 else { throw BackendAccountClient.Failure(status: 0) }
      result = ["export_file":["path":file.path, "bytes":bytes], "filename":file.lastPathComponent]
    }
    _ = try await credentials()
    try Task.checkCancellation()
    if let file = pendingExport {
      if let exported { try? FileManager.default.removeItem(at: exported.deletingLastPathComponent()) }
      exported = file; pendingExport = nil
    }
    return result
  }
  @objc func request(_ request: NSDictionary, completion: @escaping (NSDictionary) -> Void) -> Progress {
    let progress = Progress(totalUnitCount: 1)
    let task = Task {
      do { completion(["ok":true, "value":try await execute(request)]) }
      catch let failure as BackendAccountClient.Failure { completion(["ok":false, "error":failure.status == 409 ? "conflict" : "unavailable"]) }
      catch { completion(["ok":false, "error":"unavailable"]) }
      progress.completedUnitCount = 1; progress.cancellationHandler = nil
    }
    progress.cancellationHandler = { task.cancel() }
    return progress
  }
}
