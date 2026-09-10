import AppKit
import SwiftUI

struct MacWritingView: View {
  @StateObject private var model: MacChatModel
  @Environment(\.dismiss) private var dismiss
  @State private var task = WritingTask.polish
  @State private var style = "自然"
  @State private var input = ""
  @State private var results: [String] = []
  @State private var status = ""
  private let accountID: String
  @State private var usingCustom = false
  @State private var serviceSettings = false
  @State private var templateID = ""
  @State private var templates: [MacReplyTemplate] = []
  @State private var community = false
  private let context: MacWritingContext?
  private let closeWindow: (() -> Void)?
  @State private var applying = false
  @State private var applyGeneration = UUID()
  @State private var applyOperation: Task<Void, Never>?

  init(accountID: String, context: MacWritingContext? = nil, close: (() -> Void)? = nil) {
    _model = StateObject(wrappedValue: MacChatModel(accountID: accountID))
    self.accountID = accountID
    _usingCustom = State(initialValue: accountID.isEmpty || UserDefaults.standard.bool(forKey: "MetasequoiaWritingUseCustom"))
    self.context = context; closeWindow = close
    _input = State(initialValue: context?.text ?? "")
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("AI 写作助手").font(.title2)
        Spacer()
        Button("关闭") { model.close(); context?.cancel(); if let closeWindow { closeWindow() } else { dismiss() } }.keyboardShortcut(.cancelAction)
      }
      Picker("任务", selection: $task) {
        ForEach(WritingTask.allCases) { Text($0.title).tag($0) }
      }.pickerStyle(.segmented)
      HStack {
        Picker("生成服务", selection: $usingCustom) {
          Text("水杉账户服务").tag(false); Text("自定义 AI 服务").tag(true)
        }
        Button("服务配置…") { serviceSettings = true }
        if !usingCustom && accountID.isEmpty { Button("登录账户") { BackendAccountWindow.shared.showAccount() } }
      }
      if usingCustom {
        Text("点击生成后，原文和风格将直接发送至 \(URL(string: MacWritingService.configuration.endpoint)?.host ?? "未配置的服务")。请核对结果后使用。")
          .font(.footnote).foregroundStyle(.secondary)
      } else { Text(context == nil ? "点击生成后，下方文字和所选风格会经水杉后端交由 EveryAPI 处理。结果由你确认后复制使用。" : "点击生成后，选中文字和风格会经水杉后端交由 EveryAPI 处理。确认结果后可替换原选区。")
        .font(.footnote).foregroundStyle(.secondary) }
      HStack {
        if usingCustom { Text("模型：" + MacWritingService.configuration.model).foregroundStyle(.secondary) }
        else { Picker("模型", selection: $model.selectedModel) {
          ForEach(model.models) { Text($0.id).tag($0.id) }
        }.disabled(model.busy)
        Button("刷新模型") { model.load() }.disabled(model.busy || accountID.isEmpty) }
        Picker("风格", selection: $style) {
          ForEach(WritingTask.styles, id: \.self) { Text($0).tag($0) }
        }.disabled(selectedTemplate != nil)
      }
      HStack {
        Picker("回复模板", selection: $templateID) {
          Text("使用内置风格").tag("")
          ForEach(templates) { Text("\($0.name) · v\($0.revision)").tag($0.id.uuidString) }
          if !templateID.isEmpty && selectedTemplate == nil { Text("模板不可用，请重选").tag(templateID) }
        }
        Button("社区模板…") { if accountID.isEmpty { BackendAccountWindow.shared.showAccount() } else { community = true } }
        if let selectedTemplate {
          Button("移除本机模板") {
            do { try MacReplyTemplateStore.shared.remove(selectedTemplate.id); reloadTemplates() }
            catch { status = error.localizedDescription }
          }
        }
      }
      if let selectedTemplate {
        DisclosureGroup("查看模板要求") {
          ScrollView { Text(selectedTemplate.prompt).textSelection(.enabled).font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 90)
        }
      }
      HStack {
        Text(task == .polish ? "待润色的原文" : "对方发来的话").font(.headline)
        Spacer()
        Button("粘贴") { input = NSPasteboard.general.string(forType: .string) ?? "" }
        Button("清空") { input = "" }
      }
      TextEditor(text: $input).font(.body).frame(minHeight: 100, maxHeight: 170)
        .border(Color.secondary.opacity(0.3)).accessibilityLabel("待发送文字")
      if inputTooLong { Text("文字过长，请缩短后发送。").foregroundStyle(.secondary) }
      HStack {
        if model.busy { ProgressView().controlSize(.small); Button("停止") { model.stop() } }
        if let error = model.error { Text(error).foregroundStyle(.secondary) }
        Spacer()
        Button(results.isEmpty ? "生成" : "再生成一条") {
          status = ""
          guard context?.valid != false else { status = "原选区已变化，请重新选择文字。"; return }
          if usingCustom {
            model.generateCustomWriting(text: input, task: task, style: style, configuration: MacWritingService.configuration, template: selectedTemplate)
          } else { model.generateWriting(text: input, task: task, style: style, template: selectedTemplate) }
        }.keyboardShortcut(.return, modifiers: .command)
          .disabled((!templateID.isEmpty && selectedTemplate == nil) || applying || model.busy || (!usingCustom && (accountID.isEmpty || model.models.isEmpty)) || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || inputTooLong)
      }
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if results.isEmpty { Text("生成结果会显示在这里，请核对后使用。").foregroundStyle(.secondary) }
          ForEach(results, id: \.self) { result in
            VStack(alignment: .leading, spacing: 8) {
              Text(result).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
              if let context {
                Button(applying ? "正在返回原应用…" : "替换原选区") {
                  applying = true
                  let operationID = UUID(); applyGeneration = operationID
                  let writingTask = task
                  applyOperation = Task { @MainActor in
                    do { try await model.authorizeOutput(); try Task.checkCancellation() }
                    catch {
                      guard applyGeneration == operationID else { return }
                      applying = false
                      if !Task.isCancelled { status = error.localizedDescription }
                      return
                    }
                    let inserted = await context.apply(result, task: writingTask) { try await model.authorizeOutput() }
                    guard applyGeneration == operationID else { return }
                    applying = false
                    if inserted { model.close(); closeWindow?() }
                    else if !Task.isCancelled {
                      status = "原选区、账户或服务配置已变化，或原应用未就绪，未替换文字。请重新检查后再使用。"
                      NSApp.activate(ignoringOtherApps: true)
                    }
                  }
                }.disabled(applying || model.busy)
              }
              Button("复制结果") {
                NSPasteboard.general.clearContents()
                status = NSPasteboard.general.setString(result, forType: .string) ? "已复制，请在目标应用中确认使用。" : "复制失败，请重试。"
              }
            }.padding(12).background(Color(nsColor: .controlBackgroundColor)).cornerRadius(8)
          }
        }
      }.frame(minHeight: 120)
      if !status.isEmpty { Text(status).font(.footnote).foregroundStyle(.secondary) }
    }.padding(20).frame(minWidth: 620, idealWidth: 680, minHeight: 560)
       .sheet(isPresented: $serviceSettings, onDismiss: { invalidate() }) { MacCustomWritingSettings() }
      .sheet(isPresented: $community, onDismiss: { reloadTemplates() }) {
        BackendCommunityResourcesView(accountID: accountID)
      }
      .onChange(of: templateID) { _ in invalidate() }
      .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in reloadTemplates() }
      .onAppear { reloadTemplates(); if !usingCustom && !accountID.isEmpty { model.load() } }
      .onChange(of: usingCustom) { custom in
        UserDefaults.standard.set(custom, forKey: "MetasequoiaWritingUseCustom")
        invalidate()
        if !custom && !accountID.isEmpty { model.load() }
      }
      .onDisappear { applyOperation?.cancel(); context?.cancel(); model.close() }
      .onChange(of: input) { _ in invalidate() }
      .onChange(of: task) { _ in invalidate() }
      .onChange(of: style) { _ in invalidate() }
      .onChange(of: model.selectedModel) { _ in invalidate() }
      .onChange(of: model.messages.last?.id) { _ in
        if let message = model.messages.last, message.role == "assistant", !results.contains(message.text) {
          results.insert(message.text, at: 0); results = Array(results.prefix(3))
        }
      }
  }
  private var selectedTemplate: MacReplyTemplate? { templates.first { $0.id.uuidString == templateID } }
  private func reloadTemplates() {
    let previous = selectedTemplate
    do { templates = try MacReplyTemplateStore.shared.read() }
    catch { templates = []; invalidate(); status = error.localizedDescription; return }
    if previous != selectedTemplate { invalidate() }
  }
  private var inputTooLong: Bool { usingCustom ? input.count > 10000 : input.utf8.count > 16384 }
  private func invalidate() {
    applyOperation?.cancel(); applyGeneration = UUID(); applying = false
    if !model.messages.isEmpty { model.clear() }
    results = []; status = ""
  }
}
