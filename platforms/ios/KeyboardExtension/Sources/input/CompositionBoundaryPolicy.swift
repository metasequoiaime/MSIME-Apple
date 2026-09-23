import Foundation

/// A point where the keyboard has to end an open composition.
enum CompositionBoundary {
  /// The 中/英 key, Shift in a scheme without helper codes, or the globe key.
  case modeSwitch
  /// Return while composing.
  case returnKey
  /// Anything else that takes the text away from the composition: a cursor move, a panel, the keyboard going away.
  case deactivate
}

enum CompositionBoundaryAction: Equatable {
  case none
  case commitRaw
  case finishComposition
}

/// What a boundary does to an open composition, the rule the Windows host and the HarmonyOS keyboard share: switching modes or pressing Return keeps what was typed as typed (any half-chosen phrase, then the raw letters), so `iphone` + Return is `iphone` and a wubi code + 英 is the code, while leaving the composition any other way commits the conversion. Japanese always converts, since its raw romaji is not what anyone meant to write, and so does nine-key, whose raw keys are digits rather than letters.
enum CompositionBoundaryPolicy {
  static func action(composing: Bool, scheme: ChineseInputScheme,
                     boundary: CompositionBoundary) -> CompositionBoundaryAction {
    guard composing else { return .none }
    if boundary == .deactivate || scheme.isJapanese || scheme == .nineKey { return .finishComposition }
    return .commitRaw
  }
}
