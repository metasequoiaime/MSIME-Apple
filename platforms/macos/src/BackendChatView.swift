import AppKit
import SwiftUI

@MainActor
final class MacChatModel: ObservableObject {
  struct Message: Identifiable {
    let id = UUID()
    let role: String
    let text: String
  }
  @Published var messages: [Message] = []
  @Published var models: [BackendAccountClient.ChatModels.Model] = []
  @Published var selectedModel = ""
  @Published var draft = ""
  @Published var busy = false
  @Published var error: String?
  private let accountID: String
  private let client: BackendAccountClient
  private let account: BackendAccountSession
  private var pending: Task<Void, Never>?
  private var generation = 0
  private var customConfiguration: CustomServiceConfiguration?
  private var customRevision = ""
  private var writingTemplate: MacReplyTemplate?
  private let templates: MacReplyTemplateStore

  init(accountID: String, client: BackendAccountClient = BackendAccountClient(), account: BackendAccountSession = .shared, templates: MacReplyTemplateStore? = nil) {
    self.accountID = accountID; self.client = client; self.account = account; self.templates = templates ?? .shared
  }
  var canSend: Bool {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !busy, models.contains(where: { $0.id == selectedModel }), !text.isEmpty, text.utf8.count <= 16384,
          let encoded = try? JSONEncoder().encode([BackendAccountClient.ChatMessage(role: "user", content: text)]) else { return false }
    return encoded.count <= 60000
  }
  private func credentials(retrying token: String? = nil) async throws -> (userID: String, token: String) {
    try Task.checkCancellation()
    return try await account.credentials(retrying: token, matchingUserID: accountID)
  }
  private func run(_ action: @escaping @MainActor () async throws -> Void) {
    guard !busy else { return }
    generation += 1
    let version = generation
    busy = true; error = nil
    pending = Task {
      defer { if generation == version { busy = false; pending = nil } }
      do { try await action() }
      catch is CancellationError { }
      catch { if !Task.isCancelled && generation == version { self.error = error.localizedDescription } }
    }
  }
  func load() {
    run {
      let identity = try await self.credentials()
      let catalog = try await self.client.chatModels(token: identity.token)
      _ = try await self.credentials()
      try Task.checkCancellation()
      self.models = catalog.data
      if !self.models.contains(where: { $0.id == self.selectedModel }) { self.selectedModel = catalog.default_model }
    }
  }
  func send() {
    guard canSend else { return }
    messages.append(Message(role: "user", text: draft.trimmingCharacters(in: .whitespacesAndNewlines)))
    draft = ""
    submit()
  }
  func generateSkin(description: String) {
    guard !busy, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, description.count <= 600 else { return }
    draft = description
    guard canSend else { return }
    customConfiguration = nil; writingTemplate = nil
    messages = [Message(role: "system", text: GeneratedCandidateSkin.instruction), Message(role: "user", text: description)]
    draft = ""; submit()
  }
  // Writing requests are independent transformations, never continuations of chat.
  func generateWriting(text: String, task: WritingTask, style: String, template: MacReplyTemplate? = nil) {
    guard !busy, WritingTask.styles.contains(style) else { return }
    draft = text
    guard canSend else { error = "请确认模型，并缩短或填写待发送文字。"; return }
    let input = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    customConfiguration = nil; writingTemplate = template
    messages = [Message(role: "system", text: task.prompt(style: style, templatePrompt: template?.prompt)), Message(role: "user", text: input)]
    draft = ""
    submit()
  }
  func generateCustomWriting(text: String, task: WritingTask, style: String,
    configuration: CustomServiceConfiguration, template: MacReplyTemplate? = nil,
    request: @escaping @MainActor (CustomServiceConfiguration, String) async throws -> String = { config, text in
      try await MacWritingService.request(config, text: text)
    }) {
    guard !busy, WritingTask.styles.contains(style) else { return }
    let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !input.isEmpty, input.count <= 10000, configuration.prompt.utf8.count <= 16384 else {
      error = "请填写原文，每次最多一万字。"; return
    }
    customConfiguration = configuration; customRevision = MacWritingService.revision; writingTemplate = template
    var outgoing = configuration
    outgoing.prompt = task.prompt(style: style, templatePrompt: template?.prompt) + (task == .polish && template == nil ? "\n" + configuration.prompt : "")
    messages = [Message(role: "system", text: outgoing.prompt), Message(role: "user", text: input)]
    run {
      try await self.authorizeOutput()
      let output = try await request(outgoing, input)
      try Task.checkCancellation()
      try await self.authorizeOutput()
      guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, output.count <= 10000 else {
        throw ServiceFailure(message: "返回文字为空或超过一万字。")
      }
      self.messages.append(Message(role: "assistant", text: output))
    }
  }
  func retry() {
    guard !busy, messages.last?.role == "user", models.contains(where: { $0.id == selectedModel }) else { return }
    submit()
  }
  private func submit() {
    // Measure the encoded request context, including JSON escapes, against the service limit.
    var history: [BackendAccountClient.ChatMessage] = []
    for message in messages.reversed() {
      let candidate = [BackendAccountClient.ChatMessage(role: message.role, content: message.text)] + history
      guard candidate.count <= 14, let encoded = try? JSONEncoder().encode(candidate), encoded.count <= 60000 else { break }
      history = candidate
    }
    guard !history.isEmpty else { error = "消息编码后过长，请缩短内容后重新发送。"; return }
    let context = history, model = selectedModel
    run {
      try await self.authorizeOutput()
      var identity = try await self.credentials()
      let reply: String
      do { reply = try await self.client.chat(messages: context, model: model, token: identity.token) }
      catch let failure as BackendAccountClient.Failure where failure.status == 401 {
        identity = try await self.credentials(retrying: identity.token)
        reply = try await self.client.chat(messages: context, model: model, token: identity.token)
      }
      try await self.authorizeOutput()
      try Task.checkCancellation()
      self.messages.append(Message(role: "assistant", text: reply))
    }
  }
  func authorizeOutput() async throws {
    try Task.checkCancellation()
    if let writingTemplate, !(try templates.read()).contains(writingTemplate) {
      throw ServiceFailure(message: "回复模板已更新或移除，请重新选择模板生成。")
    }
    if let customConfiguration {
      guard customConfiguration == MacWritingService.configuration, customRevision == MacWritingService.revision else {
        throw ServiceFailure(message: "AI 服务配置已变化，请重新生成。")
      }
      _ = try customConfiguration.validatedURL()
    } else { _ = try await credentials() }
  }
  func stop() { generation += 1; pending?.cancel(); pending = nil; busy = false }
  func clear() { stop(); messages = []; error = nil; customConfiguration = nil; writingTemplate = nil }
  func close() { clear(); draft = ""; models = []; selectedModel = "" }
}

struct MacChatView: View {
  @StateObject private var model: MacChatModel
  @Environment(\.dismiss) private var dismiss
  @State private var clearing = false
  init(accountID: String) { _model = StateObject(wrappedValue: MacChatModel(accountID: accountID)) }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("AI 对话").font(.title2)
        Spacer()
        Button("新对话") { clearing = true }.disabled(model.messages.isEmpty)
        Button("关闭") { model.close(); dismiss() }.keyboardShortcut(.cancelAction)
      }
      Text("点击发送后，本次对话会经水杉后端交由 EveryAPI 处理。可在输入框中试用水杉输入法，回复可复制到其他应用。")
        .font(.footnote).foregroundStyle(.secondary)
      HStack {
        Picker("模型", selection: $model.selectedModel) {
          ForEach(model.models) { Text($0.id).tag($0.id) }
        }.disabled(model.busy || model.models.isEmpty)
        Button("刷新模型") { model.load() }.disabled(model.busy)
      }
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(model.messages) { message in
              VStack(alignment: .leading, spacing: 6) {
                Text(message.role == "user" ? "你" : "AI").font(.caption).foregroundStyle(.secondary)
                Text(message.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                if message.role == "assistant" {
                  Button("复制回复") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.text, forType: .string)
                  }
                }
              }.padding(12).background(Color(nsColor: .controlBackgroundColor)).cornerRadius(8).id(message.id)
            }
            Color.clear.frame(height: 1).id("bottom")
          }
        }.onChange(of: model.messages.count) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
      }
      if let error = model.error { Text(error).foregroundStyle(.secondary) }
      if !model.busy && model.messages.last?.role == "user" { Button("重新发送") { model.retry() } }
      TextEditor(text: $model.draft).font(.body).frame(height: 90)
        .border(Color.secondary.opacity(0.3)).accessibilityLabel("消息内容")
      if model.draft.utf8.count > 16384 {
        Text("消息过长，请缩短后发送。").font(.caption).foregroundStyle(.secondary)
      }
      HStack {
        Text("⌘Return 发送 · Return 换行").font(.caption).foregroundStyle(.secondary)
        Spacer()
        if model.busy { ProgressView().controlSize(.small); Button("停止") { model.stop() } }
        Button("发送") { model.send() }.keyboardShortcut(.return, modifiers: .command).disabled(!model.canSend)
      }
    }.padding(20).frame(minWidth: 560, idealWidth: 620, minHeight: 520, idealHeight: 640)
      .onAppear { model.load() }.onDisappear { model.close() }
      .alert("开始新对话？", isPresented: $clearing) {
        Button("取消", role: .cancel) { }
        Button("清空对话", role: .destructive) { model.clear() }
      } message: { Text("当前窗口中的消息将被清空。") }
  }
}
