import Foundation

@main enum EmojiEmptyStateTest {
  static func main() {
    assert(MacEmojiEmptyState.message(category: "recent", search: "", group: "") == "Your recently used items will appear here")
    assert(MacEmojiEmptyState.message(category: "recent", search: "synthetic", group: "") == "No results")
    assert(MacEmojiEmptyState.message(category: "symbols", search: "", group: "") == "Symbol catalog not found")
    assert(MacEmojiEmptyState.message(category: "sticker", search: "", group: "") == "Stickers can be connected here")
    assert(MacEmojiEmptyState.message(category: "gif", search: "", group: "") == "GIF sources can be connected here")
    assert(MacEmojiEmptyState.message(category: "", search: "", group: "") == "No results")
    print("Emoji empty-state messages passed")
  }
}
