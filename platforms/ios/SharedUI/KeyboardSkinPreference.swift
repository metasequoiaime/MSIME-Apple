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
  private func adaptive(_ light: (CGFloat, CGFloat, CGFloat), _ dark: (CGFloat, CGFloat, CGFloat)) -> UIColor {
    UIColor { traits in
      let color = traits.userInterfaceStyle == .dark ? dark : light
      return UIColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
    }
  }
  var accent: UIColor {
    switch self {
    case .forest: adaptive((0.094, 0.36, 0.28), (0.45, 0.80, 0.65))
    case .ocean: adaptive((0.12, 0.36, 0.64), (0.50, 0.74, 0.98))
    case .rose: adaptive((0.63, 0.25, 0.39), (0.96, 0.62, 0.74))
    }
  }
  var actionBackground: UIColor {
    switch self {
    case .forest: adaptive((0.094, 0.36, 0.28), (0.12, 0.38, 0.29))
    case .ocean: adaptive((0.12, 0.36, 0.64), (0.16, 0.36, 0.62))
    case .rose: adaptive((0.63, 0.25, 0.39), (0.56, 0.23, 0.36))
    }
  }
  var background: UIColor {
    switch self {
    case .forest: adaptive((0.91, 0.94, 0.92), (0.09, 0.13, 0.11))
    case .ocean: adaptive((0.90, 0.94, 0.98), (0.09, 0.12, 0.17))
    case .rose: adaptive((0.98, 0.91, 0.94), (0.16, 0.10, 0.13))
    }
  }
  var keyBackground: UIColor {
    switch self {
    case .forest: adaptive((1, 1, 1), (0.19, 0.24, 0.21))
    case .ocean: adaptive((1, 1, 1), (0.18, 0.22, 0.29))
    case .rose: adaptive((1, 1, 1), (0.27, 0.19, 0.23))
    }
  }
  var keyForeground: UIColor { .label }
  var actionForeground: UIColor { .white }

}

enum KeyboardSkinPreference {
  static let key = "keyboardSkin"
  static var selected: KeyboardSkin {
    KeyboardSkin(rawValue: KeyboardFeedbackPreference.defaults.string(forKey: key) ?? "") ?? .forest
  }
}
