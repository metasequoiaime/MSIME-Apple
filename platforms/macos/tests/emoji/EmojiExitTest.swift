import AppKit
@main enum EmojiExitTest {
  @MainActor static func main() {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
    let other = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
    defer { window.close(); other.close() }
    let capture = MacEmojiExitView(); window.contentView = capture
    var returned = 0; capture.goHome = { returned += 1 }
    func event(_ number: Int, key: UInt16 = 53, flags: NSEvent.ModifierFlags = []) -> NSEvent {
      NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: number, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: key)!
    }
    capture.enabled = true
    assert(capture.handle(event(window.windowNumber)) && returned == 1)
    assert(!capture.handle(event(other.windowNumber)) && returned == 1)
    for flag: NSEvent.ModifierFlags in [.command, .control, .option, .shift] { assert(!capture.handle(event(window.windowNumber, flags: flag))) }
    assert(!capture.handle(event(window.windowNumber, key: 36)))
    capture.enabled = false; assert(!capture.handle(event(window.windowNumber)))
    capture.enabled = true; capture.stop(); assert(!capture.handle(event(window.windowNumber)))
    print("Window-scoped Escape routing, home pass-through, modifiers and teardown passed")
  }
}
