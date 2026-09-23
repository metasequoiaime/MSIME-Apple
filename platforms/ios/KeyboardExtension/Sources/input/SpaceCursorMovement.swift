import CoreGraphics
import Foundation

struct SpaceCursorMovement {
  private var previous: CGFloat = 0
  private var remainder: CGFloat = 0
  private var document: UUID?
  var isActive: Bool { document != nil }

  mutating func begin(at translation: CGFloat, document: UUID) {
    guard translation.isFinite else { cancel(); return }
    self.document = document
    previous = translation
    remainder = 0
  }

  mutating func advance(to translation: CGFloat, document: UUID) -> Int {
    guard self.document == document, translation.isFinite else { cancel(); return 0 }
    // Ignore impossible jumps instead of converting unbounded input to an integer offset.
    guard abs(translation - previous) <= 4096 else { cancel(); return 0 }
    remainder += translation - previous
    previous = translation
    let steps = Int(remainder / 12)
    remainder -= CGFloat(steps) * 12
    return steps
  }

  /// A quick flick through the spelling jumps a syllable per step, as Ctrl+← / → does in the Windows composition; a slow drag still walks letter by letter, which is what fixing one mistyped letter needs.
  static let segmentVelocity: CGFloat = 900

  static func movesBySegment(velocity: CGFloat) -> Bool {
    velocity.isFinite && abs(velocity) >= segmentVelocity
  }

  mutating func cancel() {
    document = nil
    previous = 0
    remainder = 0
  }
}
