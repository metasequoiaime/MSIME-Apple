import AppKit
import SwiftUI

@main enum EmojiKeyboardTest {
  @MainActor static func main() {
    _ = NSApplication.shared
    for columns in [3, 8] {
      for count in [1, 2, 9, 17, 255] {
        for index in 0..<count {
          assert(MacEmojiGridCommand.left.destination(from: index, count: count, columns: columns) == max(0, index - 1))
          assert(MacEmojiGridCommand.right.destination(from: index, count: count, columns: columns) == min(count - 1, index + 1))
          assert(MacEmojiGridCommand.up.destination(from: index, count: count, columns: columns) == max(0, index - columns))
          assert(MacEmojiGridCommand.down.destination(from: index, count: count, columns: columns) == min(count - 1, index + columns))
          assert(MacEmojiGridCommand.home.destination(from: index, count: count, columns: columns) == 0)
          assert(MacEmojiGridCommand.end.destination(from: index, count: count, columns: columns) == count - 1)
        }
      }
    }
    assert(MacEmojiGridCommand.activate.destination(from: 0, count: 0, columns: 8) == nil)
    assert(MacEmojiGridCommand.down.destination(from: 1000, count: 3, columns: 8) == 2)
    assert(MacEmojiGridCommand.up.destination(from: -5, count: 3, columns: 8) == 0)
    assert(MacEmojiGridCommand.down.destination(from: 0, count: 3, columns: 0) == nil)
    for code: UInt16 in [36, 76, 49] {
      assert(MacEmojiGridCommand.decode(key: code, modifiers: []) == .activate)
      for modifier: NSEvent.ModifierFlags in [.command, .control, .option] {
        assert(MacEmojiGridCommand.decode(key: code, modifiers: modifier) == nil)
      }
    }
    assert(MacEmojiGridCommand.decode(key: 48, modifiers: []) == nil)
    assert(MacEmojiGridCommand.decode(key: 53, modifiers: []) == nil)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let entry = MacEmojiKeyboardEntry.Entry(title: "Synthetic browse", target: nil, action: nil)
    window.contentView = entry
    assert(window.makeFirstResponder(entry))
    var commands: [MacEmojiGridCommand] = []
    entry.onCommand = { commands.append($0) }
    for code: UInt16 in [123, 124, 126, 125, 115, 119, 36, 76, 49] {
      let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
      entry.keyDown(with: event)
    }
    assert(commands == [.left, .right, .up, .down, .home, .end, .activate, .activate, .activate])
    let activate = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
      windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 36)!
    entry.isEnabled = false
    assert(!entry.acceptsFirstResponder)
    assert(!entry.handleKey(activate))
    entry.isEnabled = true
    assert(window.makeFirstResponder(nil))
    assert(!entry.handleKey(activate))
    assert(commands.count == 9)
    window.close()
    print("Emoji keyboard navigation checks passed")
  }
}
