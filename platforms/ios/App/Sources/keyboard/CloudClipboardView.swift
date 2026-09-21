import SwiftUI

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
  @State private var confirmsClear = false
  @State private var pending: Task<Void, Never>?

  private var canUpload: Bool {
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf16.count <= 4000
  }

  var body: some View {
    Form {
      Section {
        if loaded {
          Toggle("云剪贴板", isOn: Binding(
            get: { enabled },
            set: { on in run { token in try await client.setClipboardEnabled(on, token: token) } }
          ))
          .accessibilityIdentifier("cloudClipboardSwitch")
        }
      } footer: {
        Text("只上传你在此页面明确添加的内容，不自动读取系统剪贴板。最多保存 50 条。关闭时会删除云端历史。")
      }
      if enabled {
        Section {
          TextEditor(text: $text).frame(minHeight: 100).accessibilityIdentifier("cloudClipboardText")
          SettingsActionRow(title: "上传这段文字", symbol: "arrow.up.doc.fill",
                            enabled: canUpload) {
            run { token in
              _ = try await client.addClipboard(text, token: token)
              text = ""
            }
          }
        } header: {
          Text("添加内容")
        } footer: {
          Text("\(text.utf16.count) / 4000")
            .foregroundStyle(text.utf16.count > 4000 ? .red : .secondary)
            .monospacedDigit()
        }

        Section {
          ForEach(items) { item in
            Button {
              run { _ in UIPasteboard.general.string = item.text }
            } label: {
              HStack(spacing: 12) {
                Text(item.text).lineLimit(3).foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: "doc.on.doc").font(.caption).foregroundStyle(.secondary)
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing) {
              Button("删除", role: .destructive) {
                run { token in try await client.deleteClipboard(id: item.id, token: token) }
              }
            }
          }
          if items.isEmpty {
            Text(search.isEmpty ? "还没有保存任何内容" : "没有匹配「\(search)」的内容").foregroundStyle(.secondary)
        }
        if !items.isEmpty {
          SettingsActionRow(title: "清空历史", symbol: "trash.fill", destructive: true) { confirmsClear = true }
          }
        } header: {
          Text("云端历史")
        } footer: {
          Text("点一条即复制到系统剪贴板，左滑删除单条。")
        }
      }
      if !loaded && !busy {
        Section {
          SettingsActionRow(title: "重试", detail: "没能读到云端内容", symbol: "arrow.clockwise") { run { _ in } }
        }
      }
    }
    .searchable(text: $search, prompt: "搜索云端内容")
    .onSubmit(of: .search) { run { _ in } }
    .settingsStatus(busy: busy, message: message)
    .disabled(busy)
    .navigationTitle("云剪贴板")
    .task { run { _ in } }
    .onDisappear { pending?.cancel(); items = []; text = "" }
    .confirmationDialog("清空云剪贴板？", isPresented: $confirmsClear, titleVisibility: .visible) {
      Button("确认清空", role: .destructive) {
        run { token in try await client.deleteClipboard(token: token) }
      }
      Button("取消", role: .cancel) { }
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
