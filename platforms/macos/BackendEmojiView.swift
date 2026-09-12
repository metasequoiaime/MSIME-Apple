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
  @State private var category = "home"
  @State private var pendingEmojiGroup: String?
  private var emojiPage: Bool { category == "" || category == "recent" }
  private var emojiSection: Binding<MacEmojiSectionChoice> {
    Binding(get: { category == "recent" ? .recent : .group(group) }, set: { choice in
      switch choice {
      case .recent: pendingEmojiGroup = nil; category = "recent"
      case .group(let name):
        if category == "" { group = name }
        else { pendingEmojiGroup = name; category = "" }
      }
    })
  }
  private func navigate(_ rawValue: String) {
    guard let page = MacEmojiMainPage(rawValue: rawValue) else { return }
    pendingEmojiGroup = page == .emoji ? "" : nil
    category = page.destination(hasRecents: !recent.items.isEmpty)
  }
  private var mediaPage: MacEmojiMediaPage? { MacEmojiMediaPage(rawValue: category) }
  private var columns: Int { category == "clipboard" ? 1 : MacEmojiGridMetrics.columns }
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
  @State private var toast = MacEmojiToastState()
  @State private var historyRevision = 0
  @State private var historyEnabled: Bool?
  @State private var enablingHistory = false
  @ObservedObject private var clipboardService = MacClipboardService.shared
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
    toast.copied(item.text, success: copyText(item.text))
  }

  private func enableHistory() {
    guard !enablingHistory else { return }
    enablingHistory = true
    let directory = preferencesDirectory
    let requestedID = queryID
    Task {
      defer { enablingHistory = false }
      do {
        try await Task.detached { try MacEmojiClipboardHistory.enable(directory: directory) }.value
        guard requestedID == queryID else { return }
        historyRevision += 1
        toast.show("剪贴板已开启")
      } catch {
        guard requestedID == queryID else { return }
        toast.show("无法开启剪贴板")
      }
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
      Text("表情与更多").font(.system(size: 12, weight: .semibold))
      if category == "home" {
        MacEmojiMainTabs(selected: .home, palette: palette, navigate: navigate)
      } else {
        HStack {
          Button("返回首页") { navigate("home") }
          if emojiPage {
            Picker("表情分类", selection: emojiSection) {
              Text("最近使用").tag(MacEmojiSectionChoice.recent)
              if groupsCategory == category && !groups.isEmpty {
                ForEach(groups, id: \.self) { Text($0).tag(MacEmojiSectionChoice.group($0)) }
              } else {
                Text(groupsFailed ? "分类不可用" : groupsCategory == category ? "分类为空" : "正在加载分类…")
                  .tag(MacEmojiSectionChoice.group(""))
              }
            }
          } else { Text(MacEmojiMainPage.title(category: category)).font(.system(size: 16, weight: .semibold)) }
        }
      }
      if category == "symbols" {
        Picker("符号大类", selection: $parent) {
          Text("全部大类").tag("")
          ForEach(MacEmojiSymbolGroup.parents(symbolGroups), id: \.self) { Text($0).tag($0) }
        }.disabled(groupsCategory != category || symbolGroups.isEmpty)
      }
      if category != "home" && category != "clipboard" && !emojiPage && mediaPage == nil {
      Picker("分类", selection: $group) {
        Text("全部分类").tag("")
        ForEach(groupsCategory == category ? displayedGroups : [], id: \.self) { name in
          Text(name).tag(name)
        }
      }.disabled(groupsCategory != category || displayedGroups.isEmpty)
      }
      if groupsFailed { Text("分类加载失败，可返回首页重试").font(.caption).foregroundStyle(MacEmojiPalette.color(palette.muted)) }
      MacEmojiSearchField(text: $search,
        placeholder: mediaPage != nil ? "搜索" : category == "home" ? "搜索表情、颜文字和符号" : category == "clipboard" ? "搜索剪贴板历史" : category == "kaomoji" ? "搜索颜文字" : category == "symbols" ? "搜索符号" : "搜索表情",
        palette: palette)
      if category == "clipboard" {
        if historyEnabled == false && loadedQuery == queryID {
          Button("开启剪贴板历史") { enableHistory() }
            .buttonStyle(.borderedProminent).disabled(enablingHistory)
          Text("开启共享设置；已运行的桌面客户端可能按此设置保存复制的文本。").font(.caption)
        }
        HStack {
          Text(clipboardService.status?.message ?? "正在检查剪贴板采集设置…").font(.caption)
          Spacer()
          Button("刷新") { historyRevision += 1 }
        }
        if !deletionNotice.isEmpty { Text(deletionNotice).font(.caption) }
      }
      if mediaPage == nil { Text(status).font(.caption).foregroundStyle(MacEmojiPalette.color(palette.muted)) }
      if selection.rejected {
        Text(MacEmojiSelectionState.failureMessage).font(.caption)
          .foregroundStyle(MacEmojiPalette.color(palette.text))
      }
      if category == "home" {
        MacEmojiHomeView(resources: resources, search: search, recent: recent.matching(search),
          palette: palette, copy: copyItem, more: navigate)
      } else if let page = mediaPage {
        MacEmojiMediaPlaceholder(page: page, palette: palette)
      } else {
      HStack {
        Button("上一页") { offset = max(0, offset - 255) }.disabled(offset == 0)
        Spacer()
        Text("第 \(offset / 255 + 1) 页").font(.caption)
        Spacer()
        Button("下一页") { offset += 255 }
          .disabled(category == "recent" || category == "clipboard" || loadedQuery != queryID || items.isEmpty || offset > Int.max - 255)
      }
      GeometryReader { geometry in
      let flowWidth = max(0, geometry.size.width - 16)
      let flowItems = loadedQuery == queryID && category == "kaomoji" ? items : []
      let flowCells = MacEmojiFlow.cells(texts: flowItems.map(\.text), width: flowWidth)
      ScrollViewReader { proxy in
        VStack(spacing: 4) {
          MacEmojiKeyboardEntry(enabled: loadedQuery == queryID && !items.isEmpty) { command in
            if command == .activate && !items.indices.contains(selectedIndex) { return }
            guard loadedQuery == queryID,
                  let index = category == "kaomoji" && (command == .up || command == .down)
                    ? MacEmojiFlow.vertical(from: selectedIndex, direction: command == .up ? -1 : 1, cells: flowCells)
                    : command.destination(from: selectedIndex, count: items.count, columns: columns) else { return }
            selectedIndex = index
            proxy.scrollTo(index)
            if case .activate = command { copyItem(items[index]) }
          }.frame(height: 24)
          ScrollView {
            if category == "kaomoji" {
              MacEmojiFlowGrid(items: flowItems, cells: flowCells, width: flowWidth, palette: palette,
                selected: { selectedIndex == $0 }, identity: { $0 },
                copy: { selectedIndex = $0; copyItem(flowItems[$0]) })
            } else if category == "clipboard" {
            LazyVGrid(columns: [GridItem(.flexible())], spacing: MacClipboardPreview.gap) {
              ForEach(Array((loadedQuery == queryID ? items : []).enumerated()), id: \.offset) { index, item in
                  MacEmojiClipboardRow(text: item.text, palette: palette, selected: selectedIndex == index,
                    deleting: deletingHistory, copy: { selectedIndex = index; copyItem(item) },
                    remove: { removeHistory(item.text) })
                    .id(index)
              }
            }
            } else {
              MacEmojiGrid(items: loadedQuery == queryID ? items : [], palette: palette,
                selected: { selectedIndex == $0 }, identity: { $0 },
                copy: { selectedIndex = $0; copyItem(items[$0]) })
            }
          }
        }
      }
      }
      .overlayPreferenceValue(MacClipboardTooltipPreference.self) { anchors in
        MacClipboardTooltipOverlay(anchors: anchors, light: palette.background == 0xF7F7FA)
      }
      Button("插入所选项") {
        guard loadedQuery == queryID, items.indices.contains(selectedIndex) else { return }
        selection.submit(items[selectedIndex].text, send: onSelect)
      }.disabled(loadedQuery != queryID || !items.indices.contains(selectedIndex))
      }
    }.padding(20).frame(minWidth: MacEmojiGridMetrics.minimumPanelWidth, minHeight: 500)
      .background(MacEmojiPalette.color(palette.background))
      .foregroundStyle(MacEmojiPalette.color(palette.text))
      .tint(MacEmojiPalette.color(palette.accent))
      .preferredColorScheme(appearance.colorScheme)
      .overlay { MacEmojiToastOverlay(message: toast.message, light: palette.background == 0xF7F7FA) }
      .task(id: toast.generation) {
        guard toast.message != nil else { return }
        let generation = toast.generation
        await MacEmojiToastState.expire(generation: generation) { toast.dismiss(ifGeneration: $0) }
      }
      .onChange(of: search) { _ in offset = 0 }
      .onChange(of: category) { _ in offset = 0; group = ""; parent = ""; toast.dismiss() }
      .onChange(of: parent) { _ in offset = 0; group = "" }
      .onChange(of: group) { _ in offset = 0 }
      .task(id: category) {
        groupsCategory = nil
        groups = []
        symbolGroups = []
        groupsFailed = false
        let selectedCategory = category
        let directory = resources
        if selectedCategory == "home" || selectedCategory == "clipboard" || MacEmojiMediaPage(rawValue: selectedCategory) != nil { groupsCategory = selectedCategory; return }
        do {
          if selectedCategory == "symbols" {
            let result = try await Task.detached { try MacEmojiCatalog.loadSymbolGroups(resources: directory) }.value
            try Task.checkCancellation()
            symbolGroups = result
            groupsCategory = selectedCategory
            return
          }
          let result = try await Task.detached {
            try MacEmojiCatalog.loadGroups(resources: directory, category: selectedCategory == "recent" ? "" : selectedCategory)
          }.value
          try Task.checkCancellation()
          groups = result
          groupsCategory = selectedCategory
          if selectedCategory == "" {
            group = MacEmojiSectionChoice.resolvedGroup(requested: pendingEmojiGroup, current: group, groups: result)
            pendingEmojiGroup = nil
          }
        } catch {
          guard !Task.isCancelled else { return }
          groupsFailed = true
        }
      }
      .task(id: queryID) {
        historyEnabled = nil
        items = []
        selectedIndex = 0
        loadedQuery = []
        status = "正在加载…"
        if MacEmojiMediaPage(rawValue: category) != nil { status = ""; loadedQuery = queryID; return }
        if category == "home" { status = "首页预览 · 更多可进入完整目录"; return }
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
            historyEnabled = history?.enabled
            // Preserve the selected record across insertions/reordering, never
            // silently move the explicit-insert action to a different record.
            let selectedText = items.indices.contains(selectedIndex) ? items[selectedIndex].text : nil
            items = history?.matching(query) ?? []
            selectedIndex = selectedText.flatMap { text in items.firstIndex { $0.text == text } } ?? -1
            loadedQuery = requestedID
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
