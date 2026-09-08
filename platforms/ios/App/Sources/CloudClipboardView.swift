import SwiftUI

private enum ClipboardConfirmation: String, Identifiable {
  case enable, disable, clear
  var id: String { rawValue }
  var title: String {
    switch self {
    case .enable: return "开启云剪贴板？"
    case .disable: return "关闭并清空云剪贴板？"
    case .clear: return "清空云剪贴板？"
    }
  }
}

struct CloudClipboardView: View {
  let session: BackendAccountSession
  let client: BackendAccountClient
  @State private var enabled = false
  @State private var loaded = false
  @State private var items: [BackendAccountClient.ClipboardItem] = []
  @State private var search = ""
  @State private var text = ""
  @State private var busy = false
  @State private var message: String?
  @State private var confirmation: ClipboardConfirmation?
  @State private var pending: Task<Void, Never>?

  var body: some View {
    Form {
      Section {
        if loaded {
          Button(enabled ? "关闭云剪贴板" : "开启云剪贴板") {
            confirmation = enabled ? .disable : .enable
          }
        }
      } footer: {
        Text("只上传你在此页面明确添加的内容，不自动读取系统剪贴板。最多保存 50 条。关闭时会删除云端历史。")
      }
      if enabled {
        Section("添加内容") {
          TextEditor(text: $text).frame(minHeight: 100).accessibilityIdentifier("cloudClipboardText")
          Text("长度：\(text.utf16.count) / 4000")
            .font(.caption).foregroundStyle(text.utf16.count > 4000 ? .red : .secondary)
          Button("上传这段文字") {
            run { token in
              _ = try await client.addClipboard(text, token: token)
              text = ""
            }
          }
          .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.utf16.count > 4000)
        }
        Section("云端历史") {
          TextField("搜索", text: $search).onSubmit { run { _ in } }
          Button("搜索 / 刷新") { run { _ in } }
          ForEach(items) { item in
            VStack(alignment: .leading, spacing: 8) {
              Text(item.text).textSelection(.enabled)
              HStack {
                Button("复制") { UIPasteboard.general.string = item.text }
                Spacer()
                Button("删除", role: .destructive) { run { token in try await client.deleteClipboard(id: item.id, token: token) } }
              }
              .buttonStyle(.borderless)
            }
          }
          if items.isEmpty { Text("暂无匹配内容").foregroundStyle(.secondary) }
          Button("清空历史", role: .destructive) { confirmation = .clear }.disabled(items.isEmpty)
        }
      }
      if busy { ProgressView("正在处理…") }
      if let message { Text(message).foregroundStyle(.secondary) }
      if !loaded && !busy { Button("重试") { run { _ in } } }
    }
    .disabled(busy)
    .navigationTitle("云剪贴板")
    .task { await execute { _ in } }
    .onDisappear { pending?.cancel(); items = []; text = "" }
    .confirmationDialog(confirmation?.title ?? "", isPresented: Binding(
      get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })) {
      if let action = confirmation {
        Button(action == .enable ? "开启" : "确认清空", role: action == .enable ? nil : .destructive) {
          run { token in
            if action == .clear { try await client.deleteClipboard(token: token) }
            else { try await client.setClipboardEnabled(action == .enable, token: token) }
          }
        }
      }
      Button("取消", role: .cancel) { confirmation = nil }
    }
  }
  private func run(_ action: @escaping (String) async throws -> Void) {
    pending = Task { await execute(action) }
  }
  @MainActor private func execute(_ action: (String) async throws -> Void) async {
    guard !busy else { return }
    busy = true; message = nil
    defer { busy = false }
    do {
      let token = try await session.accessToken()
      try await action(token)
      let page = try await client.clipboard(token: token, search: search)
      try Task.checkCancellation()
      enabled = page.enabled; items = page.items; loaded = true
    } catch is CancellationError { }
    catch let error as BackendAccountClient.Failure { message = error.localizedDescription }
    catch { message = "连接未完成，请检查网络后重试。" }
  }
}
