import Foundation

@main enum EmojiEmptyStateTest {
  static func main() {
    assert(MacEmojiEmptyState.message(category: "recent", search: "", group: "", hasRecents: false) == "Your recently used items will appear here")
    assert(MacEmojiEmptyState.message(category: "recent", search: "synthetic", group: "", hasRecents: false) == "Your recently used items will appear here")
    assert(MacEmojiEmptyState.message(category: "recent", search: "synthetic", group: "", hasRecents: true) == "No results")
    assert(MacEmojiEmptyState.message(category: "symbols", search: "", group: "", hasRecents: false) == "Symbol catalog not found")
    assert(MacEmojiEmptyState.message(category: "sticker", search: "", group: "", hasRecents: false) == "Stickers can be connected here")
    assert(MacEmojiEmptyState.message(category: "gif", search: "", group: "", hasRecents: false) == "GIF sources can be connected here")
    assert(MacEmojiEmptyState.message(category: "", search: "", group: "", hasRecents: false) == "No results")
    print("Emoji empty-state messages passed")
  }
}
