import AppKit
import SwiftUI

struct MacEmojiView: View {
  let resources: String
  let preferencesDirectory: String
  @ObservedObject var appearance = MacEmojiAppearance.shared
  @Environment(\.colorScheme) private var systemColorScheme
  private var palette: MacEmojiPalette {
    MacEmojiPalette(light: (appearance.colorScheme ?? systemColorScheme) == .light)
  }
  @State private var search = ""
  @State private var category = ""
  private var usesWideCells: Bool { category == "kaomoji" || category == "recent" || category == "clipboard" }
  private var columns: Int { category == "clipboard" ? 1 : usesWideCells ? 3 : 8 }
  @State private var group = ""
  @State private var parent = ""
  @State private var symbolGroups: [MacEmojiSymbolGroup] = []
  private var displayedGroups: [String] {
    category == "symbols" ? MacEmojiSymbolGroup.titles(symbolGroups, parent: parent) : groups
  }
  @State private var groups: [String] = []
  @State private var groupsCategory: String?
  @State private var groupsFailed = false
  @State private var offset = 0
  @State private var selectedIndex = 0
  @State private var recent = MacEmojiRecents()
  @State private var clipboardNotice = ""
  @State private var historyRevision = 0
  @State private var deletingHistory = false
  @State private var deletionNotice = ""
  @State private var loadedQuery: [String] = []
  private var queryID: [String] { [search, category, parent, group, String(offset), String(category == "recent" ? recent.revision : 0), String(category == "clipboard" ? historyRevision : 0)] }
  @State private var items: [MacEmojiCatalogItem] = []
  @State private var status = "正在加载…"
  @State private var selection = MacEmojiSelectionState()
  var onSelect: (String) -> Bool
  var copyText: (String) -> Bool = { MacEmojiClipboard.copy($0) }

  private func copyItem(_ item: MacEmojiCatalogItem) {
    if category != "clipboard" { recent.recordSelection(item) }
    if copyText(item.text) {
      clipboardNotice = "已复制到剪贴板"
    } else {
      clipboardNotice = "无法访问剪贴板，请重试"
    }
  }

  private func removeHistory(_ text: String) {
    guard !deletingHistory else { return }
    deletingHistory = true
    deletionNotice = ""
    let directory = preferencesDirectory
    let requestedID = queryID
    Task {
      defer { deletingHistory = false }
      do {
        let removed = try await Task.detached {
          try MacEmojiClipboardHistory.remove(directory: directory, text: text)
        }.value
        guard queryID == requestedID else { return }
        historyRevision += 1
        deletionNotice = removed ? "已删除历史记录（不会清空系统剪贴板）" : "记录已不存在"
      } catch {
        guard queryID == requestedID else { return }
        deletionNotice = "无法删除历史记录，请重试"
      }
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("表情与符号").font(.title2)
      Picker("目录", selection: $category) {
        Text("最近").tag("recent")
        Text("表情").tag("")
        Text("颜文字").tag("kaomoji")
        Text("符号").tag("symbols")
        Text("剪贴板").tag("clipboard")
      }.pickerStyle(.segmented)
      if category == "symbols" {
        Picker("符号大类", selection: $parent) {
          Text("全部大类").tag("")
          ForEach(MacEmojiSymbolGroup.parents(symbolGroups), id: \.self) { Text($0).tag($0) }
        }.disabled(groupsCategory != category || symbolGroups.isEmpty)
      }
      Picker("分类", selection: $group) {
        Text("全部分类").tag("")
        ForEach(groupsCategory == category ? displayedGroups : [], id: \.self) { name in
          Text(name).tag(name)
        }
      }.disabled(groupsCategory != category || displayedGroups.isEmpty)
      if groupsFailed { Text("分类加载失败，仍可浏览全部或搜索").font(.caption).foregroundStyle(MacEmojiPalette.color(palette.muted)) }
      MacEmojiSearchField(text: $search,
        placeholder: category == "clipboard" ? "搜索剪贴板历史" : category == "kaomoji" ? "搜索颜文字" : category == "symbols" ? "搜索符号" : "搜索表情",
        palette: palette)
      if category == "clipboard" {
        HStack {
          Text("仅显示已保存记录，不采集系统剪贴板").font(.caption)
          Spacer()
          Button("刷新") { historyRevision += 1 }
        }
        if !deletionNotice.isEmpty { Text(deletionNotice).font(.caption) }
      }
      Text(status).font(.caption).foregroundStyle(MacEmojiPalette.color(palette.muted))
      if !clipboardNotice.isEmpty { Text(clipboardNotice).font(.caption) }
      if selection.rejected {
        Text(MacEmojiSelectionState.failureMessage).font(.caption)
          .foregroundStyle(MacEmojiPalette.color(palette.text))
      }
      HStack {
        Button("上一页") { offset = max(0, offset - 255) }.disabled(offset == 0)
        Spacer()
        Text("第 \(offset / 255 + 1) 页").font(.caption)
        Spacer()
        Button("下一页") { offset += 255 }
          .disabled(category == "recent" || category == "clipboard" || loadedQuery != queryID || items.isEmpty || offset > Int.max - 255)
      }
      ScrollViewReader { proxy in
        VStack(spacing: 4) {
          MacEmojiKeyboardEntry(enabled: loadedQuery == queryID && !items.isEmpty) { command in
            if command == .activate && !items.indices.contains(selectedIndex) { return }
            guard loadedQuery == queryID,
                  let index = command.destination(from: selectedIndex, count: items.count, columns: columns) else { return }
            selectedIndex = index
            proxy.scrollTo(index)
            if case .activate = command { copyItem(items[index]) }
          }.frame(height: 24)
          ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: columns), spacing: 8) {
              ForEach(Array((loadedQuery == queryID ? items : []).enumerated()), id: \.offset) { index, item in
                HStack {
                Button(item.text) { selectedIndex = index; copyItem(item) }
                  .font(usesWideCells ? .body : .title2)
                  .lineLimit(category == "clipboard" ? 3 : nil)
                  .buttonStyle(MacEmojiCellStyle(palette: palette, selected: selectedIndex == index))
                  .id(index)
                  .help([item.group, item.annotation].filter { !$0.isEmpty }.joined(separator: " · "))
                  .accessibilityLabel(item.annotation.isEmpty ? item.text : item.annotation)
                  if category == "clipboard" {
                    Spacer(minLength: 4)
                    Button { removeHistory(item.text) } label: { Image(systemName: "trash") }
                      .buttonStyle(.plain)
                      .accessibilityLabel("删除此条历史记录")
                      .help("删除此条历史记录，不会清空系统剪贴板")
                      .disabled(deletingHistory)
                  }
                }
              }
            }
          }
        }
      }
      Button("插入所选项") {
        guard loadedQuery == queryID, items.indices.contains(selectedIndex) else { return }
        selection.submit(items[selectedIndex].text, send: onSelect)
      }.disabled(loadedQuery != queryID || !items.indices.contains(selectedIndex))
    }.padding(20).frame(minWidth: 380, minHeight: 500)
      .background(MacEmojiPalette.color(palette.background))
      .foregroundStyle(MacEmojiPalette.color(palette.text))
      .tint(MacEmojiPalette.color(palette.accent))
      .preferredColorScheme(appearance.colorScheme)
      .onChange(of: search) { _ in offset = 0 }
      .onChange(of: category) { _ in offset = 0; group = ""; parent = ""; clipboardNotice = "" }
      .onChange(of: parent) { _ in offset = 0; group = "" }
      .onChange(of: group) { _ in offset = 0 }
      .task(id: category) {
        groupsCategory = nil
        groups = []
        symbolGroups = []
        groupsFailed = false
        let selectedCategory = category
        let directory = resources
        if selectedCategory == "recent" || selectedCategory == "clipboard" { groupsCategory = selectedCategory; return }
        do {
          if selectedCategory == "symbols" {
            let result = try await Task.detached { try MacEmojiCatalog.loadSymbolGroups(resources: directory) }.value
            try Task.checkCancellation()
            symbolGroups = result
            groupsCategory = selectedCategory
            return
          }
          let result = try await Task.detached {
            try MacEmojiCatalog.loadGroups(resources: directory, category: selectedCategory)
          }.value
          try Task.checkCancellation()
          groups = result
          groupsCategory = selectedCategory
        } catch {
          guard !Task.isCancelled else { return }
          groupsFailed = true
        }
      }
      .task(id: queryID) {
        items = []
        selectedIndex = 0
        loadedQuery = []
        status = "正在加载…"
        if category == "recent" {
          items = Array(recent.matching(search).dropFirst(offset).prefix(255))
          loadedQuery = queryID
          status = items.isEmpty ? "最近使用为空或没有匹配项" : "本页 \(items.count) 项"
          return
        }
        if category == "clipboard" {
          let directory = preferencesDirectory
          let requestedID = queryID
          let query = search
          await MacEmojiClipboardHistory.observe(read: {
            try await Task.detached {
              try MacEmojiClipboardHistory.load(directory: directory)
            }.value
          }, publish: { history in
            // Preserve the selected record across insertions/reordering, never
            // silently move the explicit-insert action to a different record.
            let selectedText = items.indices.contains(selectedIndex) ? items[selectedIndex].text : nil
            items = history?.matching(query) ?? []
            selectedIndex = selectedText.flatMap { text in items.firstIndex { $0.text == text } } ?? -1
            loadedQuery = requestedID
            clipboardNotice = ""
            guard let history else {
              status = "剪贴板历史不可用，请检查共享存储配置"
              return
            }
            status = !history.enabled ? "剪贴板历史已关闭" : items.isEmpty ? "没有已保存的匹配记录" : "本页 \(items.count) 项"
          })
          return
        }
        do {
          try await Task.sleep(nanoseconds: 200_000_000)
          let query = search
          let directory = resources
          let selectedCategory = category
          let selectedOffset = offset
          let selectedGroup = group
          let selectedParent = parent
          let requestedID = queryID
          let result = try await Task.detached {
            try MacEmojiCatalog.load(resources: directory, search: query, category: selectedCategory, offset: selectedOffset, group: selectedGroup, parent: selectedParent)
          }.value
          try Task.checkCancellation()
          items = result
          loadedQuery = requestedID
          status = result.isEmpty ? (selectedOffset == 0 ? "没有匹配的表情" : "已到目录末尾，可返回上一页") : "本页 \(result.count) 项"
        } catch {
          guard !Task.isCancelled else { return }
          items = []
          status = category == "clipboard" ? "剪贴板历史不可用，请检查共享存储配置" : "表情目录不可用，请检查本地资源配置"
        }
      }
  }
}
