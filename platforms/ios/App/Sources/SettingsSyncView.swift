import SwiftUI

private enum IOSCloudSettings {
  static func snapshot() throws -> [String: BackendPreferenceValue] {
    let scheme = InputSchemePreference.scheme
    let name = scheme.shuangpinProfile != nil ? "shuangpin" : ((scheme == .nineKey || scheme == .thoughtfulReply) ? "quanpin" : scheme.rawValue)
    let skinData = try JSONEncoder().encode(CustomKeyboardSkinStore.current)
    var settings: [String: BackendPreferenceValue] = [
      "input.schema": .string(name),
      "input.character_set": .string(ChineseOutputPreference.usesTraditional ? "traditional" : "simplified"),
      "platform.ios.nine_key": .boolean(scheme == .nineKey),
      "platform.ios.sound_enabled": .boolean(KeyboardFeedbackPreference.soundEnabled),
      "platform.ios.haptics_enabled": .boolean(KeyboardFeedbackPreference.hapticsEnabled),
      "platform.ios.haptic_strength": .string(KeyboardFeedbackPreference.hapticStrength.rawValue),
      "platform.ios.dictionary_learning": .boolean(DictionaryLearningPreference.enabled),
      "platform.ios.keyboard_skin": .string(KeyboardSkinPreference.selected.rawValue),
      "platform.ios.custom_keyboard_skin": .string(String(decoding: skinData, as: UTF8.self))
    ]
    if let profile = scheme.shuangpinProfile { settings["input.shuangpin_schema"] = .string(profile) }
    return settings
  }
  static func apply(_ values: [String: BackendPreferenceValue]) throws {
    let plan = try IOSPreferencePlan(values)
    let custom = try plan.customSkinJSON.map { try JSONDecoder().decode(CustomKeyboardSkin.self, from: Data($0.utf8)).normalized }
    // Validate everything before writing. Unknown platforms' values stay in the
    // cloud and are never assigned to local defaults.
    if let scheme = plan.scheme.flatMap(ChineseInputScheme.init(rawValue:)) { InputSchemePreference.scheme = scheme }
    if let traditional = plan.traditional { ChineseOutputPreference.usesTraditional = traditional }
    let defaults = KeyboardFeedbackPreference.defaults
    if let sound = plan.sound { defaults.set(sound, forKey: KeyboardFeedbackPreference.soundKey) }
    if let haptics = plan.haptics { defaults.set(haptics, forKey: KeyboardFeedbackPreference.hapticsKey) }
    if let strength = plan.strength { defaults.set(strength, forKey: KeyboardFeedbackPreference.strengthKey) }
    if let learning = plan.learning { defaults.set(learning, forKey: DictionaryLearningPreference.key) }
    if let custom { CustomKeyboardSkinStore.save(custom) }
    if let skin = plan.skin { defaults.set(skin, forKey: KeyboardSkinPreference.key) }
  }
}

struct SettingsSyncView: View {
  let session: BackendAccountSession
  let client: BackendAccountClient
  @State private var loadedUserID: String?
  @State private var cloud: BackendAccountClient.Preferences?
  @State private var schema: BackendAccountClient.PreferenceSchema?
  @State private var busy = false
  @State private var message: String?
  @State private var applying = false
  @State private var uploading = false
  @State private var pending: Task<Void, Never>?

  var body: some View {
    Form {
      Section {
        Text("同步输入方案、简繁体、键盘声音与触感、词库学习开关和皮肤。凭据、联网授权及输入内容不会随设置上传。")
        if let cloud { Text("云端版本：\(cloud.revision)") }
        Button("刷新云端设置") { pending = Task { await load() } }
        Button("上传本机设置") { uploading = true }.disabled(cloud == nil || schema == nil)
        Button("下载并应用云端设置") { applying = true }.disabled(cloud?.settings.isEmpty != false)
      }
      if busy { ProgressView("正在处理…") }
      if let message { Text(message).foregroundStyle(.secondary) }
    }
    .disabled(busy)
    .navigationTitle("设置同步")
    .task { await load() }
    .onDisappear { pending?.cancel(); cloud = nil }
    .alert("上传本机设置？", isPresented: $uploading) {
      Button("取消", role: .cancel) { }
      Button("上传") { pending = Task { await upload() } }
    } message: { Text("更新云端对应设置，包括自定义皮肤的背景图片；保留其他平台专属设置。版本冲突时需刷新后重新确认。") }
    .alert("应用云端设置？", isPresented: $applying) {
      Button("取消", role: .cancel) { }
      Button("应用") {
        pending = Task { await apply() }
      }
    } message: { Text("将替换本机对应设置，包括词库学习开关；不会下载词库或开启数据上传。") }
  }
  @MainActor private func load() async {
    guard !busy else { return }
    busy = true; message = nil
    defer { busy = false }
    do {
      let identity = try await session.credentials()
      let fields = try await client.preferenceSchema(token: identity.token)
      let values = try await client.preferences(token: identity.token)
      guard try await session.user()?.id == identity.userID else { throw CancellationError() }
      try Task.checkCancellation()
      schema = fields; cloud = values; loadedUserID = identity.userID
    } catch is CancellationError { }
    catch { message = "无法读取云端设置，请稍后重试。" }
  }
  @MainActor private func apply() async {
    do {
      guard let cloud, let loadedUserID, try await session.user()?.id == loadedUserID else { throw BackendAccountClient.Failure(status: 401) }
      try Task.checkCancellation()
      try IOSCloudSettings.apply(cloud.settings)
      message = "已应用云端设置。"
    } catch is CancellationError { }
    catch { message = "账号已变化或云端设置不兼容，本机设置未更改，请重新读取。" }
  }
  @MainActor private func upload() async {
    guard !busy, let cloud, let schema else { return }
    busy = true; message = nil
    defer { busy = false }
    do {
      let values = try BackendAccountClient.mergedPreferences(cloud, replacing: IOSCloudSettings.snapshot(), schema: schema)
      let identity = try await session.credentials()
      guard identity.userID == loadedUserID else { throw BackendAccountClient.Failure(status: 401) }
      try Task.checkCancellation()
      self.cloud = try await client.putPreferences(values, token: identity.token)
      message = "本机设置已上传。"
    } catch is CancellationError { }
    catch let error as BackendAccountClient.Failure {
      message = error.status == 409 ? "云端设置已被其他设备更新，请刷新后重新确认。" : error.localizedDescription
    } catch { message = "上传未完成，请稍后重试。" }
  }
}
