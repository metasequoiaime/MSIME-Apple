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
}

@_cdecl("init_plugin_msime_mobile_platform")
func initPlugin() -> Plugin {
  MobilePlatformPlugin()
}
