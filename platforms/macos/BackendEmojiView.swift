import AppKit
import SwiftUI

struct MacEmojiView: View {
  let resources: String
  @State private var search = ""
  @State private var category = ""
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
      TextField("搜索表情或关键词", text: $search)
      Text(status).font(.caption).foregroundStyle(.secondary)
      ScrollView {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: category == "kaomoji" ? 3 : 8), spacing: 8) {
          ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            Button(item.text) { onSelect(item.text) }
              .font(category == "kaomoji" ? .body : .title2).buttonStyle(.plain)
              .help([item.group, item.annotation].filter { !$0.isEmpty }.joined(separator: " · "))
              .accessibilityLabel(item.annotation.isEmpty ? item.text : item.annotation)
          }
        }
      }
    }.padding(20).frame(minWidth: 380, minHeight: 320)
      .task(id: [search, category]) {
        items = []
        status = "正在加载…"
        do {
          try await Task.sleep(nanoseconds: 200_000_000)
          let query = search
          let directory = resources
          let selectedCategory = category
          let result = try await Task.detached {
            try MacEmojiCatalog.load(resources: directory, search: query, category: selectedCategory)
          }.value
          try Task.checkCancellation()
          items = result
          status = result.isEmpty ? "没有匹配的表情" : result.count == 255 ? "显示前 255 项，请输入关键词缩小范围" : "\(result.count) 个表情"
        } catch {
          guard !Task.isCancelled else { return }
          items = []
          status = "表情目录不可用，请检查本地资源配置"
        }
      }
  }
}
