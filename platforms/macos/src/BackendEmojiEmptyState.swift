import SwiftUI

enum MacEmojiEmptyState {
  static func message(category: String, search: String, group: String) -> String {
    if category == "recent" { return search.isEmpty ? "Your recently used items will appear here" : "No results" }
    if category == "symbols" { return "Symbol catalog not found" }
    if category == "sticker" { return "Stickers can be connected here" }
    if category == "gif" { return "GIF sources can be connected here" }
    return search.isEmpty ? "No results" : "No results"
  }
}

struct MacEmojiEmptyStateView: View {
  let category: String
  let search: String
  let group: String
  let palette: MacEmojiPalette
  var body: some View {
    Text(MacEmojiEmptyState.message(category: category, search: search, group: group))
      .font(.system(size: category == "clipboard" ? 16 : 20))
      .foregroundStyle(MacEmojiPalette.color(palette.muted))
      .frame(maxWidth: .infinity, minHeight: 64, alignment: .center)
  }
}
