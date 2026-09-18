import SwiftUI
import UniformTypeIdentifiers

private struct PersonalDictionaryDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.json] }
  var data: Data
  init() throws { data = try PersonalDictionaryImport.example.encoded() }
  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}

struct PersonalDictionaryImportView: View {
  let save: ([PersonalWord]) throws -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var choosing = false
  @State private var exporting = false
  @State private var document: PersonalDictionaryDocument?
  @State private var preview: PersonalDictionaryImport?
  @State private var fileName = ""
  @State private var error: String?
  @State private var readTask: Task<Void, Never>?
  @State private var loading = false

  var body: some View {
    NavigationView {
      List {
        Section {
          Button("选择 JSON 文件") { choosing = true }.disabled(loading)
            .accessibilityIdentifier("choosePersonalDictionaryFile")
          Button("保存示例文件") {
            do { document = try PersonalDictionaryDocument(); exporting = true }
            catch { self.error = error.localizedDescription }
          }
        } footer: {
          Text("支持拼音、五笔、英文和快捷短语，每次最多 128 条、文件不超过 1 MB。请按示例填写；不支持其他输入法的专有词库文件。")
        }
        if loading { Section { ProgressView("正在读取并校验词库…") } }
        if let preview {
          Section {
            Text(fileName).font(.headline)
            Text("已校验 \(preview.entries.count) 条，请确认内容。编码已按输入引擎规范化。")
              .font(.footnote).foregroundStyle(.secondary)
            ForEach(PersonalWordKind.allCases) { kind in
              let count = preview.entries.filter { $0.kind == kind }.count
              if count > 0 { LabeledContentCompat(title: kind.title, value: "\(count) 条") }
            }
          }
          Section("词条预览") {
            ForEach(preview.entries) { word in
              VStack(alignment: .leading, spacing: 4) {
                Text(word.value).lineLimit(3)
                Text("\(word.kind.title) · \(word.key)").font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        }
        Section {
          Text("确认后加入本机同步队列，打开水杉键盘后逐条生效。同步失败的词条可单独重试；相同类型、编码和内容的已有词条将更新权重。文件内容不会上传。")
            .font(.footnote).foregroundStyle(.secondary)
        }
      }
      .navigationTitle("导入个人词库")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("确认导入") {
            guard let preview else { return }
            do { try save(preview.entries); dismiss() } catch { self.error = error.localizedDescription }
          }.disabled(preview == nil || loading).accessibilityIdentifier("confirmPersonalDictionaryImport")
        }
      }
      .fileImporter(isPresented: $choosing, allowedContentTypes: [.json]) { result in
        // Invalidate an earlier preview before attempting to load a replacement file.
        do {
          let url = try result.get()
          preview = nil
          loading = true
          readTask?.cancel()
          readTask = Task { @MainActor in
            do {
              let imported = try await Task.detached(priority: .userInitiated) {
                try PersonalDictionaryImport.read(from: url)
              }.value
              guard !Task.isCancelled else { return }
              preview = imported
              fileName = url.lastPathComponent
            } catch {
              guard !Task.isCancelled else { return }
              self.error = error.localizedDescription
            }
            loading = false
          }
        } catch { self.error = error.localizedDescription }
      }
      .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                    defaultFilename: "msime-personal-dictionary-example") { result in
        if case .failure(let error) = result { self.error = error.localizedDescription }
      }
      .alert("导入个人词库", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
        Button("好", role: .cancel) { error = nil }
      } message: { Text(error ?? "") }
      .onDisappear { readTask?.cancel(); readTask = nil }
    }
  }
}

private struct LabeledContentCompat: View {
  let title: String
  let value: String
  var body: some View {
    HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary) }
  }
}
