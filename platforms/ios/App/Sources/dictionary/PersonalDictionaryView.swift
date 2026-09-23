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
  @State private var importing = false
  @State private var exportKind = PersonalWordKind.pinyin
  @State private var exportFormat = "standard"
  @State private var exportCopy: (id: UUID, url: URL)?
  @State private var exportCopyAttempt: UUID?
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
  /// An ASCII search is a code prefix, which the keyboard looks up across the whole store; anything else, such as the word itself, can only filter the page already here.
  private var codeQuery: String? {
    let query = search.trimmingCharacters(in: .whitespaces).lowercased()
    guard !query.isEmpty, query.allSatisfy(\.isASCII),
          query.utf8.count <= PersonalDictionaryStore.maximumQueryBytes else { return nil }
    return query
  }
  private var showsSearchResults: Bool { codeQuery != nil && codeQuery == state.pageQuery }
  private var awaitingKeyboard: Bool {
    state.requestedPageOffset != state.pageOffset || state.requestedQuery != state.pageQuery
  }
  private var visibleEntries: [PersonalWord] {
    // The keyboard matched the code with the Engine's own rule, which ignores pinyin separators, so its answer is shown whole.
    if showsSearchResults { return state.entries }
    return state.entries.filter { search.isEmpty || $0.value.localizedCaseInsensitiveContains(search) || $0.key.localizedCaseInsensitiveContains(search) }
  }
  private func requestPage(_ offset: Int) {
    perform { try store.requestPage(offset: offset, query: state.requestedQuery) }
  }
  var body: some View {
    List {
      // 这一组原来是五个平铺的列表行:一个标题、一段说明、试打框、同步时间、错误。说明和时间讲的都是同一件事 —— 同步走到哪儿了 —— 所以状态归状态,说明归 footer,中间只留下真正要人动手的那个试打框。
      Section {
        SettingsFactRow(title: state.pendingCount > 0 ? "\(state.pendingCount) 项等待键盘同步" : "已全部同步",
                        detail: state.snapshotDate.map { "最近同步 \($0.formatted(date: .abbreviated, time: .standard))" }
                          ?? "尚未收到键盘确认，保存的操作暂不会标记为已生效",
                        symbol: state.pendingCount > 0 ? "clock.arrow.circlepath" : "checkmark.circle.fill")
        TextField("点此打开键盘并试打", text: $trial)
          .accessibilityIdentifier("personalDictionaryTrial")
        SettingsActionRow(title: "从文件导入词条", detail: "JSON、纯中文词表或词库文件",
                          symbol: "square.and.arrow.down.fill") { importing = true }
          .accessibilityIdentifier("importPersonalDictionary")
      } header: {
        Text("键盘同步")
      } footer: {
        Text("开启水杉键盘的「允许完全访问」，再打开键盘完成本机同步。已保存的学习记录和词条不会上传。")
      }
      exportSection
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
        if let codeQuery, codeQuery == state.requestedQuery, codeQuery != state.pageQuery {
          Text("已请求在整个词库里搜索「\(codeQuery)」，打开上方试打框让键盘查找。").foregroundStyle(.secondary)
        }
        if visibleEntries.isEmpty {
          Text(search.isEmpty ? "本页暂无个人词条。点击右上角添加。"
               : showsSearchResults ? "个人词库里没有以「\(state.pageQuery)」开头的编码。" : "本页没有匹配的词条。")
            .foregroundStyle(.secondary)
        }
        ForEach(visibleEntries) { word in
          Button { editing = Editing(previous: word) } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(word.value).foregroundStyle(.primary).lineLimit(3)
              Text("\(word.kind.title) · \(word.key) · 权重 \(word.weight)").font(.caption).foregroundStyle(.secondary)
            }
          }
          .swipeActions {
            Button("删除", role: .destructive) { deleting = word }
          }
        }
      } header: { Text(showsSearchResults ? "编码以「\(state.pageQuery)」开头的词条" : "已生效词条") } footer: {
        Text("包括手动添加和引擎学习生成的词条。每页最多 100 条；搜索编码时在键盘里查整个个人词库，搜索汉字只筛当前页。滑动词条可删除。刷新、翻页或搜索编码后打开上方试打框，同步新的列表。")
      }
      // 翻页原本是词条组最后一行里三个并排的小按钮,和词条自己的点按、侧滑挤在同一片区域。
      if state.pageOffset > 0 || state.hasMore {
        Section {
          SettingsActionRow(title: "上一页", symbol: "chevron.left", enabled: state.pageOffset > 0) {
            requestPage(max(0, state.pageOffset - 100))
          }
          SettingsActionRow(title: "下一页", symbol: "chevron.right", enabled: state.hasMore) {
            requestPage(state.pageOffset + 100)
          }
        } footer: {
          Text(awaitingKeyboard
               ? "等待键盘读取第 \(state.requestedPageOffset / 100 + 1) 页…"
               : "第 \(state.pageOffset / 100 + 1) 页")
        }
      }
    }
    .settingsStatus(busy: false, message: state.snapshotError)
    .navigationTitle("个人词库")
    .searchable(text: $search, prompt: "搜索编码或本页词条")
    .onSubmit(of: .search) {
      guard let codeQuery, codeQuery != state.requestedQuery else { return }
      perform { try store.requestPage(offset: 0, query: codeQuery) }
    }
    .onChange(of: search) { value in
      // Clearing the search goes back to the whole store's first page rather than leaving the last search's results in place.
      guard value.isEmpty, !state.requestedQuery.isEmpty else { return }
      perform { try store.requestPage(offset: 0) }
    }
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button { editing = Editing(previous: nil) } label: { Image(systemName: "plus") }
          .accessibilityLabel("添加词条").accessibilityIdentifier("addPersonalWord")
      }
      ToolbarItem(placement: .navigationBarTrailing) {
        Button { requestPage(state.pageOffset) } label: { Image(systemName: "arrow.clockwise") }
          .accessibilityLabel("刷新个人词库")
      }
    }
    .sheet(item: $editing) { item in
      PersonalWordEditor(previous: item.previous) { replacement in
        try store.enqueue(previous: item.previous, replacement: replacement)
        refresh()
      }
    }
    .sheet(isPresented: $importing) {
      PersonalDictionaryImportView { words in
        try store.enqueueImport(words)
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
  /// Windows exports one dictionary at a time, word first or code first. The keyboard writes the file, because only it may open the Engine's dictionary; the page then offers it to the share sheet.
  @ViewBuilder private var exportSection: some View {
    Section {
      Picker("词库类型", selection: $exportKind) {
        ForEach(PersonalWordKind.allCases) { Text($0.title).tag($0) }
      }.accessibilityIdentifier("personalDictionaryExportKind")
      Picker("文件格式", selection: $exportFormat) {
        Text("词在前（标准）").tag("standard")
        Text("编码在前（Windows）").tag("windows")
      }.accessibilityIdentifier("personalDictionaryExportFormat")
      SettingsActionRow(title: "生成导出文件", detail: "由键盘在下次同步时写出",
                        symbol: "square.and.arrow.up.on.square") {
        perform { try store.requestExport(kind: exportKind, format: exportFormat) }
      }
      .accessibilityIdentifier("requestPersonalDictionaryExport")
      if let request = state.exportRequest {
        if let result = state.exportResult, result.request.id == request.id {
          if let failure = result.error {
            Text(failure).font(.footnote).foregroundStyle(.red)
          } else {
            Text("\(request.kind.title)词库已导出 \(result.rows) 条" + (result.truncated ? "，词库过大，只导出了前面一部分。" : "。"))
              .font(.footnote).foregroundStyle(.secondary)
            if let copy = exportCopy, copy.id == request.id {
              ShareLink(item: copy.url) { Label("分享「\(request.fileName)」", systemImage: "square.and.arrow.up") }
                .accessibilityIdentifier("sharePersonalDictionaryExport")
            }
          }
        } else {
          Text("等待键盘生成\(request.kind.title)词库文件，打开上方试打框。").font(.footnote).foregroundStyle(.secondary)
        }
      }
    } header: {
      Text("导出")
    } footer: {
      Text("与电脑版导出的文件相同：每行一条，用 Tab 分隔。拼音导出多字词，包括调整过权重的内置词；其他类型只导出你添加的词条。文件只保存在本机，通过分享面板存到你选择的位置。")
    }
  }

  private func refresh() {
    do { state = try store.read(); lastReadError = nil; prepareExportCopy() } catch {
      let message = error.localizedDescription
      if lastReadError != message { self.error = message; lastReadError = message }
    }
  }
  /// Copies the export the keyboard just wrote, once, so the share sheet gets a file under the desktop's name.
  private func prepareExportCopy() {
    guard let result = state.exportResult, result.request.id == state.exportRequest?.id, result.error == nil,
          exportCopyAttempt != result.request.id else { return }
    // The page re-reads the queue every second; a copy that failed is reported once, not every second.
    exportCopyAttempt = result.request.id
    do { exportCopy = (result.request.id, try store.exportCopy(for: result)) } catch {
      self.error = error.localizedDescription
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
          Text(word.kind == .pinyin ? "每个字填写一个完整拼音音节，用空格或英文单引号分隔；ü 用 v。全拼、双拼和九键共用这个词条。" : "五笔使用 1–4 个字母；快捷短语使用字母或数字，在键盘“本地输入 → 快捷短语”输入；英文编码使用字母、连字符或撇号，可以和词条不同，例如用 dont 打出 don't。")
        }
        Section {
          TextField("权重", value: $word.weight, format: .number.grouping(.never))
            .keyboardType(.numberPad)
            .accessibilityIdentifier("personalWordWeight")
        } header: {
          Text("权重")
        } footer: {
          Text("同一编码下权重越大，候选越靠前。新词默认 \(PersonalWord.defaultWeight)，可填 1–\(PersonalWord.weightRange.upperBound)。")
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
            guard PersonalWord.weightRange.contains(word.weight) else {
              error = "权重需要在 1–\(PersonalWord.weightRange.upperBound) 之间。"
              return
            }
            do { try save(word.validated()); dismiss() } catch { self.error = error.localizedDescription }
          }.disabled(word.key.isEmpty || word.value.isEmpty).accessibilityIdentifier("savePersonalWord")
        }
      }
    }
  }
}
