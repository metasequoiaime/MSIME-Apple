import Foundation

@MainActor final class SyntheticDictionaryAPI: DesktopCloudDictionaryAPI {
  var calls = 0
  var failure: Int?
  var lastRevision: Int64 = 0
  var lastExport: URL?
  func tick() throws { calls += 1; if let failure { throw BackendAccountClient.Failure(status: failure) } }
  func dictionary(_ kind: BackendAccountClient.DictionaryKind, search: String, offset: Int, token: String) async throws -> BackendAccountClient.DictionaryPage {
    try tick()
    return .init(entries: [.init(id: String(repeating: "a", count: 64), kind: kind, code: "synthetic", word: "合成", weight: 100, revision: 17)], has_more: offset == 0, offset: offset)
  }
  func addDictionary(_ kind: BackendAccountClient.DictionaryKind, value: BackendAccountClient.DictionaryValue, token: String) async throws -> BackendAccountClient.DictionaryChange {
    try tick(); return .init(revision: 18, previous: nil, replacement: nil)
  }
  func updateDictionary(_ entry: BackendAccountClient.DictionaryEntry, value: BackendAccountClient.DictionaryValue, token: String) async throws -> BackendAccountClient.DictionaryChange {
    try tick(); lastRevision = entry.revision; return .init(revision: 18, previous: nil, replacement: nil)
  }
  func deleteDictionary(_ entry: BackendAccountClient.DictionaryEntry, token: String) async throws -> BackendAccountClient.DictionaryChange {
    try tick(); lastRevision = entry.revision; return .init(revision: 19, previous: nil, replacement: nil)
  }
  func importDictionary(_ kind: BackendAccountClient.DictionaryKind, text: String, format: BackendAccountClient.DictionaryFileFormat, token: String) async throws -> BackendAccountClient.DictionaryImportResult {
    try tick(); return .init(imported: 1, revision: 20)
  }
  func exportDictionary(_ kind: BackendAccountClient.DictionaryKind, format: BackendAccountClient.DictionaryFileFormat, token: String) async throws -> URL {
    try tick()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("msime-export-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions:0o700])
    let file = root.appendingPathComponent("dictionary-" + kind.rawValue + ".tsv")
    let content = String(repeating: "synthetic\t合成\t100\n", count: 150_000).data(using: .utf8)!
    assert(FileManager.default.createFile(atPath: file.path, contents: content, attributes: [.posixPermissions:0o600]))
    lastExport = file
    return file
  }
}

@main enum DesktopCloudDictionaryProviderTest {
  @MainActor static func main() async throws {
    let api = SyntheticDictionaryAPI()
    var provider: BackendCloudDictionaryProvider? = .init(client: api, credentials: { "synthetic-token" })
    for kind in ["pinyin", "wubi", "quick", "english"] {
      let page = try await provider!.execute(["operation":"list", "kind":kind, "offset":100, "search":"合成"])
      assert(page["offset"] as? Int == 100 && page["has_more"] as? Bool == false)
    }
    _ = try await provider!.execute(["operation":"add", "kind":"quick", "code":"k2", "word":String(repeating:"界",count:199), "weight":100])
    _ = try await provider!.execute(["operation":"update", "kind":"pinyin", "id":String(repeating:"a",count:64), "revision":17, "code":"he'cheng", "word":"合成", "weight":100])
    assert(api.lastRevision == 17)
    _ = try await provider!.execute(["operation":"delete", "kind":"pinyin", "id":String(repeating:"a",count:64), "revision":18])
    assert(api.lastRevision == 18)
    for format in ["standard", "windows", "hans"] {
      _ = try await provider!.execute(["operation":"import", "kind":"pinyin", "format":format, "text":"he'cheng\t合成\t100\n"])
    }
    let before = api.calls
    for request: NSDictionary in [
      ["operation":"list","kind":"pinyin","offset":true,"search":""],
      ["operation":"list","kind":"pinyin","offset":0.5,"search":""],
      ["operation":"add","kind":"wubi","code":"abcde","word":"合成","weight":1],
      ["operation":"add","kind":"quick","code":"K2","word":"合成","weight":1],
      ["operation":"add","kind":"quick","code":"k2","word":String(repeating:"界",count:200),"weight":1],
      ["operation":"delete","kind":"pinyin","id":"bad/id","revision":17],
      ["operation":"delete","kind":"pinyin","id":String(repeating:"a",count:64),"revision":0],
      ["operation":"export","kind":"pinyin","format":"hans"],
      ["operation":"import","kind":"wubi","format":"hans","text":"合成"],
      ["operation":"import","kind":"pinyin","format":"standard","text":"bad\0"],
      ["operation":"token","kind":"pinyin"]
    ] {
      do { _ = try await provider!.execute(request); assertionFailure("invalid action accepted") } catch { }
    }
    assert(api.calls == before)
    api.failure = 409
    let conflict: NSDictionary = await withCheckedContinuation { continuation in
      _ = provider!.request(["operation":"delete","kind":"pinyin","id":String(repeating:"a",count:64),"revision":17]) { continuation.resume(returning:$0) }
    }
    assert(conflict["ok"] as? Bool == false && conflict["error"] as? String == "conflict")
    api.failure = nil
    let exported = try await provider!.execute(["operation":"export","kind":"pinyin","format":"standard"])
    assert(exported["text"] == nil)
    let descriptor = exported["export_file"] as! [String:Any]
    assert((descriptor["bytes"] as! NSNumber).intValue > 2 * 1024 * 1024)
    let oldFile = api.lastExport!
    _ = try await provider!.execute(["operation":"export","kind":"pinyin","format":"windows"])
    assert(!FileManager.default.fileExists(atPath: oldFile.path))
    let current = api.lastExport!
    provider = nil
    assert(!FileManager.default.fileExists(atPath: current.path))
    var identities = 0
    let changed = BackendCloudDictionaryProvider(client:api, credentials: {
      identities += 1; if identities > 1 { throw CancellationError() }; return "synthetic-token"
    })
    do { _ = try await changed.execute(["operation":"export","kind":"pinyin","format":"standard"]); assertionFailure("old account data exposed") } catch { }
    assert(!FileManager.default.fileExists(atPath: api.lastExport!.path))
    let missing = BackendCloudDictionaryProvider(client:api, credentials: { throw CancellationError() })
    let count = api.calls
    do { _ = try await missing.execute(["operation":"add","kind":"pinyin","code":"he","word":"合","weight":1]); assertionFailure("signed-out write") } catch { }
    assert(api.calls == count)
  }
}
