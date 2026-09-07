import UIKit

enum KeyboardSkin: String, CaseIterable {
  case forest, ocean, rose
  var title: String {
    switch self {
    case .forest: "水杉绿"
    case .ocean: "海盐蓝"
    case .rose: "浅蔷薇"
    }
  }
  var accent: UIColor {
    switch self {
    case .forest: UIColor(red: 0.094, green: 0.36, blue: 0.28, alpha: 1)
    case .ocean: UIColor(red: 0.12, green: 0.36, blue: 0.64, alpha: 1)
    case .rose: UIColor(red: 0.63, green: 0.25, blue: 0.39, alpha: 1)
    }
  }
  var background: UIColor {
    switch self {
    case .forest: UIColor(red: 0.91, green: 0.94, blue: 0.92, alpha: 1)
    case .ocean: UIColor(red: 0.90, green: 0.94, blue: 0.98, alpha: 1)
    case .rose: UIColor(red: 0.98, green: 0.91, blue: 0.94, alpha: 1)
    }
  }
}

enum KeyboardSkinPreference {
  static let key = "keyboardSkin"
  static var selected: KeyboardSkin {
    KeyboardSkin(rawValue: KeyboardFeedbackPreference.defaults.string(forKey: key) ?? "") ?? .forest
  }
}
