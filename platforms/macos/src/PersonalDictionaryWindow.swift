import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Dynamic Objective-C entry points keep the CMake-built Swift module independent
// of generated bridging headers. The bridge delegates all linguistic work to Engine.
enum MacPersonalDictionaryAccess {
  static func invoke(_ selector: String, _ parameters: NSDictionary) throws -> NSDictionary {
    guard let type = NSClassFromString("MSIMEMacPersonalDictionary") as? NSObject.Type,
          let result = type.perform(NSSelectorFromString(selector), with: parameters)?.takeUnretainedValue() as? NSDictionary else {
      throw PersonalDictionaryImport.ImportError(message: "个人词库暂不可用，请重新打开输入法设置。")
    }
    if let error = result["error"] as? NSError { throw error }
    return result
  }
  static func dictionary(_ word: PersonalWord) throws -> NSDictionary {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(word)) as! NSDictionary
  }
}
extension PersonalWord {
  func validated() throws -> PersonalWord {
    let result = try MacPersonalDictionaryAccess.invoke("validate:", MacPersonalDictionaryAccess.dictionary(self))
    return try JSONDecoder().decode(PersonalWord.self, from: JSONSerialization.data(withJSONObject: result["entry"]!))
  }
}

@MainActor
final class MacPersonalDictionaryModel: ObservableObject {
  @Published var entries: [PersonalWord] = []
  @Published var hasMore = false
  @Published var offset = 0
  @Published var loaded = false
  @Published var saving = false
  private var writeGeneration = 0
  @Published var error: String?
  private var generation = ""
  private var lastEdit: (previous: PersonalWord?, replacement: PersonalWord?, id: String)?
  typealias Invoke = (String, NSDictionary) throws -> NSDictionary
  private let invoke: Invoke
  init(invoke: @escaping Invoke = MacPersonalDictionaryAccess.invoke) { self.invoke = invoke }
  func load(offset: Int = 0) {
    do {
      let result = try invoke("page:", ["offset": offset])
      entries = try JSONDecoder().decode([PersonalWord].self, from: JSONSerialization.data(withJSONObject: result["entries"]!))
      generation = result["generation"] as? String ?? ""
      hasMore = result["hasMore"] as? Bool ?? false
      self.offset = offset; loaded = true; error = nil
    } catch { self.error = error.localizedDescription; loaded = false; entries = [] }
  }
  func cancelPendingWrites() { writeGeneration += 1 }
  func save(previous: PersonalWord?, replacement: PersonalWord?, identifier: String? = nil) async -> Bool {
    guard !saving else { return false }
    saving = true
    defer { saving = false }
    let version = writeGeneration
    guard loaded else { error = "请先刷新个人词库。"; return false }
    do {
      let id: String
      if let identifier { id = identifier }
      else if let lastEdit, lastEdit.previous == previous, lastEdit.replacement == replacement { id = lastEdit.id }
      else { id = UUID().uuidString }
      lastEdit = (previous, replacement, id)
      var parameters: [String: Any] = ["identifier": id, "generation": generation]
      if let previous { parameters["previous"] = try MacPersonalDictionaryAccess.dictionary(previous) }
      if let replacement { parameters["replacement"] = try MacPersonalDictionaryAccess.dictionary(replacement) }
      _ = try await MacDictionaryMutation.perform {
        guard self.writeGeneration == version else { throw CancellationError() }
        return try self.invoke("edit:", parameters as NSDictionary)
      }
      lastEdit = nil; error = nil
      return true
    } catch { self.error = error.localizedDescription; return false }
  }
}

private struct PersonalWordEditor: View {
  let previous: PersonalWord?
  @ObservedObject var model: MacPersonalDictionaryModel
  @Environment(\.dismiss) private var dismiss
  @State private var word: PersonalWord
  init(previous: PersonalWord?, model: MacPersonalDictionaryModel) {
    self.previous = previous; self.model = model
    _word = State(initialValue: previous ?? PersonalWord(key: "", value: ""))
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(previous == nil ? "添加个人词条" : "编辑个人词条").font(.title2)
      Picker("类型", selection: $word.kind) { ForEach(PersonalWordKind.allCases) { Text($0.title).tag($0) } }
      TextField("编码（拼音用空格或单引号分隔音节）", text: $word.key).accessibilityLabel("词条编码")
      Text("词条内容").font(.headline)
      TextEditor(text: $word.value).frame(height: 100).border(Color.secondary.opacity(0.3)).accessibilityLabel("词条内容")
      Text("权重").font(.headline)
      TextField("权重", value: $word.weight, format: .number.grouping(.never)).accessibilityLabel("词条权重")
      Text("权重范围 1–100000000。快捷短语支持多行；保存后在下一次输入时生效。")
        .font(.footnote).foregroundStyle(.secondary)
      if let error = model.error { Text(error).foregroundStyle(.secondary) }
      HStack {
        Spacer()
        Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).accessibilityLabel("取消编辑")
        Button("保存") {
          Task { if await model.save(previous: previous, replacement: word) { model.load(offset: model.offset); dismiss() } }
        }.keyboardShortcut(.defaultAction).disabled(word.key.isEmpty || word.value.isEmpty).accessibilityLabel("保存词条")
      }
    }.padding(24).frame(width: 460).disabled(model.saving)
  }
}

private struct MacPersonalDictionaryView: View {
  @StateObject private var model = MacPersonalDictionaryModel()
  @State private var search = ""
  @State private var editing: Editing?
  @State private var deleting: PersonalWord?
  @State private var imports: [ImportEntry] = []
  @State private var importedCount = 0
  @State private var pending: Task<Void, Never>?
  @State private var busy = false
  private struct Editing: Identifiable { let id = UUID(); let word: PersonalWord? }
  private struct ImportEntry: Identifiable { let id = UUID().uuidString; let word: PersonalWord }
  private var visible: [PersonalWord] {
    model.entries.filter { search.isEmpty || $0.key.localizedCaseInsensitiveContains(search) || $0.value.localizedCaseInsensitiveContains(search) }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("本机个人词库").font(.title2)
      Text("包括手动添加和引擎学习产生的词条。保存前请完成当前输入；词条保存在本机，不会自动上传。")
        .font(.footnote).foregroundStyle(.secondary)
      HStack {
        Button("添加…") { model.error = nil; editing = Editing(word: nil) }.disabled(!model.loaded).accessibilityLabel("添加个人词条")
        Button("导入 JSON…") { chooseFile() }.accessibilityLabel("导入 JSON 词库")
        Button("保存示例…") { saveExample() }.accessibilityLabel("保存词库示例")
        Spacer()
        Button("刷新") { model.load(offset: model.offset) }.keyboardShortcut("r", modifiers: .command).accessibilityLabel("刷新个人词库")
      }
      TextField("搜索本页词条或编码", text: $search)
      if model.loaded && visible.isEmpty {
        Text(search.isEmpty ? "本页暂无个人词条，可添加词条或导入 JSON 词库。" : "本页没有匹配的词条。")
          .font(.callout).foregroundStyle(.secondary)
      }
      List(visible) { word in
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(word.value).lineLimit(3).textSelection(.enabled)
            Text("\(word.kind.title) · \(word.key) · 权重 \(word.weight)").font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Button("编辑") { model.error = nil; editing = Editing(word: word) }.accessibilityLabel("编辑词条：\(word.value)")
          Button("删除", role: .destructive) { deleting = word }.accessibilityLabel("删除词条：\(word.value)")
        }.padding(.vertical, 4)
      }
      HStack {
        Button("上一页") { model.load(offset: max(0, model.offset - 100)) }.disabled(model.offset == 0).accessibilityLabel("上一页")
        Text("第 \(model.offset / 100 + 1) 页 · 每页最多 100 条").font(.caption)
        Button("下一页") { model.load(offset: model.offset + 100) }.disabled(!model.hasMore).accessibilityLabel("下一页")
      }
      if !imports.isEmpty {
        GroupBox("导入预览 · 已导入 \(importedCount) 条，剩余 \(imports.count) 条") {
          VStack(alignment: .leading) {
            ScrollView { ForEach(imports) { item in Text("\(item.word.kind.title) · \(item.word.key) · \(item.word.value)").frame(maxWidth: .infinity, alignment: .leading) } }.frame(height: 110)
            Text("逐条保存，发生错误时保留剩余词条供重试；已保存的词条不会回滚。相同类型、编码和内容的词条将更新权重。")
              .font(.footnote).foregroundStyle(.secondary)
            HStack {
              Button("确认导入剩余词条") { applyImport() }.disabled(!model.loaded)
              Button("放弃剩余词条") { imports = []; importedCount = 0 }
            }
          }.padding(8)
        }
      }
      if let error = model.error { Text(error).foregroundStyle(.secondary) }
      if busy { ProgressView("正在处理词库…") }
    }.padding(20).frame(minWidth: 620, minHeight: 540).disabled(busy || model.saving)
      .onAppear { model.load() }.onDisappear { pending?.cancel() }
      .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
        if let window = notification.object as? NSWindow, window === MacPersonalDictionaryWindow.shared.window {
          pending?.cancel(); model.cancelPendingWrites()
        }
      }
      .sheet(item: $editing) { item in PersonalWordEditor(previous: item.word, model: model) }
      .alert("删除个人词条？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
        Button("取消", role: .cancel) { deleting = nil }
        Button("删除", role: .destructive) {
          let word = deleting
          deleting = nil
          Task { if let word, await model.save(previous: word, replacement: nil) { model.load(offset: model.offset) } }
        }
      } message: { Text(deleting?.value ?? "") }
  }
  private func chooseFile() {
    let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      imports = []; importedCount = 0; busy = true
      pending = Task { @MainActor in
        defer { busy = false }
        do {
          let file = try await Task.detached { try PersonalDictionaryImport.read(from: url) }.value
          try Task.checkCancellation()
          imports = file.entries.map { ImportEntry(word: $0) }; model.error = nil
        } catch { if !Task.isCancelled { model.error = error.localizedDescription } }
      }
    }
  }
  private func applyImport() {
    busy = true
    pending = Task { @MainActor in
      defer { busy = false }
      while let item = imports.first, !Task.isCancelled {
        guard await model.save(previous: nil, replacement: item.word, identifier: item.id) else { return }
        imports.removeFirst(); importedCount += 1
        await Task.yield()
      }
      model.load(offset: model.offset)
    }
  }
  private func saveExample() {
    let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "水杉个人词库示例.json"
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      do { try PersonalDictionaryImport.example.encoded().write(to: url, options: .atomic) }
      catch { model.error = error.localizedDescription }
    }
  }
}

@MainActor
final class MacPersonalDictionaryWindow: NSWindowController {
  static let shared = MacPersonalDictionaryWindow()
  private init() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 700),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    super.init(window: window)
    window.title = "个人词库"; window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: MacPersonalDictionaryView()); window.center()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func showDictionary() { showWindow(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
}
@_cdecl("MSIMEShowPersonalDictionary")
func showPersonalDictionary() { Task { @MainActor in MacPersonalDictionaryWindow.shared.showDictionary() } }
