import Foundation

enum MacEmojiMainPage: String, CaseIterable {
  case home, emoji = "", kaomoji, symbols, sticker, gif, clipboard
  var title: String {
    switch self {
    case .home: return "首页"
    case .emoji: return "表情"
    case .kaomoji: return "颜文字"
    case .symbols: return "符号"
    case .sticker: return "贴纸"
    case .gif: return "GIF"
    case .clipboard: return "剪贴板"
    }
  }
  func destination(hasRecents: Bool) -> String {
    self == .emoji && hasRecents ? "recent" : rawValue
  }
  static func title(category: String) -> String {
    category == "recent" ? Self.emoji.title : Self(rawValue: category)?.title ?? ""
  }
}

enum MacEmojiSectionChoice: Hashable {
  case recent
  case group(String)

  static func resolvedGroup(requested: String?, current: String, groups: [String]) -> String {
    let proposed = requested ?? current
    return groups.contains(proposed) ? proposed : groups.first ?? ""
  }
}
