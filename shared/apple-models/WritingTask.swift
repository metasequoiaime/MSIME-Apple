import Foundation

enum WritingTask: String, CaseIterable, Identifiable {
  case polish, reply
  var id: String { rawValue }
  var title: String { self == .polish ? "AI 润色" : "帮你回复" }
  static let replyStyles = ["专属回复", "暖心关怀", "捧场王", "恋人", "幽默风趣", "成熟稳重", "土味情话", "高情商", "委婉拒绝"]
  static let styles = ["自然"] + replyStyles
  func prompt(style: String, templatePrompt: String? = nil) -> String {
    if let templatePrompt {
      return "\(self == .polish ? "润色用户原文，保持原意。" : "用户内容是对方发来的话，请代拟回复。")\n\(templatePrompt)\n只输出可直接使用的一条回复，不编造事实或承诺。"
    }
    if self == .polish {
      return "请以\(style)的语气润色用户文字，保持原意，不编造事实或承诺。只输出一条简短自然的成稿，不加标题、解释或引号。"
    }
    return "用户内容是对方发来的话，请代拟一条\(style)风格的回复。尊重对方且有边界，不编造事实、关系或承诺。只输出一条简短自然、可以直接发送的回复，不加标题、解释或引号。"
  }
}
