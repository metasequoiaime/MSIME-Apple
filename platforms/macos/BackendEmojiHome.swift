import SwiftUI

struct MacEmojiHomeSection: Sendable {
  let title: String
  let category: String
  let items: [MacEmojiCatalogItem]
}

enum MacEmojiHomeCatalog {
  static func preview(groups: [[MacEmojiCatalogItem]], limit: Int, diverse: Bool) -> [MacEmojiCatalogItem] {
    guard limit > 0 else { return [] }
    if !diverse { return Array(groups.joined().prefix(limit)) }
    var result: [MacEmojiCatalogItem] = []
    for round in 0..<limit {
      var added = false
      for group in groups where round < group.count {
        result.append(group[round]); added = true
        if result.count == limit { return result }
      }
      if !added { break }
    }
    return result
  }

  static func load(search: String, groups: (String) throws -> [String],
    page: (String, String, Int) throws -> [MacEmojiCatalogItem]) throws -> [MacEmojiHomeSection] {
    try [("表情", "", 18), ("颜文字", "kaomoji", 15), ("符号", "symbols", 18)].map { title, category, limit in
      try Task.checkCancellation()
      if !search.isEmpty {
        return MacEmojiHomeSection(title: title, category: category, items: Array(try page(category, "", limit).prefix(limit)))
      }
      var collected: [[MacEmojiCatalogItem]] = []
      var count = 0
      for group in try groups(category) {
        try Task.checkCancellation()
        let items = try page(category, group, limit)
        if items.isEmpty { continue }
        collected.append(items)
        count += items.count
        if category == "symbols" ? collected.count >= limit : count >= limit { break }
      }
      return MacEmojiHomeSection(title: title, category: category,
        items: preview(groups: collected, limit: limit, diverse: category == "symbols"))
    }
  }
}

struct MacEmojiHomeView: View {
  let resources: String
  let search: String
  let recent: [MacEmojiCatalogItem]
  let palette: MacEmojiPalette
  let copy: (MacEmojiCatalogItem) -> Void
  let more: (String) -> Void
  @State private var sections: [MacEmojiHomeSection] = []
  @State private var loaded: [String] = []
  @State private var failed = false

  private func section(_ title: String, category: String, items: [MacEmojiCatalogItem], showMore: Bool) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(title).font(.headline)
        Spacer()
        if showMore { Button("更多") { more(category) }.accessibilityLabel("更多\(title)") }
      }
      if items.isEmpty { Text("没有匹配项").font(.caption) }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: category == "kaomoji" ? 5 : 6), spacing: 8) {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
          Button(item.text) { copy(item) }
            .font(category == "kaomoji" ? .body : .title2)
            .buttonStyle(MacEmojiCellStyle(palette: palette))
            .help([item.group, item.annotation].filter { !$0.isEmpty }.joined(separator: " · "))
            .accessibilityLabel(item.annotation.isEmpty ? item.text : item.annotation)
        }
      }
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if !recent.isEmpty { section("最近使用", category: "recent", items: recent, showMore: false) }
        if loaded == [resources, search] {
          ForEach(sections, id: \.category) { section($0.title, category: $0.category, items: $0.items, showMore: true) }
        } else {
          Text(failed ? "首页目录加载失败，请切换目录重试" : "正在加载首页…").font(.caption)
        }
      }
    }.task(id: [resources, search]) {
      loaded = []; sections = []; failed = false
      let directory = resources
      let query = search
      do {
        try await Task.sleep(nanoseconds: 200_000_000)
        let worker = Task.detached {
          try MacEmojiHomeCatalog.load(search: query, groups: {
            try MacEmojiCatalog.loadGroups(resources: directory, category: $0)
          }, page: { category, group, limit in
            try MacEmojiCatalog.load(resources: directory, search: query, category: category, group: group, limit: limit)
          })
        }
        let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
        try Task.checkCancellation()
        sections = result; loaded = [directory, query]
      } catch { if !Task.isCancelled { failed = true } }
    }
  }
}
