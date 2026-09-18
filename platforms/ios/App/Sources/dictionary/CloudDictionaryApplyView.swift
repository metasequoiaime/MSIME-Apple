import SwiftUI

struct CloudDictionaryApplyView: View {
  let accountID: String
  let authorize: () async throws -> String
  @State private var state = DictionarySnapshotQueueState()
  @State private var preview: BackendPreparedSnapshot?
  @State private var expectedVersion: String?
  @State private var confirming = false
  @State private var busy = false
  @State private var message: String?
  @State private var probe = ""
  @State private var pending: Task<Void, Never>?
  private let queue = DictionarySnapshotQueue()
  private let client = BackendAccountClient()

  var body: some View {
    List {
      Section("准备本地词库") {
        Text("请启用水杉键盘的完全访问权限，并在下方打开水杉键盘，让键盘提供当前词库版本。测试区内容不会上传。")
          .font(.footnote).foregroundStyle(.secondary)
        TextField("点此打开水杉键盘", text: $probe)
          .textInputAutocapitalization(.never).autocorrectionDisabled()
        Text(state.localVersion == nil ? "尚未获取键盘词库版本。" : "已获取本地词库版本。")
        Button("下载云词库并预览") { download() }
          .disabled(busy || state.localVersion == nil || state.request?.status.active == true)
      }
      if let preview {
        Section("确认应用") {
          Text("云端版本 \(preview.envelope.revision)")
          Text("\(preview.envelope.entries) 个个人词条，\(preview.envelope.overlays) 条覆盖记录，\(preview.envelope.positions) 个固定位置。")
          Text("应用会替换本机个人词库、学习、删除和排序记录。下载期间本机状态发生变化时，键盘会拒绝本次应用。")
            .font(.footnote).foregroundStyle(.secondary)
          Button("替换本机词库", role: .destructive) { confirming = true }.disabled(busy)
          Button("丢弃预览") { self.preview = nil; expectedVersion = nil }.disabled(busy)
        }
      }
      if let request = state.request, request.accountID == accountID {
        Section("处理结果") {
          Text(status(request.status))
          if request.status.active {
            Text("保持水杉键盘开启，等待准备完成；结束当前输入后会尝试应用。")
              .font(.footnote).foregroundStyle(.secondary)
            Button("取消待应用快照", role: .destructive) {
              do { try queue.cancel(accountID: accountID); refresh() }
              catch { message = error.localizedDescription }
            }
          }
        }
      }
      if busy { ProgressView("正在准备…") }
      if let message { Text(message).foregroundStyle(.secondary) }
    }
    .navigationTitle("应用云词库")
    .task {
      while !Task.isCancelled {
        refresh()
        do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
      }
    }
    .onDisappear { pending?.cancel(); preview = nil; expectedVersion = nil; probe = "" }
    .alert("替换本机词库？", isPresented: $confirming) {
      Button("取消", role: .cancel) { }
      Button("确认替换", role: .destructive) { enqueue() }
    } message: { Text("将以这份云端快照替换本机个人词库及学习记录。确认后由水杉键盘在空闲时处理，请先确认云端数据完整。") }
  }
  private func status(_ value: DictionarySnapshotRequest.Status) -> String {
    switch value {
    case .queued: return "等待水杉键盘接收。"
    case .preparing: return "键盘正在准备词库或等待空闲会话。"
    case .applied: return "已应用到本机词库。"
    case .conflict: return "本地词库已变化，未应用。请重新下载并确认。"
    case .failed: return "准备失败，原有词库未更改。请重新下载后重试。"
    case .cancelled: return "待应用请求已取消。"
    }
  }
  @MainActor private func refresh() {
    do { state = try queue.read() }
    catch { message = error.localizedDescription }
  }
  @MainActor private func download() {
    guard !busy, let version = state.localVersion else { return }
    busy = true; message = nil; preview = nil
    pending = Task {
      defer { busy = false }
      do {
        guard try PersonalDictionaryStore().read().pendingCount == 0 else { throw DictionarySnapshotQueue.Failure.busy }
        let token = try await authorize()
        let file = try await client.dictionarySnapshot(token: token)
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
        let prepared = try await BackendPreparedSnapshot.prepareDocument(file.url)
        _ = try await authorize(); try Task.checkCancellation()
        preview = prepared; expectedVersion = version
      } catch is CancellationError { }
      catch { message = error.localizedDescription }
    }
  }
  @MainActor private func enqueue() {
    guard !busy, let preview, let version = expectedVersion else { return }
    busy = true; message = nil
    pending = Task {
      defer { busy = false }
      do {
        let token = try await authorize()
        let changes = try await client.dictionaryChanges(after: preview.envelope.revision, limit: 1, token: token)
        _ = try await authorize(); try Task.checkCancellation()
        guard changes.changes.isEmpty else {
          self.preview = nil; expectedVersion = nil
          message = "预览后云词库已变化，请重新下载并确认。"
          return
        }
        let copy = Task.detached(priority: .utility) {
          try queue.enqueue(file: preview.url, accountID: accountID, cloudRevision: preview.envelope.revision,
            expectedLocalVersion: version, fileSHA256: preview.fileSHA256)
        }
        _ = try await withTaskCancellationHandler(operation: { try await copy.value }, onCancel: { copy.cancel() })
        self.preview = nil; expectedVersion = nil; refresh()
      } catch is CancellationError { }
      catch { message = error.localizedDescription }
    }
  }
}
