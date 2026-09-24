import SwiftUI

/// 「润色服务」, the desktop voice page's 文本润色 API: the polish pass after recognition follows 「AI 设置」 by default and can be given a provider, model and key of its own.
struct VoicePolishServiceView: View {
  @Binding var service: VoicePolishService
  @State private var draft: VoicePolishService
  @State private var token = ""
  @State private var status = ""
  @State private var testing = false
  @State private var operation: Task<Void, Never>?

  init(service: Binding<VoicePolishService>) {
    _service = service
    _draft = State(initialValue: service.wrappedValue)
  }

  var body: some View {
    Form {
      Section {
        Toggle("单独设置润色服务", isOn: $draft.separate)
          .accessibilityIdentifier("voicePolishSeparate")
          .onChange(of: draft.separate) { separate in
            // Going back to 「AI 设置」 needs nothing else, so it is saved at once; a separate service waits for 保存.
            if !separate { save() }
          }
      } footer: {
        Text(draft.separate
          ? "润色请求发给下面的服务，密钥单独存在本机钥匙串，不写入可同步的设置。"
          : "润色使用“AI 设置”里保存的服务和密钥。")
      }
      if draft.separate {
        Section("服务") {
          Picker("服务商", selection: Binding(get: { draft.provider }, set: { draft.select($0) })) {
            ForEach(AIProviderPreset.allCases, id: \.self) { Text($0.title).tag($0) }
          }
          .accessibilityIdentifier("voicePolishProvider")
          TextField("接口地址", text: $draft.endpoint)
            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            .accessibilityIdentifier("voicePolishEndpoint")
          TextField("模型", text: $draft.model)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .accessibilityIdentifier("voicePolishModel")
          if !draft.provider.models.isEmpty {
            Picker("常用模型", selection: $draft.model) {
              ForEach(draft.provider.models, id: \.self) { Text($0).tag($0) }
              if !draft.provider.models.contains(draft.model) { Text("自定义").tag(draft.model) }
            }
          }
          SecureField("API Key（留空则保留已保存的）", text: $token)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .accessibilityIdentifier("voicePolishToken")
        }
        Section {
          Button { test() } label: {
            HStack {
              Label(testing ? "正在测试…" : "测试连接", systemImage: "checkmark.seal")
              Spacer()
              if testing { ProgressView() }
            }
          }
          .disabled(testing)
          .accessibilityIdentifier("voicePolishTest")
          Button { save() } label: {
            Label("保存", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("voicePolishSave")
        } footer: {
          if !status.isEmpty { Text(status).accessibilityIdentifier("voicePolishStatus") }
        }
      }
    }
    .navigationTitle("润色服务")
    .onDisappear { operation?.cancel() }
  }

  private func save() {
    do {
      try draft.save(token: token.trimmingCharacters(in: .whitespacesAndNewlines))
      service = VoicePolishService.load()
      token = ""
      status = draft.separate ? "已保存。" : ""
    } catch { status = error.localizedDescription }
  }

  /// Checks the endpoint, model and key as typed, before saving; a blank key uses the saved one.
  private func test() {
    let configuration = draft.configuration
    do {
      let url = try configuration.validatedURL()
      let entered = token.trimmingCharacters(in: .whitespacesAndNewlines)
      let key = try entered.isEmpty ? ServiceTokenStore.read(scope: ServiceTokenStore.polishScope, url: url) : entered
      guard !key.isEmpty else { status = "请先填写 API Key，或使用已保存的密钥。"; return }
      testing = true
      status = ""
      operation = Task {
        do {
          try await CustomServiceClient.test(kind: .ai, configuration: configuration, token: key)
          if !Task.isCancelled { status = "连接成功，API Key 和模型配置有效。" }
        } catch is CancellationError {
        } catch {
          if !Task.isCancelled { status = "测试失败：\(error.localizedDescription)" }
        }
        testing = false
      }
    } catch { status = error.localizedDescription }
  }
}
