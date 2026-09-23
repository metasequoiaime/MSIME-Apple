import Foundation

@_silgen_name("msime_client_skin_catalog")
private func msimeSkinCatalog(_ directory: UnsafePointer<UInt8>?, _ length: UInt) -> UnsafeMutablePointer<CChar>?

@_silgen_name("msime_client_skin_import")
private func msimeSkinImport(_ request: UnsafePointer<UInt8>?, _ length: UInt) -> UnsafeMutablePointer<CChar>?

@_silgen_name("msime_client_string_free")
private func msimeSkinCatalogStringFree(_ value: UnsafeMutablePointer<CChar>?)

/// A skin the user imported into `<App Group>/MSIME/skins`, read through the same Rust catalog scan the settings page lists, so a package the page reports as an issue is never drawn here either.
///
/// Only what the strip draws is kept: the built-in skin the package extends and, per declared theme, its candidate colours. Like the Windows candidate window, a package is adopted only for a layout and theme it declares; the strip is horizontal.
struct ExternalCandidateSkin: Equatable {
  var name = ""
  let base: String
  /// `light` / `dark` → colour key → value, exactly as the manifest spells them.
  let candidate: [String: [String: String]]
  let themes: Set<String>
  let horizontal: Bool

  /// The directory the settings app imports skins into; the keyboard extension shares it through the App Group.
  static var defaultRoot: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: InputSchemePreference.appGroupIdentifier)?
      .appendingPathComponent("MSIME", isDirectory: true)
      .appendingPathComponent("skins", isDirectory: true)
  }

  private static let lock = NSLock()
  /// Only the selected skin is ever asked for, so one entry is enough.
  private static var cache: [String: ExternalCandidateSkin?] = [:]

  /// The package named `id` under `root` if it supports the horizontal strip in the requested theme, else nil. A scan runs only when the manifest changed since the last one, so a redraw costs one `stat`.
  static func load(_ id: String, dark: Bool, root: URL?) -> ExternalCandidateSkin? {
    guard let root, !id.isEmpty, id.count <= 64 else { return nil }
    let manifest = root.appendingPathComponent(id, isDirectory: true).appendingPathComponent("skin.toml")
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: manifest.path),
          let modified = attributes[.modificationDate] as? Date else { return nil }
    let key = "\(root.path)\u{0}\(id)\u{0}\(modified.timeIntervalSince1970)\u{0}\(attributes[.size] ?? 0)"
    lock.lock()
    let cached = cache[key]
    lock.unlock()
    let package: ExternalCandidateSkin?
    if let cached {
      package = cached
    } else {
      package = scan(root)?.first { $0.id == id }?.skin
      lock.lock()
      cache = [key: package]
      lock.unlock()
    }
    guard let package, package.supports(theme: dark ? "dark" : "light") else { return nil }
    return package
  }

  func supports(theme: String) -> Bool { horizontal && themes.contains(theme) }

  /// The catalog's packages, or nil when the ABI refused the root.
  static func scan(_ root: URL) -> [(id: String, skin: ExternalCandidateSkin)]? {
    let path = Array(root.path.utf8)
    guard path.count <= 16384 else { return nil }
    let raw = path.withUnsafeBufferPointer { msimeSkinCatalog($0.baseAddress, UInt($0.count)) }
    guard let raw else { return nil }
    defer { msimeSkinCatalogStringFree(raw) }
    guard let reply = try? JSONSerialization.jsonObject(with: Data(String(cString: raw).utf8)) as? [String: Any],
          reply["ok"] as? Bool == true,
          let value = reply["value"] as? [String: Any],
          let packages = value["packages"] as? [[String: Any]] else { return nil }
    return packages.compactMap { package in
      guard let id = package["id"] as? String, let base = package["base"] as? String else { return nil }
      var candidate: [String: [String: String]] = [:]
      for theme in ["light", "dark"] {
        guard let palette = (package["candidate"] as? [String: Any])?[theme] as? [String: Any] else { continue }
        candidate[theme] = palette.compactMapValues { $0 as? String }
      }
      let themes = Set(package["themes"] as? [String] ?? [])
      let layouts = package["layouts"] as? [String] ?? []
      return (id, ExternalCandidateSkin(name: package["name"] as? String ?? id, base: base, candidate: candidate,
                                        themes: themes, horizontal: layouts.contains("horizontal")))
    }
  }

  enum ImportFailure: Error, Equatable {
    /// The folder's name is not one the catalog lists: lowercase ASCII letters, digits, `.`, `_` and `-`, starting with a letter or digit, and not a built-in id.
    case name
    /// The folder has no `skin.toml`.
    case manifest
    case storage
  }

  /// Copy a folder the user picked in Files into `root`, the way the Tauri shell imports one on iOS: the same Rust import, which checks the name and manifest before copying and replaces a skin of the same name whole. Returns the id the catalog lists it under. Touches the disk; call it off the main thread.
  static func importFolder(_ source: URL, root: URL) -> Result<String, ImportFailure> {
    guard let request = try? JSONSerialization.data(withJSONObject: ["source": source.path, "directory": root.path])
    else { return .failure(.storage) }
    let raw = request.withUnsafeBytes { bytes in
      msimeSkinImport(bytes.bindMemory(to: UInt8.self).baseAddress, UInt(bytes.count))
    }
    guard let raw else { return .failure(.storage) }
    defer { msimeSkinCatalogStringFree(raw) }
    guard let reply = try? JSONSerialization.jsonObject(with: Data(String(cString: raw).utf8)) as? [String: Any]
    else { return .failure(.storage) }
    if reply["ok"] as? Bool == true, let id = (reply["value"] as? [String: Any])?["id"] as? String { return .success(id) }
    switch reply["error"] as? String {
    case "skin_name": return .failure(.name)
    case "skin_manifest": return .failure(.manifest)
    default: return .failure(.storage)
    }
  }

  /// Delete an imported skin. Only a name the catalog could list is accepted, so nothing outside `root` is reachable.
  static func remove(_ id: String, root: URL) -> Bool {
    let bytes = Array(id.utf8)
    guard let first = bytes.first, bytes.count <= 64,
          (first >= 0x61 && first <= 0x7a) || (first >= 0x30 && first <= 0x39),
          bytes.allSatisfy({ ($0 >= 0x61 && $0 <= 0x7a) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2e || $0 == 0x5f || $0 == 0x2d })
    else { return false }
    let folder = root.appendingPathComponent(id, isDirectory: true)
    return (try? FileManager.default.removeItem(at: folder)) != nil
  }
}
