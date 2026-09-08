import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class MacSnapshotModel: ObservableObject {
  @Published var preview: BackendPreparedSnapshot?
  @Published var busy = false
  @Published var message: String?
  private var expectedRevision: Int64?
  private let accountID: String
  private let client: BackendAccountClient
  private let account: BackendAccountSession
  private var pending: Task<Void, Never>?
  private var panel: NSSavePanel?
  private var closed = false
  init(accountID: String, client: BackendAccountClient = BackendAccountClient(), account: BackendAccountSession = .shared) {
    self.accountID = accountID; self.client = client; self.account = account
  }
  private func authorize() async throws -> String {
    let identity = try await account.credentials()
    try Task.checkCancellation()
    guard !closed, identity.userID == accountID else { throw CancellationError() }
    return identity.token
  }
  private func run(_ action: @escaping @MainActor (String) async throws -> Void) {
    guard !busy, !closed else { return }
    busy = true; message = nil
    pending = Task {
      defer { busy = false }
      do { try await action(try await authorize()) }
      catch is CancellationError { discard() }
      catch { if !Task.isCancelled { message = error.localizedDescription } }
    }
  }
  func backup(to destination: URL) {
    run { token in
      let snapshot = try await self.client.dictionarySnapshot(token: token)
      defer { try? FileManager.default.removeItem(at: snapshot.url.deletingLastPathComponent()) }
      try await MacCloudFileTransfer.save(snapshot.url, to: destination) { _ = try await self.authorize() }
      self.message = "已保存完整云词库备份。"
    }
  }
  func prepare(_ url: URL) {
    run { token in
      self.discard()
      let snapshot = try await BackendPreparedSnapshot.prepareDocument(url)
      let cloud = try await self.client.dictionaryCatalog(.quick, code: "", token: token)
      _ = try await self.authorize()
      self.preview = snapshot; self.expectedRevision = cloud.revision
    }
  }
  func restore() {
    guard let preview, let revision = expectedRevision else { return }
    run { token in
      _ = try await self.client.restoreDictionarySnapshot(file: preview.url, expectedSHA256: preview.envelope.sha256, revision: revision, token: token)
      _ = try await self.authorize()
      self.discard(); self.message = "完整备份已恢复到云端。本机词库尚未替换。"
    }
  }
  func discard() { preview = nil; expectedRevision = nil }
  func chooseBackup() {
    guard !busy, panel == nil else { return }
    let selected = NSSavePanel(); selected.nameFieldStringValue = "水杉完整云词库.ndjson"; selected.allowedContentTypes = [.data]
    panel = selected
    selected.begin { response in Task { @MainActor in
      defer { self.panel = nil }
      guard !self.closed, response == .OK, let url = selected.url else { return }
      self.backup(to: url)
    } }
  }
  func chooseRestore() {
    guard !busy, panel == nil else { return }
    let selected = NSOpenPanel(); selected.allowsMultipleSelection = false; selected.allowedContentTypes = [.data]
    panel = selected
    selected.begin { response in Task { @MainActor in
      defer { self.panel = nil }
      guard !self.closed, response == .OK, let url = selected.url else { return }
      self.prepare(url)
    } }
  }
  func close() { closed = true; pending?.cancel(); panel?.cancel(nil); panel = nil; discard() }
}

struct MacCloudSnapshotView: View {
  @StateObject private var model: MacSnapshotModel
  @Environment(\.dismiss) private var dismiss
  @State private var restoring = false
  init(accountID: String) { _model = StateObject(wrappedValue: MacSnapshotModel(accountID: accountID)) }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack { Text("完整云词库备份").font(.title2); Spacer(); Button("关闭") { model.close(); dismiss() } }
      Text("完整备份包含个人词条、基础词库修改、删除记录、固定位置和调频计数。恢复会替换当前账号的云端词库，其他设备需另行同步。")
      Button("保存完整云端备份…") { model.chooseBackup() }.disabled(model.busy)
      Button("选择备份并预览…") { model.chooseRestore() }.disabled(model.busy)
      if let preview = model.preview {
        Text("\(preview.envelope.entries) 个个人词条，\(preview.envelope.overlays) 条修改记录，\(preview.envelope.positions) 个固定位置，\(preview.envelope.selections) 条调频计数。")
        Text("文件完整性已校验。请确认这是要恢复到当前账号的备份。")
        Button("用此备份替换云端词库", role: .destructive) { restoring = true }.disabled(model.busy)
        Button("丢弃预览") { model.discard() }.disabled(model.busy)
      }
      if model.busy { ProgressView("正在处理…") }
      if let message = model.message { Text(message).foregroundStyle(.secondary) }
      Spacer()
    }.padding(20).frame(width: 560, height: 410)
    .onDisappear { model.close() }
    .alert("替换完整云词库？", isPresented: $restoring) {
      Button("取消", role: .cancel) { }
      Button("确认恢复", role: .destructive) { model.restore() }
    } message: { Text("此操作将替换全部云端个人词库及学习、删除和排序记录。预览后云端有新变化时会拒绝恢复，请重新选择并确认。") }
  }
}
