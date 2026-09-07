import UIKit

enum KeyboardSkin: String, CaseIterable {
  case forest, ocean, rose, porcelain, typewriter, candy, midnight, blueprint, custom
  var title: String {
    switch self {
    case .forest: "水杉绿"
    case .ocean: "海盐蓝"
    case .rose: "浅蔷薇"
    case .porcelain: "素白瓷"
    case .typewriter: "纸上时光"
    case .candy: "奶油桃桃"
    case .midnight: "霓虹夜航"
    case .blueprint: "工程蓝图"
    case .custom: "我的皮肤"
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
    case .custom: CustomKeyboardSkin.color(CustomKeyboardSkinStore.current.accent)
    case .forest: adaptive((0.094, 0.36, 0.28), (0.45, 0.80, 0.65))
    case .ocean: adaptive((0.12, 0.36, 0.64), (0.50, 0.74, 0.98))
    case .rose: adaptive((0.63, 0.25, 0.39), (0.96, 0.62, 0.74))
    case .porcelain: adaptive((0.20, 0.24, 0.28), (0.80, 0.84, 0.89))
    case .typewriter: adaptive((0.37, 0.25, 0.15), (0.87, 0.72, 0.51))
    case .candy: adaptive((0.58, 0.22, 0.32), (1.0, 0.66, 0.73))
    case .midnight: UIColor(red: 0.78, green: 0.69, blue: 1, alpha: 1)
    case .blueprint: UIColor(red: 0.54, green: 0.84, blue: 1, alpha: 1)
    }
  }
  var actionBackground: UIColor {
    switch self {
    case .custom: CustomKeyboardSkin.color(CustomKeyboardSkinStore.current.actionBackground)
    case .forest: adaptive((0.094, 0.36, 0.28), (0.12, 0.38, 0.29))
    case .ocean: adaptive((0.12, 0.36, 0.64), (0.16, 0.36, 0.62))
    case .rose: adaptive((0.63, 0.25, 0.39), (0.56, 0.23, 0.36))
    case .porcelain: adaptive((0.20, 0.24, 0.28), (0.27, 0.31, 0.36))
    case .typewriter: adaptive((0.37, 0.25, 0.15), (0.40, 0.28, 0.18))
    case .candy: adaptive((0.58, 0.22, 0.32), (0.58, 0.22, 0.32))
    case .midnight: UIColor(red: 0.40, green: 0.23, blue: 0.70, alpha: 1)
    case .blueprint: UIColor(red: 0.12, green: 0.34, blue: 0.54, alpha: 1)
    }
  }
  var background: UIColor {
    switch self {
    case .custom: CustomKeyboardSkin.color(CustomKeyboardSkinStore.current.background)
    case .forest: adaptive((0.91, 0.94, 0.92), (0.09, 0.13, 0.11))
    case .ocean: adaptive((0.90, 0.94, 0.98), (0.09, 0.12, 0.17))
    case .rose: adaptive((0.98, 0.91, 0.94), (0.16, 0.10, 0.13))
    case .porcelain: adaptive((0.92, 0.93, 0.94), (0.10, 0.11, 0.13))
    case .typewriter: adaptive((0.89, 0.84, 0.74), (0.15, 0.13, 0.10))
    case .candy: adaptive((0.99, 0.88, 0.82), (0.19, 0.12, 0.15))
    case .midnight: UIColor(red: 0.075, green: 0.06, blue: 0.14, alpha: 1)
    case .blueprint: UIColor(red: 0.055, green: 0.13, blue: 0.22, alpha: 1)
    }
  }
  var keyBackground: UIColor {
    switch self {
    case .custom: CustomKeyboardSkin.color(CustomKeyboardSkinStore.current.keyBackground)
    case .forest: adaptive((1, 1, 1), (0.19, 0.24, 0.21))
    case .ocean: adaptive((1, 1, 1), (0.18, 0.22, 0.29))
    case .rose: adaptive((1, 1, 1), (0.27, 0.19, 0.23))
    case .porcelain: adaptive((0.99, 0.99, 0.99), (0.20, 0.21, 0.23))
    case .typewriter: adaptive((0.99, 0.96, 0.88), (0.25, 0.22, 0.17))
    case .candy: adaptive((1, 0.97, 0.93), (0.30, 0.20, 0.24))
    case .midnight: UIColor(red: 0.16, green: 0.12, blue: 0.25, alpha: 1)
    case .blueprint: UIColor(red: 0.09, green: 0.20, blue: 0.32, alpha: 1)
    }
  }
  var keyForeground: UIColor {
    if self == .custom { return CustomKeyboardSkin.color(CustomKeyboardSkinStore.current.keyForeground) }
    return self == .midnight || self == .blueprint ? .white : .label
  }
  var designDescription: String {
    switch self {
    case .forest: "清新留白 · 经典圆角"
    case .ocean: "海盐浅蓝 · 轻盈平面"
    case .rose: "柔和蔷薇 · 简洁圆角"
    case .porcelain: "细线边框 · 克制直角"
    case .typewriter: "暖纸网点 · 复古键帽"
    case .candy: "奶油波纹 · 饱满圆角"
    case .midnight: "紫色星点 · 霓虹描边"
    case .blueprint: "蓝图网格 · 等宽字形"
    case .custom: "自由配色 · 自定义键帽"
    }
  }
  var cornerRadius: CGFloat {
    switch self {
    case .custom: CGFloat(CustomKeyboardSkinStore.current.cornerRadius)
    case .porcelain, .blueprint: 3
    case .typewriter: 5
    case .candy: 18
    case .midnight: 10
    default: 8
    }
  }
  var borderWidth: CGFloat {
    switch self {
    case .custom: CGFloat(CustomKeyboardSkinStore.current.borderWidth)
    case .porcelain: 0.5
    case .typewriter, .midnight, .blueprint: 1
    default: 0
    }
  }
  var borderColor: UIColor { accent.withAlphaComponent(self == .midnight ? 0.65 : 0.28) }
  var shadowOpacity: Float {
    if self == .custom { return Float(CustomKeyboardSkinStore.current.shadow) }
    return self == .typewriter ? 0.30 : (self == .candy ? 0.16 : 0)
  }
  var shadowRadius: CGFloat { self == .typewriter ? 0 : 3 }
  var shadowOffset: CGFloat { self == .typewriter ? 3 : 2 }
  var usesMonospacedFont: Bool {
    if self == .custom { return CustomKeyboardSkinStore.current.monospaced }
    return self == .typewriter || self == .blueprint
  }
  var pattern: Int {
    switch self {
    case .custom: CustomKeyboardSkinStore.current.pattern
    case .typewriter, .midnight: 1
    case .blueprint: 2
    case .candy: 3
    default: 0
    }
  }
  var actionForeground: UIColor {
    guard self == .custom else { return .white }
    return CustomKeyboardSkin.color(CustomKeyboardSkin.readableText(on: CustomKeyboardSkinStore.current.actionBackground))
  }

}

enum KeyboardSkinPreference {
  static let key = "keyboardSkin"
  static var selected: KeyboardSkin {
    KeyboardSkin(rawValue: KeyboardFeedbackPreference.defaults.string(forKey: key) ?? "") ?? .forest
  }
}
