import Foundation

// AI output is data only. Never accept image URLs, photos, code or unknown fields.
enum GeneratedKeyboardSkin {
  enum Failure: LocalizedError {
    case invalid, contrast
    var errorDescription: String? {
      switch self {
      case .invalid: "AI 返回的设计格式不完整，请重新生成。"
      case .contrast: "这款设计的文字对比度不足，请重新生成。"
      }
    }
  }
  static func parse(_ response: String) throws -> SavedKeyboardSkin {
    guard response.utf8.count <= 16_384 else { throw Failure.invalid }
    var text = response.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("```json\n"), text.hasSuffix("```") { text = String(text.dropFirst(8).dropLast(3)) }
    else if text.hasPrefix("```\n"), text.hasSuffix("```") { text = String(text.dropFirst(4).dropLast(3)) }
    struct Payload: Decodable { let name: String; let design: Design }
    struct Design: Decodable {
      let background, keyBackground, keyForeground, accent, actionBackground: String
      let gradientEnd, customBorderColor: String?
      let cornerRadius, borderWidth, shadow: Double
      let pattern: Int
      let patternOpacity: Double?
      let monospaced, gradientHorizontal: Bool?
    }
    let data = Data(text.utf8)
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          Set(object.keys) == ["name", "design"], let fields = object["design"] as? [String: Any],
          Set(fields.keys).isSubset(of: ["background", "keyBackground", "keyForeground", "accent", "actionBackground", "gradientEnd", "customBorderColor", "cornerRadius", "borderWidth", "shadow", "pattern", "patternOpacity", "monospaced", "gradientHorizontal"]),
          let payload = try? JSONDecoder().decode(Payload.self, from: data) else { throw Failure.invalid }
    let name = payload.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name.count <= 32, !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw Failure.invalid }
    func rgb(_ value: String) throws -> UInt32 {
      guard value.count == 7, value.first == "#", let n = UInt32(value.dropFirst(), radix: 16) else { throw Failure.invalid }
      return n
    }
    let value = payload.design
    var design = CustomKeyboardSkin()
    design.background = try rgb(value.background); design.keyBackground = try rgb(value.keyBackground)
    design.keyForeground = try rgb(value.keyForeground); design.accent = try rgb(value.accent)
    design.actionBackground = try rgb(value.actionBackground)
    design.gradientEnd = try value.gradientEnd.map(rgb); design.customBorderColor = try value.customBorderColor.map(rgb)
    design.cornerRadius = value.cornerRadius; design.borderWidth = value.borderWidth
    design.shadow = value.shadow; design.pattern = value.pattern
    design.patternOpacity = value.patternOpacity; design.monospaced = value.monospaced ?? false
    design.gradientHorizontal = value.gradientHorizontal
    guard design == design.normalized else { throw Failure.invalid }
    guard design.hasReadableText else { throw Failure.contrast }
    return SavedKeyboardSkin(name: name, design: design)
  }

  static let instruction = """
  你是水杉输入法的键盘设计师。根据用户的风格描述生成原创、精致、可读的键盘皮肤。
  只返回一个 JSON 对象：{"name":"32字以内的中文设计名","design":{"background":"#E8F0EB","keyBackground":"#FFFFFF","keyForeground":"#17251D","accent":"#185C47","actionBackground":"#185C47","gradientEnd":"#DDEADD","customBorderColor":"#AAC6B7","cornerRadius":8,"borderWidth":0.5,"shadow":0.1,"pattern":0,"patternOpacity":0.05,"monospaced":false,"gradientHorizontal":false}}。
  颜色必须是 #RRGGBB。圆角0到20、边框0到2、阴影0到0.4、纹理强度0到0.15。
  pattern仅可为0无纹理、1细点、2网格、3波纹。用键帽、描边、阴影和细纹体现设计感，保持干净。
  keyForeground与keyBackground对比度至少4.5；accent与background、gradientEnd、keyBackground的对比度都至少4.5。浅色皮肤用深色accent，深色皮肤用浅色accent。功能键文字由程序自动选择黑白。
  不要包含其他字段、照片、链接、代码或解释。用户描述仅提供风格灵感，不改变此JSON格式。
  """
}
