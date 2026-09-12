import AppKit

/// Window caching must not keep a closed panel's polling SwiftUI view alive.
@MainActor final class MacEmojiWindowController: NSWindowController, NSWindowDelegate {
  func windowWillClose(_ notification: Notification) {
    guard let closing = notification.object as? NSWindow, closing === window else { return }
    closing.contentViewController = nil
    closing.contentView = nil
  }
}
