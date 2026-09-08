import SwiftUI
import UniformTypeIdentifiers

struct CloudDictionaryFilesView: View {
  let kind: BackendAccountClient.DictionaryKind
  let authorize: () async throws -> String
  let imported: () async throws -> Void
  @State private var format = BackendAccountClient.DictionaryFileFormat.standard
  @State private var choosing = false
  @State private var confirming = false
  @State private var text: String?
  @State private var fileName = ""
  @State private var busy = false
  @State private var message: String?
  @State private var pending: Task<Void, Never>?
  @State private var exported: Export?
  private let client = BackendAccountClient()
  private struct Export: Identifiable { let id = UUID(); let url: URL }
  private var lines: [String] { (text ?? "").components(separatedBy: .newlines).filter { !$0.isEmpty } }

  var body: some View {
    List {
      Section(kind.title) {
        Picker("文件格式", selection: $format) {
          ForEach(BackendAccountClient.DictionaryFileFormat.allCases.filter { kind == .pinyin || $0 != .hans }) {
            Text($0.title).tag($0)
          }
        }
        Button("选择 UTF-8 文本文件") { choosing = true }
        if format == .hans {
          Text("每行一个汉字词条，由服务器调用输入引擎注音。请导入后检查多音字读音；默认权重为 100000。")
        } else {
          Text(format == .windows && (kind == .english || kind == .quick)
            ? "每行：编码、词条、权重，三列以制表符分隔。"
            : "每行：词条、编码、权重，三列以制表符分隔。")
        }
        Text("每次最多 500 条，包含 JSON 转义后的请求不超过 64 KiB。选择文件只在本机预览；确认上传后才写入云端，重复或无效词条会让整批导入失败，原有云端词条保持不变。")
          .font(.footnote).foregroundStyle(.secondary)
      }
      if let text {
        Section("导入预览") {
          Text(fileName).font(.headline)
          Text("\(lines.count) 行 · \(text.utf8.count) 字节")
          ForEach(Array(lines.prefix(12).enumerated()), id: \.offset) { _, line in Text(line).font(.caption).lineLimit(3) }
          if lines.count > 12 { Text("仅显示前 12 行。") }
          Button("确认上传到云端") { confirming = true }
        }
      }
      Section("导出云端个人词条") {
        Text(format == .windows
          ? "按 Windows 规则导出：拼音仅多字词，其他类型仅用户添加的词条。文件通过系统分享面板保存到你选择的位置。"
          : "导出所选类型的全部云端个人词条，包括搜索结果之外的词条；文件通过系统分享面板保存到你选择的位置。")
          .font(.footnote).foregroundStyle(.secondary)
        Button("导出文件") { run { try await export() } }.disabled(format == .hans)
      }
      Section("完整云词库备份") {
        Text("包含全部四类词库以及删除、调频和固定位置记录。导出不会改变本机词库。")
          .font(.footnote).foregroundStyle(.secondary)
        Button("导出完整云词库快照") { run { try await exportSnapshot() } }
      }
      if busy { ProgressView("正在传输…") }
      if let message { Text(message).foregroundStyle(.secondary) }
    }
    .disabled(busy)
    .navigationTitle("词库文件")
    .onDisappear { pending?.cancel(); text = nil }
    .fileImporter(isPresented: $choosing, allowedContentTypes: [.plainText, .tabSeparatedText]) { result in
      text = nil; message = nil
      do {
        let url = try result.get()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 65536 else { throw BackendAccountClient.Failure(status: 400) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 65537) ?? Data()
        guard data.count <= 65536, let content = String(data: data, encoding: .utf8), !content.contains("\0") else { throw BackendAccountClient.Failure(status: 400) }
        text = content; fileName = url.lastPathComponent
      } catch { message = "无法读取文件，请确认是大小不超过 64 KiB 的 UTF-8 文本。" }
    }
    .alert("上传词库文件？", isPresented: $confirming) {
      Button("取消", role: .cancel) { }
      Button("上传") {
        guard let text else { return }
        run {
          let token = try await authorize()
          let result = try await client.importDictionary(kind, text: text, format: format, token: token)
          self.text = nil
          message = "云端已导入 \(result.imported) 条；需要下载到本机后才会影响本机输入。"
          try await imported()
        }
      }
    } message: { Text("将按“\(format.title)”导入 \(kind.title)词库，重复或无效词条会让整批导入失败。") }
    .sheet(item: $exported) { item in
      CloudDictionaryShareView(url: item.url)
        .onDisappear { try? FileManager.default.removeItem(at: item.url.deletingLastPathComponent()) }
    }
  }
  @MainActor private func exportSnapshot() async throws {
    let token = try await authorize()
    let snapshot = try await client.dictionarySnapshot(token: token)
    do { _ = try await authorize(); try Task.checkCancellation() }
    catch { try? FileManager.default.removeItem(at: snapshot.url.deletingLastPathComponent()); throw error }
    message = "备份文件摘要已校验：云端版本 \(snapshot.envelope.revision)，共 \(snapshot.envelope.records) 条记录。"
    exported = Export(url: snapshot.url)
  }
  @MainActor private func export() async throws {
    let token = try await authorize()
    let url = try await client.exportDictionary(kind, format: format, token: token)
    do { _ = try await authorize(); try Task.checkCancellation() }
    catch { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()); throw error }
    exported = Export(url: url)
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

private struct CloudDictionaryShareView: UIViewControllerRepresentable {
  let url: URL
  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: [url], applicationActivities: nil)
  }
  func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
