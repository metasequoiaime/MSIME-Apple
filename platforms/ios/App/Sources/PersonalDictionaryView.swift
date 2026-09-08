import SwiftUI

struct PersonalDictionaryView: View {
  private struct Editing: Identifiable { let id = UUID(); var previous: PersonalWord? }
  @State private var state = PersonalDictionaryState()
  @State private var editing: Editing?
  @State private var deleting: PersonalWord?
  @State private var error: String?
  @State private var lastReadError: String?
  @State private var trial = ""
  @State private var search = ""
  private let store: PersonalDictionaryStore
  init() {
    #if DEBUG && targetEnvironment(simulator)
    let arguments = ProcessInfo.processInfo.arguments
    if let index = arguments.firstIndex(of: "-personalDictionaryTestID"), index + 1 < arguments.count,
       let id = UUID(uuidString: arguments[index + 1]) {
      store = PersonalDictionaryStore(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("personal-dictionary-ui-\(id.uuidString)"))
      return
    }
    #endif
    store = PersonalDictionaryStore()
  }
  private var visibleEntries: [PersonalWord] {
    state.entries.filter { search.isEmpty || $0.value.localizedCaseInsensitiveContains(search) || $0.key.localizedCaseInsensitiveContains(search) }
  }
  var body: some View {
    List {
      Section {
        Label(state.pendingCount > 0 ? "\(state.pendingCount) 项等待键盘同步" : "个人词库", systemImage: "character.book.closed")
          .font(.headline)
        Text("开启水杉键盘的“允许完全访问”，再打开键盘完成本机同步。已保存的学习记录和词条不会上传。")
          .font(.footnote).foregroundStyle(.secondary)
        TextField("点此打开键盘并试打", text: $trial)
          .accessibilityIdentifier("personalDictionaryTrial")
        if let date = state.snapshotDate {
          Text("最近同步：\(date.formatted(date: .abbreviated, time: .standard))")
            .font(.caption).foregroundStyle(.secondary)
        } else {
          Text("尚未收到键盘确认，保存的操作暂不会标记为已生效。")
            .font(.caption).foregroundStyle(.secondary)
        }
        if let message = state.snapshotError { Text(message).font(.footnote).foregroundStyle(.red) }
      }
      let requests = state.requests.filter { $0.status != .applied }
      if !requests.isEmpty {
        Section("同步进度") {
          ForEach(requests) { request in
            VStack(alignment: .leading, spacing: 5) {
              Text((request.replacement ?? request.previous)?.value ?? "词条")
              Text(request.status == .pending ? "等待同步 · \(request.replacement == nil ? "删除" : "保存")" : (request.error ?? "同步失败"))
                .font(.caption).foregroundStyle(request.status == .pending ? Color.secondary : .red)
              if request.status == .failed {
                HStack {
                  Button("重试") { perform { try store.retry(request.id) } }.buttonStyle(.borderless)
                  Button("移除失败记录", role: .destructive) { perform { try store.dismissFailure(request.id) } }
                    .buttonStyle(.borderless)
                }
              }
            }
          }
        }
      }
      Section {
        if visibleEntries.isEmpty {
          Text(search.isEmpty ? "本页暂无个人词条。点击右上角添加。" : "本页没有匹配的词条。")
            .foregroundStyle(.secondary)
        }
        ForEach(visibleEntries) { word in
          Button { editing = Editing(previous: word) } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(word.value).foregroundStyle(.primary).lineLimit(3)
              Text("\(word.kind.title) · \(word.key)").font(.caption).foregroundStyle(.secondary)
            }
          }
          .swipeActions {
            Button("删除", role: .destructive) { deleting = word }
          }
        }
        if state.pageOffset > 0 || state.hasMore {
          HStack {
            Button("上一页") { perform { try store.requestPage(offset: max(0, state.pageOffset - 100)) } }
              .disabled(state.pageOffset == 0)
            Spacer()
            Text("第 \(state.pageOffset / 100 + 1) 页").font(.caption)
            Spacer()
            Button("下一页") { perform { try store.requestPage(offset: state.pageOffset + 100) } }
              .disabled(!state.hasMore)
          }.buttonStyle(.borderless)
        }
        if state.requestedPageOffset != state.pageOffset {
          Text("等待键盘读取第 \(state.requestedPageOffset / 100 + 1) 页…").font(.caption).foregroundStyle(.secondary)
        }
      } header: { Text("已生效词条") } footer: {
        Text("包括手动添加和引擎学习生成的词条。每页最多 100 条，搜索作用于当前页；滑动词条可删除。刷新或翻页后打开上方试打框，同步新的列表。")
      }
    }
    .navigationTitle("个人词库")
    .searchable(text: $search, prompt: "搜索本页词条或编码")
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button { editing = Editing(previous: nil) } label: { Image(systemName: "plus") }
          .accessibilityLabel("添加词条").accessibilityIdentifier("addPersonalWord")
      }
      ToolbarItem(placement: .navigationBarTrailing) {
        Button { perform { try store.requestPage(offset: state.pageOffset) } } label: { Image(systemName: "arrow.clockwise") }
          .accessibilityLabel("刷新个人词库")
      }
    }
    .sheet(item: $editing) { item in
      PersonalWordEditor(previous: item.previous) { replacement in
        try store.enqueue(previous: item.previous, replacement: replacement)
        refresh()
      }
    }
    .alert("删除个人词条？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
      Button("取消", role: .cancel) { deleting = nil }
      Button("删除", role: .destructive) {
        if let word = deleting { perform { try store.enqueue(previous: word, replacement: nil) } }
        deleting = nil
      }
    } message: { Text("删除将在键盘同步后生效，并保留到之后的词库升级。") }
    .alert("个人词库", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
      Button("好", role: .cancel) { error = nil }
    } message: { Text(error ?? "") }
    .task {
      while !Task.isCancelled {
        refresh()
        do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { break }
      }
    }
  }
  private func refresh() {
    do { state = try store.read(); lastReadError = nil } catch {
      let message = error.localizedDescription
      if lastReadError != message { self.error = message; lastReadError = message }
    }
  }
  private func perform<T>(_ work: () throws -> T) {
    do { _ = try work(); refresh() } catch { self.error = error.localizedDescription }
  }
}

private struct PersonalWordEditor: View {
  let previous: PersonalWord?
  let save: (PersonalWord) throws -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var word: PersonalWord
  @State private var error: String?
  init(previous: PersonalWord?, save: @escaping (PersonalWord) throws -> Void) {
    self.previous = previous
    self.save = save
    _word = State(initialValue: previous ?? PersonalWord(key: "", value: ""))
  }
  var body: some View {
    NavigationView {
      Form {
        Section {
          Picker("类型", selection: $word.kind) { ForEach(PersonalWordKind.allCases) { Text($0.title).tag($0) } }
          if word.kind == .quickPhrase {
            VStack(alignment: .leading) {
              Text("短语内容").font(.caption).foregroundStyle(.secondary)
              TextEditor(text: $word.value).frame(minHeight: 90).accessibilityIdentifier("personalWordValue")
            }
          } else {
            TextField("词条内容", text: $word.value).accessibilityIdentifier("personalWordValue")
          }
          TextField(word.kind == .pinyin ? "完整拼音，例如 ni hao" : "输入编码", text: $word.key)
            .keyboardType(.asciiCapable).textInputAutocapitalization(.never).autocorrectionDisabled()
            .accessibilityIdentifier("personalWordCode")
        } footer: {
          Text(word.kind == .pinyin ? "每个字填写一个完整拼音音节，用空格或英文单引号分隔；ü 用 v。全拼、双拼和九键共用这个词条。" : "五笔使用 1–4 个字母；快捷短语使用字母或数字，在键盘“本地输入 → 快捷短语”输入；英文编码与词条字母一致。")
        }
        if let error { Section { Text(error).foregroundStyle(.red) } }
        Section { Text("保存后等待水杉键盘确认同步。这里只保存本机词条，不会发送到 AI 或语音服务。").font(.footnote).foregroundStyle(.secondary) }
      }
      .navigationTitle(previous == nil ? "添加词条" : "编辑词条")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            do { try save(word.validated()); dismiss() } catch { self.error = error.localizedDescription }
          }.disabled(word.key.isEmpty || word.value.isEmpty).accessibilityIdentifier("savePersonalWord")
        }
      }
    }
  }
}
