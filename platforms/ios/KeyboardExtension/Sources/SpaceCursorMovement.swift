import CoreGraphics

struct SpaceCursorMovement {
  private var previous: CGFloat = 0
  private var remainder: CGFloat = 0

  mutating func begin(at translation: CGFloat) {
    previous = translation
    remainder = 0
  }

  mutating func advance(to translation: CGFloat) -> Int {
    guard translation.isFinite else { return 0 }
    remainder += translation - previous
    previous = translation
    let steps = Int(remainder / 12)
    remainder -= CGFloat(steps) * 12
    return steps
  }
}
