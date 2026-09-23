import Foundation

/// One write that brings the host's marked text in line with the composition.
enum InlineCompositionEdit: Equatable {
  /// Replace the marked text with this, caret at its end.
  case mark(String)
  /// Remove the marked text and end marking.
  case clear
}

/// The marked text a keyboard extension leaves in the host while 行内预编辑 is on.
///
/// The host document holds the marked letters as long as the composition runs, so anything that reads the text before the caret has to look past them, and a composition that ends by commit has to take them out before the committed text goes in; otherwise the letters and the conversion would both stay.
enum InlineCompositionPolicy {
  /// The write that turns `current` marked text into `next`, or nil when the host already shows it.
  static func edit(showing current: String, next: String) -> InlineCompositionEdit? {
    guard current != next else { return nil }
    return next.isEmpty ? .clear : .mark(next)
  }

  /// The document text before the composition, which is what punctuation and smart-punctuation context mean by "before the caret".
  static func contextBefore(_ before: String?, marked: String) -> String? {
    guard !marked.isEmpty, let before, before.hasSuffix(marked) else { return before }
    return String(before.dropLast(marked.count))
  }
}
