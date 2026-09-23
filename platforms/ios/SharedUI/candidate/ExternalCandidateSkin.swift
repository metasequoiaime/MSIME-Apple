import Foundation

@_silgen_name("msime_client_skin_catalog")
private func msimeSkinCatalog(_ directory: UnsafePointer<UInt8>?, _ length: UInt) -> UnsafeMutablePointer<CChar>?

@_silgen_name("msime_client_string_free")
private func msimeSkinCatalogStringFree(_ value: UnsafeMutablePointer<CChar>?)

/// A skin the user imported into `<App Group>/MSIME/skins`, read through the same Rust catalog scan the settings page lists, so a package the page reports as an issue is never drawn here either.
///
/// Only what the strip draws is kept: the built-in skin the package extends and, per declared theme, its candidate colours. Like the Windows candidate window, a package is adopted only for a layout and theme it declares; the strip is horizontal.
struct ExternalCandidateSkin: Equatable {
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
      return (id, ExternalCandidateSkin(base: base, candidate: candidate, themes: themes,
                                        horizontal: layouts.contains("horizontal")))
    }
  }
}
