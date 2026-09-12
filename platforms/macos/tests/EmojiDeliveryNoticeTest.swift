import AppKit

@main enum EmojiDeliveryNoticeTest {
  @MainActor static func main() {
    _ = NSApplication.shared
    let panel = MacEmojiDeliveryNotice.makePanel()
    assert(!panel.canBecomeKey && !panel.canBecomeMain)
    assert(panel.styleMask.contains(.nonactivatingPanel))
    assert(panel.ignoresMouseEvents && !panel.hidesOnDeactivate)
    assert(panel.level == .floating)
    assert(!panel.isVisible)
    let label = panel.contentView?.subviews.compactMap { $0 as? NSTextField }.first
    assert(label?.stringValue == MacEmojiDeliveryNotice.message)
    assert(label?.isEditable == false)
    assert(panel.frame.size == NSSize(width: 340, height: 64))
    panel.close()
    print("Emoji delivery notice configuration checks passed")
  }
}
