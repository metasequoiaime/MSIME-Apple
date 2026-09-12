import AppKit
import SwiftUI

@main enum EmojiWindowChromeTest {
  @MainActor static func main() {
    _ = NSApplication.shared
    let window = MacEmojiPanelWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 560), styleMask: [.borderless, .closable, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    assert(window.styleMask.contains(.borderless) && !window.styleMask.contains(.titled))
    assert(window.styleMask.contains(.resizable))
    assert(window.canBecomeKey && window.canBecomeMain)
    window.close()
    print("Borderless emoji window chrome passed")
  }
}
