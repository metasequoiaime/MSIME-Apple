import Foundation
import Security
import Tauri
import UIKit

private struct SetAppIconArgs: Decodable {
  let style: String
}

private struct SaveAccountSessionArgs: Decodable {
  let value: String
}

private struct CopyTextArgs: Decodable {
  let text: String
}

private struct SaveKeyboardPreferencesArgs: Decodable {
  let inputScheme: String
  let traditionalChineseOutput: Bool
  let soundEnabled: Bool
  let hapticsEnabled: Bool
  let hapticStrength: String
  let dictionaryLearning: Bool
  let keyboardSkin: String
  let customKeyboardSkin: String?
}

/// App Group adapter for preferences that the keyboard extension can change
/// without opening the Tauri settings app. The keys and fallback behaviour are
/// fixed to MSIME-Apple develop@81e79abec7b53e7243fb8cbe82a42a4dde1e528f.
private struct IOSKeyboardPreferenceStore {
  static let maximumCustomSkinBytes = 800_000
  static let schemeOrder = [
    "quanpin", "nineKey", "shuangpin", "ziranma", "microsoft", "shoudao", "wubi",
    "japaneseNineKey", "japanese", "handwriting", "thoughtfulReply",
  ]
  static let skinOrder = [
    "forest", "ocean", "rose", "porcelain", "typewriter", "candy", "midnight",
    "blueprint", "custom",
  ]
  static let hapticStrengths = ["light", "medium", "strong"]

  private var defaults: UserDefaults {
    UserDefaults(suiteName: "group.app.msime.ios") ?? .standard
  }

  private func migrateJapaneseSchemes() {
    guard !defaults.bool(forKey: "japaneseSchemesSplit") else { return }
    if var enabled = defaults.stringArray(forKey: "enabledInputSchemes"),
       enabled.contains("japanese"), !enabled.contains("japaneseNineKey") {
      enabled.append("japaneseNineKey")
      defaults.set(enabled, forKey: "enabledInputSchemes")
    }
    if defaults.string(forKey: "chineseInputScheme") == "japanese",
       !defaults.bool(forKey: "japaneseRomanKeys") {
      defaults.set("japaneseNineKey", forKey: "chineseInputScheme")
    }
    defaults.set(true, forKey: "japaneseSchemesSplit")
  }

  private func enabledSchemes() -> [String] {
    migrateJapaneseSchemes()
    guard let stored = defaults.stringArray(forKey: "enabledInputSchemes") else {
      return Self.schemeOrder
    }
    let enabled = Self.schemeOrder.filter(stored.contains)
    return enabled.isEmpty ? ["quanpin"] : enabled
  }

  private func selectedScheme() -> String {
    let enabled = enabledSchemes()
    let legacy = defaults.bool(forKey: "inputSchemeUsesShuangpin") ? "shuangpin" : "quanpin"
    let selected = defaults.string(forKey: "chineseInputScheme") ?? legacy
    return enabled.contains(selected) ? selected : enabled[0]
  }

  private func customSkinJSON() -> String? {
    guard let data = defaults.data(forKey: "customKeyboardSkin.v1"),
          !data.isEmpty, data.count <= Self.maximumCustomSkinBytes,
          let document = try? JSONSerialization.jsonObject(with: data),
          document is [String: Any] else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  func snapshot() -> [String: Any] {
    let strength = defaults.string(forKey: "keyboardHapticStrength") ?? "medium"
    let skin = defaults.string(forKey: "keyboardSkin") ?? "forest"
    return [
      "inputScheme": selectedScheme(),
      "traditionalChineseOutput": defaults.bool(forKey: "chineseOutputUsesTraditional"),
      "soundEnabled": defaults.object(forKey: "keyboardSoundEnabled") as? Bool ?? true,
      "hapticsEnabled": defaults.bool(forKey: "keyboardHapticsEnabled"),
      "hapticStrength": Self.hapticStrengths.contains(strength) ? strength : "medium",
      "dictionaryLearning": defaults.bool(forKey: "dictionaryLearningEnabled"),
      "keyboardSkin": Self.skinOrder.contains(skin) ? skin : "forest",
      "customKeyboardSkin": customSkinJSON() as Any? ?? NSNull(),
    ]
  }

  func save(_ args: SaveKeyboardPreferencesArgs) throws -> [String: Any] {
    guard Self.schemeOrder.contains(args.inputScheme),
          Self.hapticStrengths.contains(args.hapticStrength),
          Self.skinOrder.contains(args.keyboardSkin) else {
      throw NSError(domain: "keyboard_preferences", code: 1)
    }
    if let custom = args.customKeyboardSkin {
      let data = Data(custom.utf8)
      guard !data.isEmpty, data.count <= Self.maximumCustomSkinBytes,
            let document = try? JSONSerialization.jsonObject(with: data),
            document is [String: Any] else {
        throw NSError(domain: "keyboard_preferences", code: 2)
      }
    }

    let enabled = enabledSchemes()
    let selected = enabled.contains(args.inputScheme) ? args.inputScheme : enabled[0]
    defaults.set(selected, forKey: "chineseInputScheme")
    defaults.set(["shuangpin", "ziranma", "microsoft", "shoudao"].contains(selected),
                 forKey: "inputSchemeUsesShuangpin")
    defaults.set(args.traditionalChineseOutput, forKey: "chineseOutputUsesTraditional")
    defaults.set(args.soundEnabled, forKey: "keyboardSoundEnabled")
    defaults.set(args.hapticsEnabled, forKey: "keyboardHapticsEnabled")
    defaults.set(args.hapticStrength, forKey: "keyboardHapticStrength")
    defaults.set(args.dictionaryLearning, forKey: "dictionaryLearningEnabled")
    defaults.set(args.keyboardSkin, forKey: "keyboardSkin")
    if let custom = args.customKeyboardSkin {
      defaults.set(Data(custom.utf8), forKey: "customKeyboardSkin.v1")
    } else {
      defaults.removeObject(forKey: "customKeyboardSkin.v1")
    }
    return snapshot()
  }
}

private struct AccountSessionKeychain {
  static let maximumPayloadBytes = 16 * 1024

  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "app.msime.backend.account",
      kSecAttrAccount as String: "https://api.msime.app",
    ]
  }

  private var legacyQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "app.msime.ios.community",
      kSecAttrAccount as String: "api.msime.app",
    ]
  }

  private func loadData(_ baseQuery: [String: Any]) throws -> Data? {
    var lookup = baseQuery
    lookup[kSecReturnData as String] = true
    lookup[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(lookup as CFDictionary, &result)
    if status == errSecItemNotFound {
      return nil
    }
    guard status == errSecSuccess, let data = result as? Data else {
      throw NSError(domain: "secure_storage", code: Int(status))
    }
    return data
  }

  private func decode(_ data: Data) throws -> String {
    guard !data.isEmpty, data.count <= Self.maximumPayloadBytes,
          let value = String(data: data, encoding: .utf8) else {
      throw NSError(domain: "secure_storage", code: Int(errSecDecode))
    }
    return value
  }

  func load() throws -> String? {
    if let data = try loadData(query) {
      return try decode(data)
    }
    guard let data = try loadData(legacyQuery) else {
      return nil
    }
    return try decode(data)
  }

  func save(_ value: String) throws {
    let data = Data(value.utf8)
    guard !data.isEmpty, data.count <= Self.maximumPayloadBytes else {
      throw NSError(domain: "secure_storage", code: Int(errSecParam))
    }
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
    }
    guard status == errSecSuccess else {
      throw NSError(domain: "secure_storage", code: Int(status))
    }
    try clearLegacy()
  }

  private func clearLegacy() throws {
    let status = SecItemDelete(legacyQuery as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw NSError(domain: "secure_storage", code: Int(status))
    }
  }

  func clear() throws {
    try clearLegacy()
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw NSError(domain: "secure_storage", code: Int(status))
    }
  }
}

final class MobilePlatformPlugin: Plugin {
  private let accountSession = AccountSessionKeychain()
  private let keyboardPreferences = IOSKeyboardPreferenceStore()

  private func onMain(_ action: @escaping () -> Void) {
    if Thread.isMainThread {
      action()
    } else {
      DispatchQueue.main.async(execute: action)
    }
  }

  private func iconName(for style: String) -> String?? {
    switch style {
    case "classic": return .some(nil)
    case "forest": return .some("AppIconForest")
    case "sky": return .some("AppIconSky")
    case "dusk": return .some("AppIconDusk")
    case "vermilion": return .some("AppIconVermilion")
    default: return nil
    }
  }

  private func selectedStyle(for iconName: String?) -> String {
    switch iconName {
    case "AppIconForest": return "forest"
    case "AppIconSky": return "sky"
    case "AppIconDusk": return "dusk"
    case "AppIconVermilion": return "vermilion"
    default: return "classic"
    }
  }

  private func resolveInfo(_ invoke: Invoke, application: UIApplication) {
    invoke.resolve([
      "supported": application.supportsAlternateIcons,
      "selected": selectedStyle(for: application.alternateIconName),
    ])
  }

  @objc public func openSystemKeyboardSettings(_ invoke: Invoke) {
    onMain { [self] in
      guard let url = URL(string: UIApplication.openSettingsURLString) else {
        invoke.reject("system_settings", code: "system_settings")
        return
      }
      UIApplication.shared.open(url, options: [:]) { opened in
        self.onMain {
          if opened {
            invoke.resolve()
          } else {
            invoke.reject("system_settings", code: "system_settings")
          }
        }
      }
    }
  }

  @objc public func appIconInfo(_ invoke: Invoke) {
    onMain { [self] in
      resolveInfo(invoke, application: UIApplication.shared)
    }
  }

  @objc public func setAppIcon(_ invoke: Invoke) {
    let args: SetAppIconArgs
    do {
      args = try invoke.parseArgs(SetAppIconArgs.self)
    } catch {
      invoke.reject("invalid_app_icon", code: "invalid_app_icon")
      return
    }
    guard let requestedName = iconName(for: args.style) else {
      invoke.reject("invalid_app_icon", code: "invalid_app_icon")
      return
    }

    onMain { [self] in
      let application = UIApplication.shared
      guard application.supportsAlternateIcons else {
        resolveInfo(invoke, application: application)
        return
      }
      application.setAlternateIconName(requestedName) { error in
        self.onMain {
          // Simulator runtimes may report an I/O failure after applying the icon.
          // Trust the state the OS exposes after completion before rejecting.
          if error != nil && application.alternateIconName != requestedName {
            invoke.reject("app_icon", code: "app_icon")
          } else {
            self.resolveInfo(invoke, application: application)
          }
        }
      }
    }
  }

  @objc public func loadSession(_ invoke: Invoke) {
    do {
      let value = try accountSession.load()
      invoke.resolve(["value": value as Any? ?? NSNull()])
    } catch {
      invoke.reject("secure_storage", code: "secure_storage")
    }
  }

  @objc public func saveSession(_ invoke: Invoke) {
    do {
      let args = try invoke.parseArgs(SaveAccountSessionArgs.self)
      try accountSession.save(args.value)
      invoke.resolve()
    } catch {
      invoke.reject("secure_storage", code: "secure_storage")
    }
  }

  @objc public func clearSession(_ invoke: Invoke) {
    do {
      try accountSession.clear()
      invoke.resolve()
    } catch {
      invoke.reject("secure_storage", code: "secure_storage")
    }
  }

  @objc public func copyText(_ invoke: Invoke) {
    let args: CopyTextArgs
    do {
      args = try invoke.parseArgs(CopyTextArgs.self)
    } catch {
      invoke.reject("invalid_clipboard_text", code: "invalid_clipboard_text")
      return
    }
    guard !args.text.isEmpty, args.text.utf16.count <= 4_000,
          !args.text.unicodeScalars.contains(where: { $0.value == 0 }) else {
      invoke.reject("invalid_clipboard_text", code: "invalid_clipboard_text")
      return
    }
    onMain {
      UIPasteboard.general.string = args.text
      invoke.resolve()
    }
  }

  @objc public func loadKeyboardPreferences(_ invoke: Invoke) {
    invoke.resolve(keyboardPreferences.snapshot())
  }

  @objc public func saveKeyboardPreferences(_ invoke: Invoke) {
    do {
      let args = try invoke.parseArgs(SaveKeyboardPreferencesArgs.self)
      invoke.resolve(try keyboardPreferences.save(args))
    } catch {
      invoke.reject("keyboard_preferences", code: "keyboard_preferences")
    }
  }
}

@_cdecl("init_plugin_msime_mobile_platform")
func initPlugin() -> Plugin {
  MobilePlatformPlugin()
}
