import SwiftUI
import UIKit

enum MetasequoiaTheme {
  static let forest = Color(red: 24 / 255, green: 92 / 255, blue: 72 / 255)
  // Adaptive accents for text and icons; forest stays dark for white button labels.
  static let accent = Color(uiColor: forestUIColor)
  static let canvas = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 17 / 255, green: 24 / 255, blue: 21 / 255, alpha: 1)
      : UIColor(red: 241 / 255, green: 247 / 255, blue: 243 / 255, alpha: 1)
  })
  static let surface = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 29 / 255, green: 38 / 255, blue: 33 / 255, alpha: 1)
      : .white
  })
  static let needle = Color(red: 77 / 255, green: 138 / 255, blue: 114 / 255)
  static let mist = Color(red: 243 / 255, green: 247 / 255, blue: 245 / 255)
  static let cone = Color(red: 167 / 255, green: 103 / 255, blue: 59 / 255)
  static let ink = Color(red: 20 / 255, green: 35 / 255, blue: 29 / 255)

  // Text and glyphs drawn on top of forestUIColor. The two shades of forest sit on opposite sides
  // of the contrast line, so a single foreground fails one of them: white reads 7.9:1 on the light
  // shade but 2.5:1 on the dark one, which is below even the large-text floor.
  static let onForestUIColor = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 20 / 255, green: 35 / 255, blue: 29 / 255, alpha: 1)
      : .white
  }

  static let forestUIColor = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 97 / 255, green: 180 / 255, blue: 145 / 255, alpha: 1)
      : UIColor(red: 24 / 255, green: 92 / 255, blue: 72 / 255, alpha: 1)
  }

  static let coneUIColor = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 214 / 255, green: 150 / 255, blue: 105 / 255, alpha: 1)
      : UIColor(red: 167 / 255, green: 103 / 255, blue: 59 / 255, alpha: 1)
  }

  static let keyboardBackground = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 24 / 255, green: 30 / 255, blue: 27 / 255, alpha: 1)
      : UIColor(red: 232 / 255, green: 239 / 255, blue: 235 / 255, alpha: 1)
  }

  static let keyBackground = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 48 / 255, green: 56 / 255, blue: 52 / 255, alpha: 1)
      : .white
  }
}

struct MetasequoiaMark: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let centerX = rect.midX
    path.move(to: CGPoint(x: centerX, y: rect.minY + rect.height * 0.08))
    path.addLine(to: CGPoint(x: centerX, y: rect.maxY * 0.9))

    for level in 0..<4 {
      let y = rect.minY + rect.height * (0.25 + CGFloat(level) * 0.18)
      let reach = rect.width * (0.2 + CGFloat(level) * 0.08)
      path.move(to: CGPoint(x: centerX, y: y - rect.height * 0.11))
      path.addLine(to: CGPoint(x: centerX - reach, y: y))
      path.move(to: CGPoint(x: centerX, y: y - rect.height * 0.11))
      path.addLine(to: CGPoint(x: centerX + reach, y: y))
    }
    return path
  }
}
