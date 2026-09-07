import UIKit

/// UIKit checks the visible input view, not its controller, before playing input clicks.
final class KeyboardInputView: UIInputView, UIInputViewAudioFeedback {
  var enableInputClicksWhenVisible: Bool { KeyboardFeedbackPreference.soundEnabled }
}
