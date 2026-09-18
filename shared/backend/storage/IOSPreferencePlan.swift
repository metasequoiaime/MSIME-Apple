import Foundation

/// Validated values only; the platform applies this plan through its existing setters.
struct IOSPreferencePlan {
  let scheme: String?
  let traditional: Bool?
  let sound: Bool?
  let haptics: Bool?
  let learning: Bool?
  let strength: String?
  let skin: String?
  let customSkinJSON: String?

  init(_ values: [String: BackendPreferenceValue]) throws {
    func string(_ key: String) throws -> String? {
      guard let value = values[key] else { return nil }
      guard case .string(let text) = value else { throw BackendAccountClient.Failure(status: 400) }
      return text
    }
    func bool(_ key: String) throws -> Bool? {
      guard let value = values[key] else { return nil }
      guard case .boolean(let value) = value else { throw BackendAccountClient.Failure(status: 400) }
      return value
    }
    let nineKey = try bool("platform.ios.nine_key")
    if let value = try string("input.schema") {
      switch value {
      case "quanpin": scheme = nineKey == true ? "nineKey" : "quanpin"
      case "shuangpin":
        let profile = try string("input.shuangpin_schema") ?? "xiaohe"
        guard ["xiaohe", "ziranma", "microsoft", "shoudao"].contains(profile) else { throw BackendAccountClient.Failure(status: 400) }
        scheme = profile == "xiaohe" ? "shuangpin" : profile
      case "wubi":
        guard try string("input.wubi_schema") ?? "wubi86" == "wubi86" else { throw BackendAccountClient.Failure(status: 400) }
        scheme = "wubi"
      case "japanese":
        guard try string("input.japanese_schema") ?? "romaji" == "romaji" else { throw BackendAccountClient.Failure(status: 400) }
        scheme = nineKey == true ? "japaneseNineKey" : "japanese"
      default: throw BackendAccountClient.Failure(status: 400)
      }
    } else { scheme = nil }
    if let charset = try string("input.character_set") {
      guard ["simplified", "traditional"].contains(charset) else { throw BackendAccountClient.Failure(status: 400) }
      traditional = charset == "traditional"
    } else { traditional = nil }
    sound = try bool("platform.ios.sound_enabled")
    haptics = try bool("platform.ios.haptics_enabled")
    learning = try bool("platform.ios.dictionary_learning")
    strength = try string("platform.ios.haptic_strength")
    guard strength == nil || ["light", "medium", "strong"].contains(strength!) else { throw BackendAccountClient.Failure(status: 400) }
    skin = try string("platform.ios.keyboard_skin")
    guard skin == nil || ["forest", "ocean", "rose", "porcelain", "typewriter", "candy", "midnight", "blueprint", "custom"].contains(skin!) else { throw BackendAccountClient.Failure(status: 400) }
    customSkinJSON = try string("platform.ios.custom_keyboard_skin")
  }
}
