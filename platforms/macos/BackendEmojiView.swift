import AppKit
import SwiftUI

struct MacEmojiView: View {
  let resources: String
  @ObservedObject var appearance = MacEmojiAppearance.shared
  @Environment(\.colorScheme) private var systemColorScheme
  private var palette: MacEmojiPalette {
    MacEmojiPalette(light: (appearance.colorScheme ?? systemColorScheme) == .light)
  }
  @State private var search = ""
  @State private var category = ""
  @State private var group = ""
  @State private var groups: [String] = []
  @State private var groupsCategory: String?
  @State private var groupsFailed = false
  @State private var offset = 0
  @State private var loadedQuery: [String] = []
  private var queryID: [String] { [search, category, group, String(offset)] }
  @State private var items: [MacEmojiCatalogItem] = []
  @State private var status = "正在加载…"
  var onSelect: (String) -> Void = { text in
    NotificationCenter.default.post(name: .msimeHandwritingCandidateSelected, object: nil, userInfo: ["text": text])
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("表情与符号").font(.title2)
      Picker("目录", selection: $category) {
        Text("表情").tag("")
        Text("颜文字").tag("kaomoji")
        Text("符号").tag("symbols")
      }.pickerStyle(.segmented)
      Picker("分类", selection: $group) {
        Text("全部分类").tag("")
        ForEach(groupsCategory == category ? groups : [], id: \.self) { name in
          Text(name).tag(name)
        }
      }.disabled(groupsCategory != category || groups.isEmpty)
      if groupsFailed { Text("分类加载失败，仍可浏览全部或搜索").font(.caption).foregroundStyle(MacEmojiPalette.color(palette.muted)) }
      MacEmojiSearchField(text: $search,
        placeholder: category == "kaomoji" ? "搜索颜文字" : category == "symbols" ? "搜索符号" : "搜索表情",
        palette: palette)
      Text(status).font(.caption).foregroundStyle(MacEmojiPalette.color(palette.muted))
      HStack {
        Button("上一页") { offset = max(0, offset - 255) }.disabled(offset == 0)
        Spacer()
        Text("第 \(offset / 255 + 1) 页").font(.caption)
        Spacer()
        Button("下一页") { offset += 255 }
          .disabled(loadedQuery != queryID || items.isEmpty || offset > Int.max - 255)
      }
      ScrollView {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: category == "kaomoji" ? 3 : 8), spacing: 8) {
          ForEach(Array((loadedQuery == queryID ? items : []).enumerated()), id: \.offset) { _, item in
            Button(item.text) { onSelect(item.text) }
              .font(category == "kaomoji" ? .body : .title2)
              .buttonStyle(MacEmojiCellStyle(palette: palette))
              .help([item.group, item.annotation].filter { !$0.isEmpty }.joined(separator: " · "))
              .accessibilityLabel(item.annotation.isEmpty ? item.text : item.annotation)
          }
        }
      }
    }.padding(20).frame(minWidth: 380, minHeight: 320)
      .background(MacEmojiPalette.color(palette.background))
      .foregroundStyle(MacEmojiPalette.color(palette.text))
      .tint(MacEmojiPalette.color(palette.accent))
      .preferredColorScheme(appearance.colorScheme)
      .onChange(of: search) { _ in offset = 0 }
      .onChange(of: category) { _ in offset = 0; group = "" }
      .onChange(of: group) { _ in offset = 0 }
      .task(id: category) {
        groupsCategory = nil
        groups = []
        groupsFailed = false
        let selectedCategory = category
        let directory = resources
        do {
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
        loadedQuery = []
        status = "正在加载…"
        do {
          try await Task.sleep(nanoseconds: 200_000_000)
          let query = search
          let directory = resources
          let selectedCategory = category
          let selectedOffset = offset
          let selectedGroup = group
          let requestedID = queryID
          let result = try await Task.detached {
            try MacEmojiCatalog.load(resources: directory, search: query, category: selectedCategory, offset: selectedOffset, group: selectedGroup)
          }.value
          try Task.checkCancellation()
          items = result
          loadedQuery = requestedID
          status = result.isEmpty ? (selectedOffset == 0 ? "没有匹配的表情" : "已到目录末尾，可返回上一页") : "本页 \(result.count) 项"
        } catch {
          guard !Task.isCancelled else { return }
          items = []
          status = "表情目录不可用，请检查本地资源配置"
        }
      }
  }
}
