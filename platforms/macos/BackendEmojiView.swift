import AppKit
import SwiftUI

struct MacEmojiView: View {
  let resources: String
  @State private var search = ""
  @State private var category = ""
  @State private var offset = 0
  @State private var loadedQuery: [String] = []
  private var queryID: [String] { [search, category, String(offset)] }
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
              .font(category == "kaomoji" ? .body : .title2).buttonStyle(.plain)
              .help([item.group, item.annotation].filter { !$0.isEmpty }.joined(separator: " · "))
              .accessibilityLabel(item.annotation.isEmpty ? item.text : item.annotation)
          }
        }
      }
    }.padding(20).frame(minWidth: 380, minHeight: 320)
      .onChange(of: search) { _ in offset = 0 }
      .onChange(of: category) { _ in offset = 0 }
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
          let requestedID = queryID
          let result = try await Task.detached {
            try MacEmojiCatalog.load(resources: directory, search: query, category: selectedCategory, offset: selectedOffset)
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
