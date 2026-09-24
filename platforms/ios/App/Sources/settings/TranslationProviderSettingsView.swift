import SwiftUI

/// 「翻译服务」: which service fills candidate glosses that the offline dictionary cannot. Saved into the shared preference document, which the keyboard reloads the next time it appears.
struct TranslationProviderSettingsView: View {
  @State private var provider = TranslationProvider.off
  @State private var niutransAppID = ""
  @State private var niutransKey = ""
  @State private var tencentID = ""
  @State private var tencentKey = ""
  @State private var tencentRegion = TranslationProviderPreference.defaultTencentRegion
  @State private var customEndpoint = ""
  @State private var customKey = ""
  @State private var status: String?
  @State private var testing = false

  var body: some View {
    Form {
      Section {
        Picker("翻译服务", selection: $provider) {
          ForEach(TranslationProvider.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .accessibilityIdentifier("translationProviderPicker")
      } footer: {
        Text("选择自己的翻译服务后，键盘把这一页的中文候选直接发给该服务，不经过水杉账号；凭据只保存在本设备的共享设置里。所选服务的凭据不完整时，键盘不会联网翻译，也不会改用其他服务。")
      }
      switch provider {
      case .off:
        Section {
          Text("键盘不会把候选词发给任何在线服务；英文释义仍来自离线词库。").foregroundStyle(.secondary)
        }
      case .account:
        Section {
          Text("候选词会发送到水杉服务器（api.msime.app）翻译，首次使用会自动创建匿名账号。").foregroundStyle(.secondary)
        }
      case .niutrans:
        Section("小牛翻译") {
          TextField("APPID", text: $niutransAppID).credentialField()
          SecureField("API Key", text: $niutransKey).credentialField()
        }
      case .tencent:
        Section {
          TextField("SecretId", text: $tencentID).credentialField()
          SecureField("SecretKey", text: $tencentKey).credentialField()
          TextField("地域", text: $tencentRegion).credentialField()
        } header: {
          Text("腾讯云机器翻译")
        } footer: {
          Text("地域留空时使用 \(TranslationProviderPreference.defaultTencentRegion)。建议为输入法单独创建只授权机器翻译的子账号密钥。")
        }
      case .custom:
        Section {
          TextField("https://example.com/translate", text: $customEndpoint).credentialField()
            .keyboardType(.URL)
          SecureField("API Key（可选）", text: $customKey).credentialField()
        } header: {
          Text("自定义接口")
        } footer: {
          Text("兼容 DeepLX 的 POST 接口。iOS 只允许 HTTPS 地址，HTTP 地址保存后不会被调用。")
        }
      }
      Section {
        Button("保存") { save() }
          .accessibilityIdentifier("translationProviderSave")
        if provider != .account && provider != .off {
          Button(testing ? "正在测试…" : "测试翻译「你好」") { test() }
            .disabled(testing)
            .accessibilityIdentifier("translationProviderTest")
        }
        if let status {
          Text(status).font(.footnote).foregroundStyle(.secondary)
        }
      }
      Section {
        NavigationLink("自定义候选释义") { CustomTranslationsView() }
          .accessibilityIdentifier("customTranslations")
      } footer: {
        Text("内置词库译得不准或没有收录时，自己加一层释义，优先于内置词库和在线翻译。")
      }
    }
    .navigationTitle("翻译服务")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: load)
  }

  private func load() {
    let preferences = MetasequoiaInputSessionBridge.loadSharedPreferences()
    provider = TranslationProviderPreference.selected(in: preferences)
    let niutrans = preferences?[TranslationProviderPreference.niutransKey] as? [String: Any] ?? [:]
    let tencent = preferences?[TranslationProviderPreference.tencentKey] as? [String: Any] ?? [:]
    let custom = preferences?[TranslationProviderPreference.customKey] as? [String: Any] ?? [:]
    niutransAppID = niutrans["app_id"] as? String ?? ""
    niutransKey = niutrans["apikey"] as? String ?? ""
    tencentID = tencent["secret_id"] as? String ?? ""
    tencentKey = tencent["secret_key"] as? String ?? ""
    let region = tencent["region"] as? String ?? ""
    tencentRegion = region.isEmpty ? TranslationProviderPreference.defaultTencentRegion : region
    customEndpoint = custom["endpoint"] as? String ?? ""
    customKey = custom["api_key"] as? String ?? ""
  }

  private func write(into document: inout [String: Any]) {
    TranslationProviderPreference.select(provider, niutrans: (niutransAppID, niutransKey),
                                         tencent: (tencentID, tencentKey, tencentRegion),
                                         custom: (customEndpoint, customKey), in: &document)
  }

  private func save() {
    let saved = MetasequoiaInputSessionBridge.updateSharedPreferences { write(into: &$0) }
    guard saved else { status = "保存失败，请稍后再试。"; return }
    var document: [String: Any] = [:]
    write(into: &document)
    if provider == .off {
      status = "已保存，键盘不再联网翻译。"
    } else {
      status = TranslationProviderPreference.route(in: document) == .none
        ? "已保存，但凭据不完整，键盘暂不联网翻译。" : "已保存，键盘下次弹出时生效。"
    }
  }

  private func test() {
    var document: [String: Any] = [:]
    write(into: &document)
    let route = TranslationProviderPreference.route(in: document)
    guard route != .none, route != .account else { status = "凭据不完整。"; return }
    testing = true
    status = nil
    Task {
      let result = await TranslationProviderClient().translate(words: ["你好"], target: "EN", route: route)
      testing = false
      if let gloss = result.first ?? nil {
        status = "测试成功：你好 → \(gloss)"
      } else {
        status = "测试失败：请检查凭据、地址与网络。"
      }
    }
  }
}

private extension View {
  func credentialField() -> some View {
    textInputAutocapitalization(.never).autocorrectionDisabled()
  }
}
