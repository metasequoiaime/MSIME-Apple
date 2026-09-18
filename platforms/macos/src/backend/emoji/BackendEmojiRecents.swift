import AppKit

/// Per-panel memory only, matching the Windows 28-item MRU list.
struct MacEmojiRecents {
  private(set) var items: [MacEmojiCatalogItem] = []
  private(set) var revision = 0

  mutating func recordSelection(_ item: MacEmojiCatalogItem) {
    items.removeAll { $0.text == item.text }
    items.insert(item, at: 0)
    if items.count > 28 { items.removeLast(items.count - 28) }
    revision += 1
  }

  func matching(_ search: String) -> [MacEmojiCatalogItem] {
    guard !search.isEmpty else { return items }
    return items.filter {
      $0.text.localizedCaseInsensitiveContains(search) ||
      $0.annotation.localizedCaseInsensitiveContains(search) ||
      $0.group.localizedCaseInsensitiveContains(search)
    }
  }
}

enum MacEmojiClipboard {
  static func copy(_ text: String, to pasteboard: NSPasteboard = .general) -> Bool {
    guard !text.isEmpty, text.utf16.count <= 4096 else { return false }
    pasteboard.clearContents()
    return pasteboard.setString(text, forType: .string)
  }
}
