import Foundation

@objc(MSIMEClientSession) final class StubEmojiSession: NSObject {
  static var lastRequest: NSDictionary = [:]
  static var groups: Any = ["Z", "A"]
  static var symbolGroups: Any = [["parent": "P1", "title": "Shared"], ["parent": "P2", "title": "Shared"], ["parent": "P1", "title": "Other"]]
  @objc class func emojiCatalogRequest(_ request: NSDictionary) -> NSDictionary {
    lastRequest = request
    if request["list_groups"] as? Bool == true { return ["groups": groups] }
    if request["list_symbol_groups"] as? Bool == true { return ["symbol_groups": symbolGroups] }
    return ["items": [["text": "😀", "annotation": "笑脸", "group": "Smileys"]]]
  }
}

@main enum EmojiCatalogTest {
  static func main() throws {
    let rows = try MacEmojiCatalog.decode(["items": [
      ["text": "😀", "annotation": "笑脸 smile", "group": "Smileys"],
      ["text": "👨‍👩‍👧", "annotation": "家庭", "group": "People"]
    ]])
    assert(rows.count == 2 && rows[1].text == "👨‍👩‍👧")
    assert(rows[0].annotation == "笑脸 smile" && rows[0].group == "Smileys")
    let empty = try MacEmojiCatalog.decode(["items": []])
    assert(empty.isEmpty)
    for invalid: NSDictionary in [["error": "unavailable"], [:], ["items": [["text": "😀"]]],
                                 ["items": [["text": "", "annotation": "", "group": ""]]]] {
      do { _ = try MacEmojiCatalog.decode(invalid); assertionFailure("accepted invalid catalog") }
      catch {}
    }
    do { _ = try MacEmojiCatalog.load(resources: "relative", search: ""); assertionFailure("accepted relative path") }
    catch {}
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    do { _ = try MacEmojiCatalog.load(resources: directory.path, search: ""); assertionFailure("accepted missing resource") }
    catch {}
    try Data().write(to: directory.appendingPathComponent("others.db"))
    for category in ["", "kaomoji", "symbols"] {
      let loaded = try MacEmojiCatalog.load(resources: directory.path, search: "synthetic-keyword", category: category)
      assert(loaded.count == 1)
      assert(StubEmojiSession.lastRequest["category"] as? String == category)
      assert(StubEmojiSession.lastRequest["search"] as? String == "synthetic-keyword")
      assert(StubEmojiSession.lastRequest["limit"] as? Int == 255)
      assert(StubEmojiSession.lastRequest["offset"] as? Int == 0)
      _ = try MacEmojiCatalog.load(resources: directory.path, search: "synthetic-keyword", category: category, offset: 510)
      assert(StubEmojiSession.lastRequest["offset"] as? Int == 510)
      _ = try MacEmojiCatalog.load(resources: directory.path, search: "match", category: category, group: "Z")
      assert(StubEmojiSession.lastRequest["group"] as? String == "Z")
      let groups = try MacEmojiCatalog.loadGroups(resources: directory.path, category: category)
      assert(groups == ["Z", "A"])
      assert(StubEmojiSession.lastRequest["category"] as? String == category)
    }
    for invalid: Any in [[""], ["duplicate", "duplicate"], 123] {
      StubEmojiSession.groups = invalid
      do { _ = try MacEmojiCatalog.loadGroups(resources: directory.path, category: ""); assertionFailure("accepted invalid groups") }
      catch {}
    }
    let hierarchy = try MacEmojiCatalog.loadSymbolGroups(resources: directory.path)
    assert(MacEmojiSymbolGroup.parents(hierarchy) == ["P1", "P2"])
    assert(MacEmojiSymbolGroup.titles(hierarchy, parent: "") == ["Shared", "Other"])
    assert(MacEmojiSymbolGroup.titles(hierarchy, parent: "P2") == ["Shared"])
    assert(MacEmojiSymbolGroup.titles(hierarchy, parent: "missing").isEmpty)
    _ = try MacEmojiCatalog.load(resources: directory.path, search: "match", category: "symbols", group: "Shared", parent: "P2")
    assert(StubEmojiSession.lastRequest["parent"] as? String == "P2")
    StubEmojiSession.symbolGroups = [["parent": "", "title": "Invalid"]]
    do { _ = try MacEmojiCatalog.loadSymbolGroups(resources: directory.path); assertionFailure("accepted empty parent") }
    catch {}
    do { _ = try MacEmojiCatalog.load(resources: directory.path, search: "", offset: -1); assertionFailure("accepted negative offset") }
    catch {}
    print("Emoji catalog decoding checks passed")
  }
}
