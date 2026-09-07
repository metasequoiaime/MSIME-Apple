import UIKit
import SwiftUI

final class KeyboardSkinBackgroundView: UIView {
  var skin: KeyboardSkin = .forest {
    didSet { backgroundColor = skin.background; setNeedsDisplay() }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    isAccessibilityElement = false
    contentMode = .redraw
    backgroundColor = skin.background
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func draw(_ rect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext(), skin.pattern != 0 else { return }
    let tint = skin.accent.resolvedColor(with: traitCollection).withAlphaComponent(0.15)
    context.setStrokeColor(tint.cgColor)
    context.setFillColor(tint.cgColor)
    context.setLineWidth(0.5)
    switch skin.pattern {
    case 1:
      for y in stride(from: CGFloat(8), to: bounds.height, by: 16) {
        for x in stride(from: CGFloat(8), to: bounds.width, by: 16) {
          context.fillEllipse(in: CGRect(x: x, y: y, width: 1.5, height: 1.5))
        }
      }
    case 2:
      for x in stride(from: CGFloat(0), to: bounds.width, by: 20) {
        context.move(to: CGPoint(x: x, y: 0)); context.addLine(to: CGPoint(x: x, y: bounds.height))
      }
      for y in stride(from: CGFloat(0), to: bounds.height, by: 20) {
        context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: bounds.width, y: y))
      }
      context.strokePath()
    default:
      context.setLineWidth(2)
      for offset in stride(from: CGFloat(-100), to: bounds.height + bounds.width, by: 24) {
        context.move(to: CGPoint(x: 0, y: offset))
        context.addCurve(to: CGPoint(x: bounds.width, y: offset - 70),
          control1: CGPoint(x: bounds.width * 0.35, y: offset - 90),
          control2: CGPoint(x: bounds.width * 0.65, y: offset + 20))
      }
      context.strokePath()
    }
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    setNeedsDisplay()
  }
}

struct KeyboardSkinBackdrop: UIViewRepresentable {
  let skin: KeyboardSkin
  @Environment(\.colorScheme) private var colorScheme
  func makeUIView(context: Context) -> KeyboardSkinBackgroundView { KeyboardSkinBackgroundView() }
  func updateUIView(_ view: KeyboardSkinBackgroundView, context: Context) {
    view.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
    view.skin = skin
  }
}
