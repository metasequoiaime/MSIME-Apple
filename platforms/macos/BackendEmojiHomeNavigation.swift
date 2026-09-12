import Foundation

struct MacEmojiHomeKey: Hashable {
  let category: String
  let text: String
  let group: String
  var occurrence: Int = 0
}

struct MacEmojiHomeEntry {
  let key: MacEmojiHomeKey
  let item: MacEmojiCatalogItem
  let row: Int
  let center: Double
}

enum MacEmojiHomeNavigation {
  static func key(category: String, items: [MacEmojiCatalogItem], index: Int) -> MacEmojiHomeKey {
    let item = items[index]
    let occurrence = items.prefix(index).filter { $0.text == item.text && $0.group == item.group }.count
    return MacEmojiHomeKey(category: category, text: item.text, group: item.group, occurrence: occurrence)
  }
  /// Reset selects the first visible item, including before asynchronous catalog arrival.
  /// A removed explicit selection stays stale: activation must not copy a different item.
  static func selection(_ selected: MacEmojiHomeKey?, sections: [MacEmojiHomeSection]) -> MacEmojiHomeKey? {
    if let selected { return selected }
    for section in sections {
      if let item = section.items.first {
        return MacEmojiHomeKey(category: section.category, text: item.text, group: item.group)
      }
    }
    return nil
  }

  static func entries(_ sections: [MacEmojiHomeSection], flowCells: [MacEmojiFlowCell]) -> [MacEmojiHomeEntry] {
    var result: [MacEmojiHomeEntry] = []
    var row = 0
    for section in sections {
      let flow = section.category == "kaomoji"
      let columns = MacEmojiGridMetrics.columns
      for (index, item) in section.items.enumerated() {
        if flow && !flowCells.indices.contains(index) { continue }
        result.append(MacEmojiHomeEntry(
          key: key(category: section.category, items: section.items, index: index),
          item: item, row: row + (flow ? flowCells[index].row : index / columns),
          center: flow ? Double(flowCells[index].rect.midX) : (Double(index % columns) + 0.5) / Double(columns)))
      }
      row += flow ? (flowCells.last.map { $0.row + 1 } ?? 0) : (section.items.count + columns - 1) / columns
    }
    return result
  }

  static func destination(_ command: MacEmojiGridCommand, selected: MacEmojiHomeKey?, entries: [MacEmojiHomeEntry]) -> MacEmojiHomeEntry? {
    guard !entries.isEmpty else { return nil }
    if command == .home { return entries.first }
    if command == .end { return entries.last }
    guard let index = entries.firstIndex(where: { $0.key == selected }) else {
      return command == .activate ? nil : entries.first
    }
    switch command {
    case .left: return entries[max(0, index - 1)]
    case .right: return entries[min(entries.count - 1, index + 1)]
    case .activate: return entries[index]
    case .up, .down:
      let current = entries[index]
      // Windows uses a flat six-cell stride outside flow-layout sections.
      guard current.key.category == "kaomoji" else {
        let stride = MacEmojiGridMetrics.columns
        return entries[max(0, min(entries.count - 1, index + (command == .up ? -stride : stride)))]
      }
      // Preserve flow navigation's section boundary and nearest horizontal center.
      let nextRow = current.row + (command == .up ? -1 : 1)
      return entries.filter { $0.key.category == current.key.category && $0.row == nextRow }.min {
        abs($0.center - current.center) < abs($1.center - current.center)
      } ?? current
    case .home, .end: return nil
    }
  }
}
