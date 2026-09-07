import SwiftUI
import UIKit

struct SkinSettingsView: View {
  @AppStorage(KeyboardSkinPreference.key, store: KeyboardFeedbackPreference.defaults)
  private var skin = KeyboardSkin.forest.rawValue

  var body: some View {
    Form {
      Section {
        ForEach(KeyboardSkin.allCases, id: \.rawValue) { option in
          Button {
            skin = option.rawValue
          } label: {
            HStack(spacing: 14) {
              RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: option.accent))
                .frame(width: 38, height: 38)
              Text(option.title).foregroundStyle(.primary)
              Spacer()
              if skin == option.rawValue { Image(systemName: "checkmark") }
            }
          }
          .accessibilityIdentifier("skin_\(option.rawValue)")
          .accessibilityValue(skin == option.rawValue ? "已选择" : "未选择")
        }
      } footer: {
        Text("下次打开水杉键盘时应用。深色外观随系统切换。")
      }
      Section("配色预览") {
        let selected = KeyboardSkin(rawValue: skin) ?? .forest
        HStack {
          ForEach(["ABC", "DEF", "空格"], id: \.self) { title in
            Text(title).frame(maxWidth: .infinity).padding(.vertical, 16)
              .background(.background, in: RoundedRectangle(cornerRadius: 8))
          }
          Image(systemName: "return").foregroundStyle(.white).padding(16)
            .background(Color(uiColor: selected.accent), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(8).background(Color(uiColor: selected.background))
      }
    }
    .navigationTitle("皮肤")
    .navigationBarTitleDisplayMode(.inline)
  }
}

struct DictionarySettingsView: View {
  private var manifest: [String: Any] {
    guard let url = Bundle.main.url(forResource: "dictionary-manifest", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return object
  }
  var body: some View {
    Form {
      Section("已安装词库") {
        Label("内置离线拼音词库", systemImage: "checkmark.circle.fill")
        Text("支持全拼 26 键、全拼 9 键和小鹤双拼。")
          .foregroundStyle(.secondary)
        HStack {
          Text("更新方式")
          Spacer()
          Text("随 App 更新").foregroundStyle(.secondary)
        }
      }
      Section("词库信息") {
        if let profile = manifest["profile"] as? String {
          HStack { Text("规格"); Spacer(); Text(profile).foregroundStyle(.secondary) }
        }
        if let source = manifest["source"] as? [String: Any], let commit = source["commit"] as? String {
          VStack(alignment: .leading, spacing: 6) {
            Text("词库版本")
            Text(String(commit.prefix(12))).font(.system(.footnote, design: .monospaced))
              .foregroundStyle(.secondary)
          }
        }
        Text("词库保存在设备上，日常拼音输入不需要联网。")
      }
      Section {
        Text("当前 iOS 版暂不支持导入第三方词库或编辑个人词库。")
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("词库")
    .navigationBarTitleDisplayMode(.inline)
  }
}

struct ServiceSettingsView: View {
  let kind: CustomServiceKind
  @Environment(\.scenePhase) private var scenePhase
  @State private var configuration: CustomServiceConfiguration
  @State private var providerDrafts: [AIProviderPreset: CustomServiceConfiguration] = [:]
  @State private var token = ""
  @State private var input = ""
  @State private var output = ""
  @State private var status = ""
  @State private var busy = false
  @State private var operation: Task<Void, Never>?
  @State private var requestID = UUID()
  @StateObject private var recorder = VoiceRecorder()

  init(kind: CustomServiceKind) {
    self.kind = kind
    _configuration = State(initialValue: CustomServiceConfiguration.load(kind))
  }

  var body: some View {
    Form {
      if kind == .ai { providerSection }
      configurationSection

      if kind == .ai {
        Section("AI 润色") {
          TextEditor(text: $input).frame(minHeight: 100)
            .accessibilityLabel("待润色文字").accessibilityIdentifier("aiInputText")
          Button(busy ? "正在处理…" : "发送并润色") { send() }
            .disabled(busy || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      } else {
        Section {
          Button(recorder.isRecording ? "停止录音" : "开始录音") {
            if recorder.isRecording { recorder.stop() }
            else {
              operation = Task {
                do { try await recorder.start() }
                catch is CancellationError {} catch { status = error.localizedDescription }
              }
            }
          }
          .disabled(busy || recorder.isPreparing)
          if recorder.isRecording { Label("正在录音，最长 60 秒", systemImage: "mic.fill").foregroundStyle(.red) }
          if recorder.audio != nil && !recorder.isRecording {
            Text("录音已准备好，尚未上传。")
            Button(busy ? "正在识别…" : "发送录音并识别") { send() }.disabled(busy)
            Button("删除录音", role: .destructive) { recorder.discard() }.disabled(busy)
          }
        } header: {
          Text("语音转文字")
        } footer: {
          Text("在水杉 App 中录音并复制识别结果。iOS 键盘扩展不能直接录音。")
        }
      }
      if busy {
        Button("取消请求") { cancelRequest(); status = "已取消" }
      }
      if !status.isEmpty {
        Section { Text(status).accessibilityIdentifier("serviceStatus") }
      }
      if !output.isEmpty {
        Section("结果") {
          Text(output).textSelection(.enabled)
          Button("复制结果") { UIPasteboard.general.string = output; status = "已复制" }
        }
      }
      Section {
        Text(kind == .ai
          ? "仅在点击发送时，将上方文字发送到你配置的服务。键盘日常输入不会自动上传。"
          : "仅在点击发送时，将本次录音发送到你配置的服务。离开页面会清除本地录音。")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
    .navigationTitle(kind.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("完成") {
          UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }.accessibilityIdentifier("serviceDismissKeyboard")
      }
    }
    .onDisappear { cancelAndClear() }
    .onChange(of: scenePhase) { phase in
      if phase == .background { cancelAndClear() }
    }
  }

  private var providerSection: some View {
        Section {
          Picker("服务商", selection: Binding(get: { configuration.provider }, set: { provider in selectProvider(provider) })) {
            ForEach(AIProviderPreset.allCases, id: \.self) { provider in
              Text(provider.title).tag(provider)
            }
          }
          .pickerStyle(.menu)
          .accessibilityIdentifier("aiProviderPicker")
          if let documentation = configuration.provider.documentation {
            Link("服务商接入说明", destination: documentation)
          }
        } header: {
          Text("AI 服务商")
        } footer: {
          Text("选择后自动填入接口和模型，填写对应服务商的 API Key 后即可使用。其他地区或代理地址请选择自定义。")
        }
        .disabled(busy)
  }

  private var configurationSection: some View {
      Section {
        TextField(kind.example, text: $configuration.endpoint)
          .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
          .accessibilityLabel("API 接口地址").accessibilityIdentifier("serviceEndpoint")
          .disabled(kind == .ai && configuration.provider != .custom)
        TextField("模型名称", text: $configuration.model)
          .textInputAutocapitalization(.never).autocorrectionDisabled()
          .accessibilityIdentifier("serviceModel")
        if kind == .ai && !configuration.provider.models.isEmpty {
          Menu("选择常用模型") {
            ForEach(configuration.provider.models, id: \.self) { model in
              Button(model) { configuration.model = model }
            }
          }
        }
        SecureField("API Key（留空保留已保存密钥）", text: $token)
          .textInputAutocapitalization(.never).autocorrectionDisabled()
          .accessibilityIdentifier("serviceToken")
        if kind == .ai {
          TextField("润色要求", text: $configuration.prompt)
            .accessibilityIdentifier("servicePrompt")
        }
        Button("保存配置") { save() }
          .accessibilityIdentifier("saveServiceConfiguration")
        Button("删除此服务的密钥", role: .destructive) {
          do {
            let url = try configuration.validatedURL()
            try ServiceTokenStore.write("", kind: kind, url: url)
            token = ""
            status = "已删除此服务的密钥"
          } catch { status = error.localizedDescription }
        }
      } header: {
        Text(kind == .ai ? configuration.provider.title : "自定义语音服务")
      } footer: {
        Text("填写完整接口地址。密钥保存在本机钥匙串，按服务地址分别保存。")
      }
      .disabled(busy || recorder.isRecording)

  }

  private func selectProvider(_ provider: AIProviderPreset) {
    guard provider != configuration.provider else { return }
    providerDrafts[configuration.provider] = configuration
    configuration = providerDrafts[provider] ?? CustomServiceConfiguration.loadPreset(provider)
    // Unsaved key text must never follow an endpoint change. Saved keys are origin-scoped.
    token = ""
    status = ""
    output = ""
  }

  @discardableResult private func save() -> Bool {
    do {
      try configuration.save(kind, token: token)
      token = ""
      status = "配置已保存"
      return true
    } catch { status = error.localizedDescription; return false }
  }
  private func send() {
    guard save() else { return }
    busy = true
    status = ""
    output = ""
    let config = configuration
    let text = input
    let audio = recorder.audio
    requestID = UUID()
    let id = requestID
    operation = Task {
      do {
        let savedToken = try ServiceTokenStore.read(kind, url: config.validatedURL())
        let result = try await CustomServiceClient.request(kind: kind, configuration: config,
          text: text, wav: audio, token: savedToken)
        try Task.checkCancellation()
        guard requestID == id else { return }
        output = result
        status = "已完成"
      } catch is CancellationError {
        if requestID == id { status = "已取消" }
      } catch {
        if requestID == id && !Task.isCancelled { status = error.localizedDescription }
      }
      if requestID == id { busy = false }
    }
  }
  private func cancelRequest() {
    requestID = UUID()
    operation?.cancel()
    busy = false
  }
  private func cancelAndClear() {
    cancelRequest()
    recorder.discard()
  }
}
