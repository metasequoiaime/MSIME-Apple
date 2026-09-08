import SwiftUI

struct CloudDictionaryView: View {
  private struct Edit: Identifiable { let id = UUID(); let entry: BackendAccountClient.DictionaryEntry?; let kind: BackendAccountClient.DictionaryKind; let userID: String }
  @State private var kind = BackendAccountClient.DictionaryKind.pinyin
  @State private var search = ""
  @State private var page: BackendAccountClient.DictionaryPage?
  @State private var userID: String?
  @State private var busy = false
  @State private var message: String?
  @State private var editing: Edit?
  @State private var deleting: BackendAccountClient.DictionaryEntry?
  @State private var downloading: BackendAccountClient.DictionaryEntry?
  @State private var pending: Task<Void, Never>?
  private let client = BackendAccountClient()
  private let session = BackendAccountSession.shared

  var body: some View {
    List {
      Section {
        Picker("词库", selection: $kind) {
          ForEach(BackendAccountClient.DictionaryKind.allCases) { Text($0.title).tag($0) }
        }
        TextField("搜索云端词条或编码", text: $search).textInputAutocapitalization(.never).autocorrectionDisabled()
        Button("查询云端词库") { run { try await load(offset: 0) } }
        Text("仅管理当前账号的云端个人词条。上传需主动保存；下载需确认后交给本机键盘处理，不会自动上传本机学习记录。")
          .font(.footnote).foregroundStyle(.secondary)
      }
      if let userID {
        Section {
          NavigationLink("查询与管理完整目录", destination: CloudDictionaryCatalogView(kind: kind,
            authorize: { try await authorizedToken(matching: userID) }))
          NavigationLink("导入与导出文件", destination: CloudDictionaryFilesView(kind: kind,
            authorize: { try await authorizedToken(matching: userID) }, imported: { try await load(offset: 0) }))
        }
      }
      if let page {
        Section("云端个人词条") {
          if page.entries.isEmpty { Text("没有匹配的云端词条。").foregroundStyle(.secondary) }
          ForEach(page.entries) { entry in
            VStack(alignment: .leading, spacing: 6) {
              Text(entry.word)
              Text("\(entry.code) · 权重 \(entry.weight)").font(.caption).foregroundStyle(.secondary)
              HStack {
                Button("编辑") { if let userID { editing = Edit(entry: entry, kind: kind, userID: userID) } }
                Button("下载到本机") { downloading = entry }
                Button("删除", role: .destructive) { deleting = entry }
              }.buttonStyle(.borderless)
            }
          }
          HStack {
            Button("上一页") { run { try await load(offset: max(0, page.offset - 100)) } }.disabled(page.offset == 0)
            Spacer()
            Text("第 \(page.offset / 100 + 1) 页").font(.caption)
            Spacer()
            Button("下一页") { run { try await load(offset: page.offset + 100) } }.disabled(!page.has_more)
          }.buttonStyle(.borderless)
        }
      }
      if busy { ProgressView("正在处理…") }
      if let message { Section { Text(message).foregroundStyle(.secondary) } }
      Section {
        NavigationLink("查看本机词库与同步进度", destination: PersonalDictionaryView())
      }
    }
    .navigationTitle("云词库")
    .disabled(busy)
    .toolbar {
      Button("添加") { if let userID { editing = Edit(entry: nil, kind: kind, userID: userID) } }
        .disabled(busy || userID == nil)
    }
    .task { run { try await load(offset: 0) } }
    .onChange(of: kind) { _ in page = nil; run { try await load(offset: 0) } }
    .onDisappear { pending?.cancel(); page = nil }
    .sheet(item: $editing) { edit in
      CloudDictionaryEditor(kind: edit.kind, value: edit.entry.map { .init(code: $0.code, word: $0.word, weight: $0.weight) }) { value in
        let token = try await authorizedToken(matching: edit.userID)
        if let entry = edit.entry { _ = try await client.updateDictionary(entry, value: value, token: token) }
        else { _ = try await client.addDictionary(edit.kind, value: value, token: token) }
        try await load(offset: 0)
      }
    }
    .alert("删除云端词条？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
      Button("取消", role: .cancel) { deleting = nil }
      Button("删除", role: .destructive) {
        guard let entry = deleting, let userID else { return }
        run {
          let token = try await authorizedToken(matching: userID)
          _ = try await client.deleteDictionary(entry, token: token)
          try await load(offset: 0)
        }
        deleting = nil
      }
    } message: { Text("只删除云端这一版本的词条。已下载的本机词条需在本机词库中删除。") }
    .alert("下载词条到本机？", isPresented: Binding(get: { downloading != nil }, set: { if !$0 { downloading = nil } })) {
      Button("取消", role: .cancel) { downloading = nil }
      Button("下载") {
        guard let entry = downloading, let userID else { return }
        run {
          _ = try await authorizedToken(matching: userID)
          let word = try entry.localWord()
          try PersonalDictionaryStore().enqueue(previous: nil, replacement: word)
          message = "已加入本机队列。请打开允许完全访问的水杉键盘，确认同步后再试打。"
        }
        downloading = nil
      }
    } message: { Text("下载内容仅在 Engine 完成处理后生效，可在本机词库查看成功或失败状态。") }
  }
  @MainActor private func authorizedToken(matching expected: String) async throws -> String {
    guard try await session.user()?.id == expected else { throw BackendAccountClient.Failure(status: 401) }
    let token = try await session.accessToken()
    guard try await session.user()?.id == expected else { throw BackendAccountClient.Failure(status: 401) }
    try Task.checkCancellation()
    return token
  }
  @MainActor private func load(offset: Int) async throws {
    guard let identity = try await session.user()?.id else { throw BackendAccountClient.Failure(status: 401) }
    let token = try await authorizedToken(matching: identity)
    let result = try await client.dictionary(kind, search: search, offset: offset, token: token)
    _ = try await authorizedToken(matching: identity)
    page = result; userID = identity
  }
  @MainActor private func run(_ work: @escaping @MainActor () async throws -> Void) {
    guard !busy else { return }
    busy = true; message = nil
    pending = Task {
      defer { busy = false }
      do { try await work() }
      catch is CancellationError { }
      catch { message = error.localizedDescription }
    }
  }
}

struct CloudDictionaryEditor: View {
  let kind: BackendAccountClient.DictionaryKind
  let isEditing: Bool
  let save: (BackendAccountClient.DictionaryValue) async throws -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var code: String
  @State private var word: String
  @State private var weight: String
  @State private var message: String?
  @State private var busy = false
  @State private var pending: Task<Void, Never>?
  init(kind: BackendAccountClient.DictionaryKind, value: BackendAccountClient.DictionaryValue?, save: @escaping (BackendAccountClient.DictionaryValue) async throws -> Void) {
    self.kind = kind; self.isEditing = value != nil; self.save = save
    _code = State(initialValue: value?.code ?? "")
    _word = State(initialValue: value?.word ?? "")
    _weight = State(initialValue: String(value?.weight ?? 100_000))
  }
  var body: some View {
    NavigationView {
      Form {
        Section(kind.title) {
          TextField("词条内容", text: $word)
          TextField("完整编码", text: $code).textInputAutocapitalization(.never).autocorrectionDisabled()
          TextField("权重", text: $weight).keyboardType(.numberPad)
        }
        Text("点击上传将把此词条保存到当前账号。版本冲突或重复词条时需返回刷新，再重新确认。")
          .font(.footnote).foregroundStyle(.secondary)
        if let message { Text(message).foregroundStyle(.red) }
        if busy { ProgressView() }
      }
      .navigationTitle(isEditing ? "编辑云端词条" : "添加云端词条")
      .disabled(busy)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("取消") { pending?.cancel(); dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("上传") {
            guard let number = Int64(weight), number >= 0, !word.isEmpty else { message = "请填写词条和有效的非负权重。"; return }
            busy = true; message = nil
            pending = Task {
              defer { busy = false }
              do { try await save(.init(code: code, word: word, weight: number)); try Task.checkCancellation(); dismiss() }
              catch is CancellationError { }
              catch { message = error.localizedDescription }
            }
          }.disabled(busy)
        }
      }
    }
    .interactiveDismissDisabled(busy)
    .onDisappear { pending?.cancel() }
  }
}
