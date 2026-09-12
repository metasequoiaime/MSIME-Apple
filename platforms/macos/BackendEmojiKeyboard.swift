import AppKit
import SwiftUI

enum MacEmojiGridCommand: Equatable {
  case left, right, up, down, home, end, activate

  static func decode(key: UInt16, modifiers: NSEvent.ModifierFlags) -> Self? {
    guard modifiers.intersection([.command, .control, .option]).isEmpty else { return nil }
    switch key {
    case 123: return .left
    case 124: return .right
    case 126: return .up
    case 125: return .down
    case 115: return .home
    case 119: return .end
    case 36, 76, 49: return .activate
    default: return nil
    }
  }

  func destination(from selected: Int, count: Int, columns: Int) -> Int? {
    guard count > 0, columns > 0 else { return nil }
    let index = min(max(selected, 0), count - 1)
    switch self {
    case .left: return max(index - 1, 0)
    case .right: return min(index + 1, count - 1)
    case .up: return max(index - columns, 0)
    case .down: return index + min(columns, count - 1 - index)
    case .home: return 0
    case .end: return count - 1
    case .activate: return index
    }
  }
}

/// A native key-view-loop entry, scoped to this panel rather than a global monitor.
struct MacEmojiKeyboardEntry: NSViewRepresentable {
  var enabled: Bool
  var onCommand: (MacEmojiGridCommand) -> Void

  func makeNSView(context: Context) -> Entry {
    let view = Entry(title: "键盘浏览", target: nil, action: nil)
    view.bezelStyle = .rounded
    view.target = view
    view.action = #selector(Entry.beginBrowsing)
    view.toolTip = "方向键选择，Home/End 跳转，回车或空格复制；Tab 离开"
    view.setAccessibilityLabel("键盘浏览表情")
    view.setAccessibilityHelp(view.toolTip)
    return view
  }
  func updateNSView(_ view: Entry, context: Context) {
    view.isEnabled = enabled
    view.onCommand = onCommand
  }
  final class Entry: NSButton {
    var onCommand: (MacEmojiGridCommand) -> Void = { _ in }
    override var acceptsFirstResponder: Bool { isEnabled }
    @objc func beginBrowsing() { window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) {
      if !handleKey(event) { super.keyDown(with: event) }
    }
    func handleKey(_ event: NSEvent) -> Bool {
      guard isEnabled, window?.firstResponder === self,
            let command = MacEmojiGridCommand.decode(key: event.keyCode, modifiers: event.modifierFlags) else {
        return false
      }
      onCommand(command)
      return true
    }
  }
}
