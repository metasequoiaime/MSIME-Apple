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
  /// 确认按钮说的是接下来会发生什么。关闭这一项原本复用了清空的文案「确认清空」,而它做的是两件事。
  var confirmTitle: String {
    switch self {
    case .enable: return "开启"
    case .disable: return "关闭并清空"
    case .clear: return "确认清空"
    }
  }
}

struct CloudClipboardView: View {
  let session: BackendAccountSession
  let client: BackendAccountClient
  @State private var accountID: String?
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
          // 开关而不是按钮。这一行要回答的是「现在开着还是关着」,而按钮只说得出下一步动作 —— 读到「开启云剪贴板」的人得自己反推出当前是关的。两个方向都先问一次:关掉会连云端历史一起删。对话框没确认时 enabled 不动,开关自己弹回原位。
          Toggle("云剪贴板", isOn: Binding(
            get: { enabled },
            set: { confirmation = $0 ? .enable : .disable }
          ))
          .accessibilityIdentifier("cloudClipboardSwitch")
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
                Button("复制") { run { _ in UIPasteboard.general.string = item.text } }
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
    .task { run { _ in } }
    .onDisappear { pending?.cancel(); items = []; text = "" }
    .confirmationDialog(confirmation?.title ?? "", isPresented: Binding(
      get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })) {
      if let action = confirmation {
        Button(action.confirmTitle, role: action == .enable ? nil : .destructive) {
          run { token in
            if action == .clear { try await client.deleteClipboard(token: token) }
            else { try await client.setClipboardEnabled(action == .enable, token: token) }
          }
        }
      }
      Button("取消", role: .cancel) { confirmation = nil }
    }
  }
  @MainActor private func run(_ action: @escaping (String) async throws -> Void) {
    guard !busy else { return }
    busy = true; message = nil
    pending = Task { await execute(action) }
  }
  @MainActor private func execute(_ action: (String) async throws -> Void) async {
    defer { busy = false }
    do {
      let identity = try await session.credentials(matchingUserID: accountID)
      try Task.checkCancellation()
      accountID = identity.userID
      try await action(identity.token)
      let page = try await client.clipboard(token: identity.token, search: search)
      _ = try await session.credentials(matchingUserID: identity.userID)
      try Task.checkCancellation()
      enabled = page.enabled; items = page.items; loaded = true
    } catch is CancellationError { items = []; text = ""; loaded = false }
    catch let error as BackendAccountClient.Failure { items = []; loaded = false; message = error.localizedDescription }
    catch { items = []; loaded = false; message = "连接未完成，请检查网络后重试。" }
  }
}
