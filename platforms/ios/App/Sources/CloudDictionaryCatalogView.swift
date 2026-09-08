import SwiftUI

struct CloudDictionaryCatalogView: View {
  let kind: BackendAccountClient.DictionaryKind
  let authorize: () async throws -> String
  @State private var code = ""
  @State private var scheme = "pinyin"
  @State private var profile = "xiaohe"
  @State private var page: BackendAccountClient.DictionaryCatalog?
  @State private var confirmedQuery: Query?
  @State private var editing: Edit?
  @State private var deleting: Edit?
  @State private var busy = false
  @State private var message: String?
  @State private var pending: Task<Void, Never>?
  private let client = BackendAccountClient()
  private struct Query { let code: String; let scheme: String; let profile: String }
  private struct Edit: Identifiable { let id = UUID(); let entry: BackendAccountClient.CatalogEntry; let revision: Int64 }

  var body: some View {
    List {
      Section(kind.title) {
        TextField(kind == .quick ? "快捷编码，可留空" : "输入编码，例如 shi、a 或 hello", text: $code)
          .textInputAutocapitalization(.never).autocorrectionDisabled()
        if kind == .pinyin {
          Picker("编码方案", selection: $scheme) { Text("全拼").tag("pinyin"); Text("双拼").tag("shuangpin") }
          if scheme == "shuangpin" {
            Picker("双拼方案", selection: $profile) {
              Text("小鹤").tag("xiaohe"); Text("自然码").tag("ziranma")
              Text("微软").tag("microsoft"); Text("Shoudao").tag("shoudao")
            }
          }
        }
        Button("查询完整目录") { run { try await load(query: .init(code: code, scheme: scheme, profile: profile), offset: 0) } }
          .disabled(kind != .quick && code.isEmpty)
        Text("包含基础词库与当前账号的修改。编辑和删除仅影响当前账号的云端词库；不会立即修改本机词库。按编码查询，拼音使用全拼或所选双拼方案。")
          .font(.footnote).foregroundStyle(.secondary)
      }
      if let page {
        Section("目录结果 · 云端版本 \(page.revision)") {
          if page.entries.isEmpty { Text("没有匹配的词条。").foregroundStyle(.secondary) }
          Text("查询编码：\(page.normalized)").font(.caption).foregroundStyle(.secondary)
          ForEach(page.entries) { entry in
            VStack(alignment: .leading, spacing: 6) {
              Text(entry.word)
              Text("\(entry.code) · 权重 \(entry.weight)").font(.caption).foregroundStyle(.secondary)
              HStack {
                Button("编辑") { editing = Edit(entry: entry, revision: page.revision) }
                Button("删除", role: .destructive) { deleting = Edit(entry: entry, revision: page.revision) }
              }.buttonStyle(.borderless)
            }
          }
          HStack {
            Button("上一页") { run { try await reload(offset: max(0, page.offset - 100)) } }.disabled(page.offset == 0)
            Spacer()
            Text("第 \(page.offset / 100 + 1) 页").font(.caption)
            Spacer()
            Button("下一页") { run { try await reload(offset: page.offset + 100) } }.disabled(!page.has_more)
          }.buttonStyle(.borderless)
        }
      }
      if busy { ProgressView("正在查询或保存…") }
      if let message { Text(message).foregroundStyle(.secondary) }
    }
    .navigationTitle("完整词库目录")
    .disabled(busy)
    .onDisappear { pending?.cancel(); page = nil }
    .sheet(item: $editing) { edit in
      CloudDictionaryEditor(kind: kind, value: edit.entry.value) { value in
        let token = try await authorize()
        _ = try await client.editCatalog(edit.entry, revision: edit.revision, replacement: value, token: token)
        try await reload(offset: 0)
      }
    }
    .alert("删除云端目录词条？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
      Button("取消", role: .cancel) { deleting = nil }
      Button("删除", role: .destructive) {
        guard let edit = deleting else { return }
        run {
          let token = try await authorize()
          _ = try await client.editCatalog(edit.entry, revision: edit.revision, replacement: nil, token: token)
          try await reload(offset: 0)
        }
        deleting = nil
      }
    } message: { Text("基础词条也可从当前账号的云端目录删除。本机词库保持原样；云端版本变化时须重新查询并确认。") }
  }
  @MainActor private func load(query: Query, offset: Int) async throws {
    let token = try await authorize()
    let result = try await client.dictionaryCatalog(kind, code: query.code, offset: offset, scheme: query.scheme, profile: query.profile, token: token)
    _ = try await authorize()
    try Task.checkCancellation()
    page = result; confirmedQuery = query
  }
  @MainActor private func reload(offset: Int) async throws {
    guard let query = confirmedQuery else { return }
    try await load(query: query, offset: offset)
  }
  @MainActor private func run(_ action: @escaping @MainActor () async throws -> Void) {
    guard !busy else { return }
    busy = true; message = nil
    pending = Task {
      defer { busy = false }
      do { try await action() }
      catch is CancellationError { }
      catch { message = error.localizedDescription }
    }
  }
}
