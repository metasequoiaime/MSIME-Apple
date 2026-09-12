import Foundation

@objc(MSIMEClientSession) final class StubEmojiSession: NSObject {
  static var lastRequest: NSDictionary = [:]
  @objc class func emojiCatalogRequest(_ request: NSDictionary) -> NSDictionary {
    lastRequest = request
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
    }
    print("Emoji catalog decoding checks passed")
  }
}
