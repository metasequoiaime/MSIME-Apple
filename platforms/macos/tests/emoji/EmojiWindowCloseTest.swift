import AppKit

@main enum EmojiWindowCloseTest {
  @MainActor static func main() {
    _ = NSApplication.shared
    let content = NSViewController()
    content.view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
    let window = NSWindow(contentViewController: content)
    window.isReleasedWhenClosed = false
    let controller = MacEmojiWindowController(window: window)
    window.delegate = controller
    let other = NSWindow()
    controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: other))
    precondition(window.contentViewController === content)
    window.close()
    precondition(window.contentViewController == nil && window.contentView == nil)
    print("Emoji window close releases content; unrelated close is ignored")
  }
}
