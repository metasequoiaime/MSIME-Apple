import UIKit

final class HandwritingCanvas: UIView {
  var acceptsInk = false
  var onStrokeBegan: (() -> Void)?
  var onChange: (() -> Void)?
  private(set) var strokes: [[CGPoint]] = []
  var hasInk: Bool { !strokes.isEmpty }

  func clear() { strokes.removeAll(); setNeedsDisplay(); onChange?() }
  func undo() { _ = strokes.popLast(); setNeedsDisplay(); onChange?() }
  func setTestStrokes(_ values: [[CGPoint]]) { strokes = values; setNeedsDisplay(); onChange?() }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard acceptsInk, let point = touches.first?.location(in: self) else { return }
    strokes.append([point]); onStrokeBegan?(); setNeedsDisplay()
  }
  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard acceptsInk, let point = touches.first?.location(in: self), !strokes.isEmpty else { return }
    strokes[strokes.index(before: strokes.endIndex)].append(point); onChange?(); setNeedsDisplay()
  }
  override func draw(_ rect: CGRect) {
    UIColor.secondarySystemBackground.setFill(); UIRectFill(rect)
    UIColor.label.setStroke();
    for stroke in strokes where stroke.count > 1 {
      let path = UIBezierPath(); path.move(to: stroke[0]);
      for point in stroke.dropFirst() { path.addLine(to: point) }
      path.lineWidth = 3; path.lineCapStyle = .round; path.stroke()
    }
  }
}

final class HandwritingInputView: UIView {
  let canvas = HandwritingCanvas()
  var canDownload: () -> Bool = { false }
  var onInsert: ((String) -> Void)?
  var onDelete: (() -> Void)?
  var hasInk: Bool { canvas.hasInk }

  override init(frame: CGRect) {
    super.init(frame: frame)
    addSubview(canvas); canvas.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      canvas.leadingAnchor.constraint(equalTo: leadingAnchor), canvas.trailingAnchor.constraint(equalTo: trailingAnchor),
      canvas.topAnchor.constraint(equalTo: topAnchor), canvas.bottomAnchor.constraint(equalTo: bottomAnchor),
      heightAnchor.constraint(greaterThanOrEqualToConstant: 120)
    ])
    canvas.acceptsInk = true
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func activate() { canvas.acceptsInk = true }
  func deactivate() { clear() }
  func clear() { canvas.clear() }
  func commitFirst() -> Bool { false }
}
