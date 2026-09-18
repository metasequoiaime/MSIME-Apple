import AppKit

@main enum EmojiRecentsTest {
  static func main() {
    var recent = MacEmojiRecents()
    assert(recent.items.isEmpty)
    for index in 0..<35 {
      recent.recordSelection(MacEmojiCatalogItem(text: "fixture-\(index)", annotation: "keyword", group: "fixture"))
    }
    assert(recent.items.count == 28)
    assert(recent.items.first?.text == "fixture-34")
    assert(recent.items.last?.text == "fixture-7")
    recent.recordSelection(MacEmojiCatalogItem(text: "fixture-10", annotation: "更新 updated", group: "new-group"))
    assert(recent.items.count == 28 && recent.items.first?.text == "fixture-10")
    assert(recent.items.filter { $0.text == "fixture-10" }.count == 1)
    assert(recent.matching("UPDATED").count == 1)
    assert(recent.matching("更新").count == 1)
    assert(recent.matching("new-group").count == 1)
    assert(recent.matching("fixture-10").count == 1)
    assert(recent.matching("missing").isEmpty)
    assert(recent.revision == 36)
    let clipboard = NSPasteboard.withUniqueName()
    defer { clipboard.releaseGlobally() }
    assert(MacEmojiClipboard.copy("😀👨‍👩‍👧", to: clipboard))
    assert(clipboard.string(forType: .string) == "😀👨‍👩‍👧")
    assert(!MacEmojiClipboard.copy("", to: clipboard))
    assert(!MacEmojiClipboard.copy(String(repeating: "x", count: 4097), to: clipboard))
    assert(clipboard.string(forType: .string) == "😀👨‍👩‍👧")
    print("Emoji recents and isolated clipboard checks passed")
  }
}
