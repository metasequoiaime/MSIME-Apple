import UIKit

/// Candidate and composition text size, read from the shared preference document.
///
/// The document stores points as the desktop candidate window uses them, 18 for candidates and 15 for the composition. iOS draws with Dynamic Type instead, so those defaults stand for the `.body` and `.subheadline` styles the keyboard already used, and any other value scales them by the same ratio; the user's system text size keeps applying on top. A phone strip has far less width than an iPad one, so a size synced from a desktop is clamped to what that surface can show.
enum CandidateFontPreference {
  static let candidateKey = "candidate_font_size"
  static let preeditKey = "candidate_preedit_font_size"
  static let defaultCandidateSize = 18
  static let defaultPreeditSize = 15

  static func candidateRange(tablet: Bool) -> ClosedRange<Int> { tablet ? 12...32 : 12...24 }
  static func preeditRange(tablet: Bool) -> ClosedRange<Int> { tablet ? 12...24 : 12...20 }

  static func candidateSize(in preferences: [String: Any]?, tablet: Bool) -> Int {
    size(preferences?[candidateKey], default: defaultCandidateSize, range: candidateRange(tablet: tablet))
  }

  static func preeditSize(in preferences: [String: Any]?, tablet: Bool) -> Int {
    size(preferences?[preeditKey], default: defaultPreeditSize, range: preeditRange(tablet: tablet))
  }

  /// How much larger than `.body` the candidates are drawn.
  static func candidateScale(in preferences: [String: Any]?, tablet: Bool) -> CGFloat {
    CGFloat(candidateSize(in: preferences, tablet: tablet)) / CGFloat(defaultCandidateSize)
  }

  /// How much larger than `.subheadline` the composition is drawn.
  static func preeditScale(in preferences: [String: Any]?, tablet: Bool) -> CGFloat {
    CGFloat(preeditSize(in: preferences, tablet: tablet)) / CGFloat(defaultPreeditSize)
  }

  /// The text style scaled at the default text size, then handed to `UIFontMetrics` so the system text size still scales it and a label that adjusts for content size keeps doing so.
  static func font(_ style: UIFont.TextStyle, scale: CGFloat) -> UIFont {
    guard scale != 1 else { return .preferredFont(forTextStyle: style) }
    let base = UIFont.preferredFont(
      forTextStyle: style, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large))
    return UIFontMetrics(forTextStyle: style).scaledFont(for: base.withSize((base.pointSize * scale).rounded()))
  }

  private static func size(_ value: Any?, default fallback: Int, range: ClosedRange<Int>) -> Int {
    guard let number = value as? NSNumber else { return fallback }
    return min(max(number.intValue, range.lowerBound), range.upperBound)
  }
}
