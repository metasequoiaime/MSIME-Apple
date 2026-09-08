import SwiftUI

@MainActor
struct BackendCommunityResourcesView: View {
  let accountID: String
  @Environment(\.dismiss) private var dismiss
  @State private var kind: BackendAccountClient.ResourceKind = .dictionary
  @State private var scope: BackendAccountClient.ResourceScope = .all
  @State private var search = ""
  @State private var items: [BackendAccountClient.CommunityResource] = []
  @State private var more = false
  @State private var nextOffset = 0
  @State private var busy = false
  @State private var message: String?
  @State private var pending: Task<Void, Never>?
  @State private var selected: BackendAccountClient.CommunityResource?
  @State private var creating = false
  private let client = BackendAccountClient()
  private func authorize() async throws -> String {
    let value = try await BackendAccountSession.shared.credentials(matchingUserID: accountID)
    try Task.checkCancellation(); return value.token
  }
  var body: some View {
    VStack {
      HStack { Text("词包与回复模板").font(.title2); Spacer(); Button("完成") { dismiss() } }.padding()
      List {
        Section {
          Picker("资源", selection: $kind) { ForEach(BackendAccountClient.ResourceKind.allCases) { Text($0.title).tag($0) } }
          Picker("范围", selection: $scope) { Text("全部").tag(BackendAccountClient.ResourceScope.all); Text("我发布的").tag(BackendAccountClient.ResourceScope.mine); Text("我收藏的").tag(BackendAccountClient.ResourceScope.saved) }
          TextField("搜索名称", text: $search)
          Button("查询") { load() }
          Button("分享\(kind.title)") { creating = true }
        }.disabled(busy)
        if let message { Text(message).foregroundStyle(.secondary) }
        if busy { ProgressView() }
        ForEach(items) { item in
          Button { selected = item } label: {
            VStack(alignment: .leading) {
              Text(item.name)
              Text("\(item.author) · 版本 \(item.revision) · \(item.saves) 人收藏").font(.caption).foregroundStyle(.secondary)
            }
          }
        }
        if !busy && items.isEmpty { Text("没有匹配的资源。").foregroundStyle(.secondary) }
        if more { Button("加载更多") { load(append: true) }.disabled(busy) }
      }
    }
    .task { load() }
    .onChange(of: kind) { _ in load() }
    .onChange(of: scope) { _ in load() }
    .onChange(of: search) { _ in items = []; more = false; nextOffset = 0 }
    .onDisappear { pending?.cancel(); items = []; selected = nil; search = "" }
    .sheet(item: $selected, onDismiss: { load() }) { item in
      CommunityResourceDetailView(initial: item, authorize: authorize).communitySheetSize()
    }
    .sheet(isPresented: $creating, onDismiss: { load() }) {
      BackendCommunityResourceEditor(kind: kind, existing: nil, authorize: authorize).communitySheetSize()
    }
  }
  private func load(append: Bool = false) {
    guard !busy else { return }
    let queryKind = kind, queryScope = scope, query = search
    let offset = append ? nextOffset : 0
    if !append { items = []; more = false; nextOffset = 0 }
    busy = true; message = nil
    pending = Task {
      defer { busy = false }
      do {
        let page = try await client.communityResources(queryKind, scope: queryScope, search: query, offset: offset, token: authorize())
        _ = try await authorize()
        guard kind == queryKind, scope == queryScope, search == query else { return }
        if append { let ids = Set(items.map(\.id)); items += page.items.filter { !ids.contains($0.id) } }
        else { items = page.items }
        nextOffset = offset + page.items.count; more = page.has_more
      } catch is CancellationError { items = []; more = false }
      catch { if !Task.isCancelled { message = error.localizedDescription } }
    }
  }
}

@MainActor
private struct CommunityResourceDetailView: View {
  let initial: BackendAccountClient.CommunityResource
  let authorize: () async throws -> String
  @Environment(\.dismiss) private var dismiss
  @State private var current: BackendAccountClient.CommunityResource?
  @State private var busy = false
  @State private var message: String?
  @State private var pending: Task<Void, Never>?
  @State private var applying = false
  @State private var applicationRevision: Int64?
  @State private var applicationResource: BackendAccountClient.CommunityResource?
  @State private var deleting = false
  @State private var editing = false
  private let client = BackendAccountClient()
  private var value: BackendAccountClient.CommunityResource { current ?? initial }
  var body: some View {
    VStack {
      HStack { Text(value.name).font(.title2); Spacer(); Button("关闭") { dismiss() } }.padding()
      List {
        Text("\(value.author) · 版本 \(value.revision)").font(.caption)
        Text(value.description)
        if let prompt = value.content.prompt { Text(prompt).textSelection(.enabled) }
        if let entries = value.content.entries {
          Section("\(entries.count) 个词条") {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
              Text("\(entry.kind.title) · \(entry.code) → \(entry.word)")
            }
          }
        }
        if value.kind == .dictionary {
          Button("导入我的云端词库") {
            run(refresh: false) { token in
              let snapshot = value
              let catalog = try await client.dictionaryCatalog(.quick, code: "", token: token)
              _ = try await authorize()
              applicationResource = snapshot; applicationRevision = catalog.revision; applying = true
            }
          }.disabled(busy)
        }
        Button(value.saved ? "取消收藏" : "收藏") { run { token in try await client.saveResource(value.id, saved: !value.saved, token: token) } }.disabled(busy)
        if value.saved && !value.owned {
          Section("评分") {
            ForEach(1...5, id: \.self) { stars in Button("\(stars) 星\(value.my_rating == stars ? " · 当前评分" : "")") { run { token in try await client.rateResource(value.id, stars: stars, token: token) } }.disabled(busy) }
          }
        }
        if value.owned {
          Button("编辑并发布新版本") { editing = true }.disabled(busy)
          Button("删除我的发布", role: .destructive) { deleting = true }.disabled(busy)
        }
        if busy { ProgressView() }
        if let message { Text(message).foregroundStyle(.secondary) }
      }
    }
    .task { run { _ in } }
    .onDisappear { pending?.cancel(); current = nil; applicationResource = nil; applicationRevision = nil; applying = false }
    .sheet(isPresented: $editing, onDismiss: { run { _ in } }) { BackendCommunityResourceEditor(kind: value.kind, existing: value, authorize: authorize).communitySheetSize() }
    .alert("导入这个词包？", isPresented: $applying) {
      Button("取消", role: .cancel) { applicationResource = nil; applicationRevision = nil }
      Button("确认导入") {
        guard let resource = applicationResource, let revision = applicationRevision else { return }
        applicationResource = nil; applicationRevision = nil
        run(refresh: false) { token in
          let result = try await client.applyResource(resource.id, resourceRevision: resource.revision,
            dictionaryRevision: revision, token: token)
          _ = try await authorize()
          message = "已导入云端词库，新增或更新 \(result.imported) 个词条。请通过词库同步应用到本机。"
        }
      }
    } message: {
      Text("将导入所查看版本的全部词条。同编码、同文字的词条会更新权重，其他词条保留。词包或云端词库发生变化时，将停止导入，请重新查看后再试。")
    }
    .alert("删除此资源？", isPresented: $deleting) {
      Button("取消", role: .cancel) { }
      Button("删除", role: .destructive) { run(refresh: false) { token in try await client.deleteResource(value.id, token: token); _ = try await authorize(); dismiss() } }
    } message: { Text("资源将从社区移除，已被其他用户保存到本机的内容不会删除。") }
  }
  private func run(refresh: Bool = true, _ action: @escaping (String) async throws -> Void) {
    guard !busy else { return }; busy = true; message = nil
    pending = Task {
      defer { busy = false }
      do {
        try await action(try await authorize())
        if refresh {
          let item = try await client.communityResource(initial.id, token: authorize())
          _ = try await authorize(); current = item
        }
      } catch is CancellationError { current = nil; dismiss() }
      catch { if !Task.isCancelled { message = error.localizedDescription } }
    }
  }
}

@MainActor
private struct BackendCommunityResourceEditor: View {
  let kind: BackendAccountClient.ResourceKind
  let existing: BackendAccountClient.CommunityResource?
  let authorize: () async throws -> String
  @Environment(\.dismiss) private var dismiss
  @State private var id = UUID()
  @State private var name = ""
  @State private var description = ""
  @State private var prompt = ""
  @State private var entries: [BackendAccountClient.SharedWord] = []
  @State private var sourceKind: BackendAccountClient.DictionaryKind = .pinyin
  @State private var sourceSearch = ""
  @State private var source: BackendAccountClient.DictionaryPage?
  @State private var busy = false
  @State private var message: String?
  @State private var pending: Task<Void, Never>?
  private let client = BackendAccountClient()
  var body: some View {
    VStack {
      HStack { Text("分享\(kind.title)").font(.title2); Spacer(); Button("取消") { dismiss() } }.padding()
      List {
        Section {
          TextField("名称（最多 32 字）", text: $name)
          TextField("说明", text: $description)
          Text("发布后将对所有用户公开，请确认选中的内容适合分享。").font(.footnote)
        }
        if kind == .reply { Section("回复提示词（最多 2000 字）") { TextEditor(text: $prompt).frame(minHeight: 160) } }
        else {
          Section("已选 \(entries.count)/128 个词条") {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, item in
              HStack { Text("\(item.kind.title) · \(item.code) → \(item.word)"); Spacer(); Button("移除") { entries.remove(at: index) } }
            }
          }
          Section("从个人云词库选择") {
            Picker("词库", selection: $sourceKind) { ForEach(BackendAccountClient.DictionaryKind.allCases) { Text($0.title).tag($0) } }
            TextField("搜索词条", text: $sourceSearch)
            Button("查询") { query(offset: 0) }
            if let source {
              ForEach(source.entries) { item in
                Button("添加：\(item.code) → \(item.word)") {
                  if !entries.contains(where: { $0.kind == item.kind && $0.code == item.code && $0.word == item.word }) {
                    entries.append(.init(kind: item.kind, code: item.code, word: item.word, weight: item.weight))
                  }
                }.disabled(entries.count >= 128)
              }
              if source.has_more { Button("下一页") { query(offset: source.offset + source.entries.count) } }
            }
          }
        }
        Button(existing == nil ? "确认公开发布" : "发布新版本") { publish() }
          .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (kind == .dictionary ? entries.isEmpty : prompt.isEmpty))
        if let message { Text(message).foregroundStyle(.secondary) }
        if busy { ProgressView() }
      }.disabled(busy)
    }
    .onAppear { if let existing { id = existing.id; name = existing.name; description = existing.description; prompt = existing.content.prompt ?? ""; entries = existing.content.entries ?? [] } }
    .onChange(of: sourceKind) { _ in source = nil }
    .onChange(of: sourceSearch) { _ in source = nil }
    .onDisappear { pending?.cancel(); source = nil; entries = []; prompt = ""; name = ""; description = ""; sourceSearch = "" }
  }
  private func query(offset: Int) {
    let kind = sourceKind, search = sourceSearch
    run { token in
      let page = try await client.dictionary(kind, search: search, offset: offset, token: token)
      _ = try await authorize()
      if sourceKind == kind && sourceSearch == search { source = page }
    }
  }
  private func publish() {
    let content = BackendAccountClient.ResourceContent(entries: kind == .dictionary ? entries : nil, prompt: kind == .reply ? prompt : nil)
    run { token in
      _ = try await client.publishResource(id: id, kind: kind, name: name, description: description,
        content: content, revision: existing?.revision ?? 0, token: token)
      _ = try await authorize(); dismiss()
    }
  }
  private func run(_ action: @escaping (String) async throws -> Void) {
    guard !busy else { return }; busy = true; message = nil
    pending = Task {
      defer { busy = false }
      do { try await action(try await authorize()) }
      catch is CancellationError { source = nil; entries = []; prompt = ""; dismiss() }
      catch { if !Task.isCancelled { message = error.localizedDescription } }
    }
  }
}

private extension View {
  @ViewBuilder func communitySheetSize() -> some View {
    #if os(macOS)
    frame(width: 650, height: 650)
    #else
    self
    #endif
  }
}

@MainActor
struct CommunityResourcesAccountView: View {
  @State private var accountID: String?
  @State private var message: String?
  var body: some View {
    Group {
      if let accountID { BackendCommunityResourcesView(accountID: accountID) }
      else if let message { Text(message).foregroundStyle(.secondary) }
      else { ProgressView("正在读取账号…") }
    }.task {
      do {
        let identity = try await BackendAccountSession.shared.credentials()
        try Task.checkCancellation(); accountID = identity.userID
      } catch { if !Task.isCancelled { message = error.localizedDescription } }
    }.onDisappear { accountID = nil }
  }
}
