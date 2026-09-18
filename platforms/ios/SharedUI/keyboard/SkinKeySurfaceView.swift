import SwiftUI
import UIKit

// One renderer for the keyboard extension, the editor and community previews.
final class SkinKeySurfaceView: UIView {
  var design = CustomKeyboardSkin() { didSet { setNeedsDisplay() } }
  var fillColor = UIColor.white { didSet { setNeedsDisplay() } }
  var scale: CGFloat = 1 { didSet { setNeedsDisplay() } }

  override init(frame: CGRect) {
    super.init(frame: frame)
    isOpaque = false
    isUserInteractionEnabled = false
    contentMode = .redraw
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  static func path(in rect: CGRect, shape: SkinKeyShape, radius: CGFloat) -> UIBezierPath {
    switch shape {
    case .rounded:
      return UIBezierPath(roundedRect: rect, cornerRadius: min(radius, min(rect.width, rect.height) / 2))
    case .capsule:
      return UIBezierPath(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2)
    case .pebble:
      let p = UIBezierPath()
      let x = rect.minX, y = rect.minY, w = rect.width, h = rect.height
      p.move(to: CGPoint(x: x + w * 0.35, y: y))
      p.addCurve(to: CGPoint(x: x + w, y: y + h * 0.3), controlPoint1: CGPoint(x: x + w * 0.83, y: y), controlPoint2: CGPoint(x: x + w, y: y + h * 0.04))
      p.addCurve(to: CGPoint(x: x + w * 0.68, y: y + h), controlPoint1: CGPoint(x: x + w, y: y + h * 0.85), controlPoint2: CGPoint(x: x + w * 0.9, y: y + h))
      p.addCurve(to: CGPoint(x: x, y: y + h * 0.7), controlPoint1: CGPoint(x: x + w * 0.18, y: y + h), controlPoint2: CGPoint(x: x, y: y + h * 0.97))
      p.addCurve(to: CGPoint(x: x + w * 0.35, y: y), controlPoint1: CGPoint(x: x, y: y + h * 0.2), controlPoint2: CGPoint(x: x + w * 0.06, y: y))
      p.close()
      return p
    case .ticket:
      let p = UIBezierPath()
      let r = min(rect.width, rect.height) * 0.12
      p.move(to: CGPoint(x: rect.minX, y: rect.minY))
      p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
      p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY - r))
      p.addArc(withCenter: CGPoint(x: rect.maxX, y: rect.midY), radius: r, startAngle: -.pi / 2, endAngle: -.pi * 1.5, clockwise: false)
      p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
      p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
      p.addLine(to: CGPoint(x: rect.minX, y: rect.midY + r))
      p.addArc(withCenter: CGPoint(x: rect.minX, y: rect.midY), radius: r, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: false)
      p.close()
      return p
    }
  }

  override func draw(_ rect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext(), bounds.width > 2, bounds.height > 2 else { return }
    let value = design.normalized
    let material = value.keyMaterial ?? .flat
    let depth: CGFloat = material == .raised ? 3 * scale : 0
    let face = bounds.insetBy(dx: scale, dy: scale).inset(by: UIEdgeInsets(top: 0, left: 0, bottom: depth, right: 0))
    let path = Self.path(in: face, shape: value.keyShape ?? .rounded, radius: value.cornerRadius * scale)
    context.saveGState()
    if depth > 0 {
      context.saveGState()
      context.translateBy(x: 0, y: depth)
      fillColor.setFill(); path.fill()
      UIColor.black.withAlphaComponent(0.28).setFill(); path.fill()
      context.restoreGState()
    }
    if value.shadow > 0 {
      context.setShadow(offset: CGSize(width: 0, height: scale), blur: 2 * scale,
                        color: UIColor.black.withAlphaComponent(value.shadow).cgColor)
    }
    fillColor.setFill(); path.fill()
    context.restoreGState()
    context.saveGState()
    path.addClip()
    if material == .glass || material == .raised {
      let alpha: CGFloat = material == .glass ? 0.24 : 0.13
      let colors = [UIColor.white.withAlphaComponent(alpha).cgColor, UIColor.white.withAlphaComponent(0).cgColor,
                    UIColor.black.withAlphaComponent(material == .glass ? 0.03 : 0.10).cgColor] as CFArray
      if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.48, 1]) {
        context.drawLinearGradient(gradient, start: CGPoint(x: face.midX, y: face.minY), end: CGPoint(x: face.midX, y: face.maxY), options: [])
      }
      if material == .glass {
        let shine = UIBezierPath()
        shine.move(to: CGPoint(x: face.minX, y: face.minY))
        shine.addLine(to: CGPoint(x: face.maxX, y: face.minY))
        shine.addLine(to: CGPoint(x: face.minX, y: face.maxY * 0.6))
        shine.close()
        UIColor.white.withAlphaComponent(0.09).setFill(); shine.fill()
      }
    } else if material == .paper {
      // Fixed fibers: stable while typing and independent of random state.
      context.setStrokeColor(UIColor.black.withAlphaComponent(0.08).cgColor)
      context.setLineWidth(0.5 * scale)
      for row in stride(from: 3, to: Int(face.height), by: max(2, Int(4 * scale))) {
        let y = face.minY + CGFloat(row)
        context.move(to: CGPoint(x: face.minX, y: y))
        context.addLine(to: CGPoint(x: face.maxX, y: y - scale))
      }
      context.strokePath()
    }
    context.restoreGState()
    if value.borderWidth > 0 {
      CustomKeyboardSkin.color(value.customBorderColor ?? value.accent).setStroke()
      path.lineWidth = value.borderWidth * scale; path.stroke()
    }
  }
}

struct SkinKeySurface: UIViewRepresentable {
  let design: CustomKeyboardSkin
  let action: Bool
  var scale: CGFloat = 1
  func makeUIView(context: Context) -> SkinKeySurfaceView { SkinKeySurfaceView() }
  func updateUIView(_ view: SkinKeySurfaceView, context: Context) {
    view.design = design
    view.scale = scale
    view.fillColor = CustomKeyboardSkin.color(action ? design.actionBackground : design.keyBackground)
      .withAlphaComponent(action ? 1 : design.keyOpacity ?? 1)
  }
}
