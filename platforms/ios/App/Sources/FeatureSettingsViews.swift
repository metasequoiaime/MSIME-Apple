import SwiftUI
import UIKit

struct SkinSettingsView: View {
  @AppStorage(KeyboardSkinPreference.key, store: KeyboardFeedbackPreference.defaults)
  private var skin = KeyboardSkin.forest.rawValue
  @State private var previewsNineKey = InputSchemePreference.scheme == .nineKey
  @State private var previewsDark = false

  var body: some View {
    Form {
      Section("完整键盘预览") {
        Picker("键盘布局", selection: $previewsNineKey) {
          Text("26 键").tag(false)
          Text("9 键").tag(true)
        }.pickerStyle(.segmented).accessibilityIdentifier("skinPreviewLayout")
        KeyboardSkinPreview(skin: KeyboardSkin(rawValue: skin) ?? .forest, nineKey: previewsNineKey)
          .environment(\.colorScheme, previewsDark ? .dark : .light)
          .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        Toggle("预览深色外观", isOn: $previewsDark)
          .accessibilityIdentifier("skinPreviewDark")
      }

      Section {
        ForEach(KeyboardSkin.allCases, id: \.rawValue) { option in
          Button {
            skin = option.rawValue
          } label: {
            HStack(spacing: 14) {
              SkinDesignThumbnail(skin: option)
              VStack(alignment: .leading, spacing: 5) {
                Text(option.title).font(.headline).foregroundStyle(.primary)
                Text(option.designDescription).font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              if skin == option.rawValue { Image(systemName: "checkmark") }
            }.contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("skin_\(option.rawValue)")
          .accessibilityValue(skin == option.rawValue ? "已选择" : "未选择")
        }
      } header: {
        Text("精选皮肤 · \(KeyboardSkin.allCases.count) 款")
      } footer: {
        Text("选择后预览立即更新，下次打开水杉键盘时应用。霓虹夜航与工程蓝图保留深色设计，其余随系统外观切换。")
      }

    }
    .navigationTitle("皮肤")
    .navigationBarTitleDisplayMode(.inline)
  }
}

struct DictionarySettingsView: View {
  @AppStorage(DictionaryLearningPreference.key, store: KeyboardFeedbackPreference.defaults)
  private var learningEnabled = false
  private var manifest: [String: Any] {
    guard let url = Bundle.main.url(forResource: "dictionary-manifest", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return object
  }
  var body: some View {
    Form {
      Section {
        Toggle("学习常用词", isOn: $learningEnabled)
          .accessibilityIdentifier("dictionaryLearningToggle")
      } header: {
        Text("输入习惯")
      } footer: {
        Text("开启后，引擎根据你选择的词调整候选排序，并学习支持的拼音组词。学习记录仅保存在设备上。关闭后停止新增学习，不清除已有记录；正在输入的内容结束后生效。")
      }
      Section("已安装词库") {
        Label("内置离线多方案词库", systemImage: "checkmark.circle.fill")
        Text("支持全拼 26 键、全拼 9 键、小鹤／自然码／微软／Shoudao 双拼、86 五笔和日语罗马字；提供英文补全、快捷短语、表情及颜文字。")
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
        Text("词库保存在设备上，日常输入不需要联网。已启用日语整句转换，支持罗马字输入、假名及汉字混合候选。")
      }
      Section("候选词管理") {
        Label("长按候选词", systemImage: "hand.tap")
        Text("全拼 26 键、双拼和五笔支持长按候选词：优先显示、固定到首位、取消固定或删除词条。删除需要再次确认，单个汉字由引擎保护。")
          .foregroundStyle(.secondary)
        Text("九键、日语和本地工具暂不支持候选词管理。第三方词库导入和个人词条新增仍待接入。")
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
  @State private var voiceProviderDrafts: [VoiceProviderPreset: CustomServiceConfiguration] = [:]
  @State private var showsProviders = false
  @State private var editsCustomModel = false
  @State private var fetchedModels: [String]?
  @State private var modelStatus = ""
  @State private var fetchingModels = false
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
      providerSection
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
    .tint(Color(uiColor: MetasequoiaTheme.forestUIColor))
    .sheet(isPresented: $showsProviders) {
      ProviderPickerView(options: providerOptions, selected: selectedProviderID) { id in
        if kind == .ai, let provider = AIProviderPreset(rawValue: id) { selectProvider(provider) }
        if kind == .voice, let provider = VoiceProviderPreset(rawValue: id) { selectVoiceProvider(provider) }
      }
    }
    .onChange(of: configuration.endpoint) { _ in fetchedModels = nil; modelStatus = "" }
    .onDisappear { cancelAndClear() }
    .onChange(of: scenePhase) { phase in
      if phase == .background { cancelAndClear() }
    }
  }

  private var selectedProviderID: String {
    kind == .ai ? configuration.provider.rawValue : configuration.voiceProvider.rawValue
  }

  private var providerOptions: [ProviderOption] {
    if kind == .ai {
      return AIProviderPreset.allCases.map { ProviderOption(id: $0.rawValue, title: $0.title, endpoint: $0.endpoint) }
    }
    return VoiceProviderPreset.allCases.map { ProviderOption(id: $0.rawValue, title: $0.title, endpoint: $0.endpoint) }
  }

  private var providerSection: some View {
    Section {
      Button { showsProviders = true } label: {
        HStack(spacing: 14) {
          ProviderIcon(id: selectedProviderID, size: 48)
          VStack(alignment: .leading, spacing: 4) {
            Text(kind == .ai ? configuration.provider.title : configuration.voiceProvider.title)
              .font(.headline).foregroundStyle(.primary)
            Text("切换服务商").font(.subheadline).foregroundStyle(.secondary)
          }
          Spacer()
          Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }.contentShape(Rectangle()).padding(.vertical, 6)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier(kind == .ai ? "aiProviderPicker" : "voiceProviderPicker")
      if let documentation = kind == .ai ? configuration.provider.documentation : configuration.voiceProvider.documentation {
        Link(destination: documentation) {
          Label("接入说明与 API Key", systemImage: "arrow.up.right.square")
            .font(.subheadline)
        }
      }
    } footer: {
      Text("选择服务商后自动填入接口和模型，填写对应 API Key 即可使用。")
    }
    .disabled(busy || recorder.isRecording || recorder.isPreparing)
  }

  private var presetModels: [String] {
    fetchedModels ?? (kind == .ai ? configuration.provider.models : configuration.voiceProvider.models)
  }

  private var usesCustomModel: Bool {
    editsCustomModel || !presetModels.contains(configuration.model)
  }

  private var modelSelection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("模型").font(.caption).foregroundStyle(.secondary)
      if !presetModels.isEmpty {
        Menu {
          ForEach(presetModels, id: \.self) { model in
            Button {
              configuration.model = model
              editsCustomModel = false
            } label: {
              if configuration.model == model && !usesCustomModel {
                Label(model, systemImage: "checkmark")
              } else { Text(model) }
            }
          }
          Divider()
          Button("自定义模型…") { editsCustomModel = true }
        } label: {
          HStack {
            Text(usesCustomModel ? "自定义模型" : configuration.model)
              .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            Image(systemName: "chevron.down").font(.caption.weight(.semibold))
          }.contentShape(Rectangle())
        }
        .accessibilityIdentifier("serviceModelPicker")
        .accessibilityLabel("模型")
        .accessibilityValue(configuration.model)
      }
      if presetModels.isEmpty || usesCustomModel {
        TextField("输入模型名称", text: $configuration.model)
          .textInputAutocapitalization(.never).autocorrectionDisabled()
          .accessibilityIdentifier("serviceModel")
      }
    }.padding(.vertical, 4)
  }

  private var configurationSection: some View {
      Section {
        VStack(alignment: .leading, spacing: 8) {
          Text("接口地址").font(.caption).foregroundStyle(.secondary)
          TextField(kind.example, text: $configuration.endpoint)
          .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
          .accessibilityLabel("API 接口地址").accessibilityIdentifier("serviceEndpoint")
          .disabled(kind == .ai ? configuration.provider != .custom : configuration.voiceProvider != .custom)
        }.padding(.vertical, 4)
        VStack(alignment: .leading, spacing: 8) {
          Label("API Key", systemImage: "key.horizontal").font(.caption).foregroundStyle(.secondary)
          SecureField("留空保留已保存密钥", text: Binding(get: { token }, set: { value in
            token = value; fetchedModels = nil; modelStatus = ""
          }))
          .textInputAutocapitalization(.never).autocorrectionDisabled()
          .accessibilityIdentifier("serviceToken")
        }.padding(.vertical, 4)
        Button { fetchModels() } label: {
          HStack {
            Label(fetchingModels ? "正在获取模型…" : "获取模型列表", systemImage: "arrow.clockwise")
            Spacer()
            if fetchingModels { ProgressView() }
          }
        }.accessibilityIdentifier("fetchServiceModels")
        if !modelStatus.isEmpty {
          Text(modelStatus).font(.footnote).foregroundStyle(.secondary)
            .accessibilityIdentifier("serviceModelsStatus")
        }
        modelSelection
        if kind == .ai {
          TextField("润色要求", text: $configuration.prompt)
            .accessibilityIdentifier("servicePrompt")
        }
        Button { save() } label: {
          Label("保存配置", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
        }
          .buttonStyle(.borderedProminent)
          .tint(Color(uiColor: MetasequoiaTheme.forestUIColor))
          .accessibilityIdentifier("saveServiceConfiguration")
        Button("删除此服务的密钥", role: .destructive) {
          do {
            let url = try configuration.validatedURL()
            try ServiceTokenStore.write("", kind: kind, url: url)
            token = ""
            fetchedModels = nil
            modelStatus = ""
            status = "已删除此服务的密钥"
          } catch { status = error.localizedDescription }
        }
      } header: {
        Text("连接配置")
      } footer: {
        Text("填写完整接口地址。密钥保存在本机钥匙串，按服务地址分别保存。")
      }
      .disabled(busy || recorder.isRecording)

  }

  private func selectProvider(_ provider: AIProviderPreset) {
    guard provider != configuration.provider else { return }
    fetchedModels = nil
    modelStatus = ""
    editsCustomModel = false
    providerDrafts[configuration.provider] = configuration
    configuration = providerDrafts[provider] ?? CustomServiceConfiguration.loadPreset(provider)
    // Unsaved key text must never follow an endpoint change. Saved keys are origin-scoped.
    token = ""
    status = ""
    output = ""
  }

  private func selectVoiceProvider(_ provider: VoiceProviderPreset) {
    guard provider != configuration.voiceProvider else { return }
    fetchedModels = nil
    modelStatus = ""
    editsCustomModel = false
    voiceProviderDrafts[configuration.voiceProvider] = configuration
    configuration = voiceProviderDrafts[provider] ?? CustomServiceConfiguration.loadVoicePreset(provider)
    token = ""
    status = ""
    output = ""
  }

  private func fetchModels() {
    let config = configuration
    do {
      let url = try config.validatedURL(requiresModel: false)
      let enteredKey = token.trimmingCharacters(in: .whitespacesAndNewlines)
      let key = try enteredKey.isEmpty ? ServiceTokenStore.read(kind, url: url) : enteredKey
      guard !key.isEmpty else { modelStatus = "请先填写 API Key，或使用已保存的密钥。"; return }
      UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
      busy = true
      fetchingModels = true
      modelStatus = ""
      requestID = UUID()
      let id = requestID
      operation = Task {
        do {
          let models = try await ModelCatalogClient.fetch(configuration: config, kind: kind, token: key)
          try Task.checkCancellation()
          guard requestID == id else { return }
          fetchedModels = models
          if !models.contains(configuration.model) { configuration.model = models[0] }
          editsCustomModel = false
          modelStatus = "已获取 \(models.count) 个模型。请选择支持当前功能的模型。"
        } catch {
          if requestID == id && !Task.isCancelled { modelStatus = error.localizedDescription }
        }
        if requestID == id { busy = false; fetchingModels = false }
      }
    } catch { modelStatus = error.localizedDescription }
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
    fetchingModels = false
    busy = false
  }
  private func cancelAndClear() {
    cancelRequest()
    recorder.discard()
  }
}
