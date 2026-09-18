import AppKit

@MainActor final class MacEmojiDeliveryNotice {
  static let message = "表情回填未完成，请回到输入位置重试。"
  private var panel: Panel?
  private var dismissal: DispatchWorkItem?

  final class Panel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
  }

  static func makePanel() -> Panel {
    let panel = Panel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 64),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    panel.ignoresMouseEvents = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.hasShadow = true
    panel.backgroundColor = .windowBackgroundColor
    let label = NSTextField(wrappingLabelWithString: message)
    label.font = .systemFont(ofSize: 14)
    label.textColor = .labelColor
    label.frame = NSRect(x: 16, y: 12, width: 308, height: 40)
    panel.contentView?.addSubview(label)
    return panel
  }

  func show() {
    dismissal?.cancel()
    let notice = panel ?? Self.makePanel()
    panel = notice
    if let screen = NSScreen.main ?? NSScreen.screens.first {
      let visible = screen.visibleFrame
      notice.setFrameOrigin(NSPoint(x: visible.midX - notice.frame.width / 2, y: visible.minY + 32))
    }
    notice.orderFrontRegardless()
    let work = DispatchWorkItem { [weak self] in self?.dismiss() }
    dismissal = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
  }

  func dismiss() {
    dismissal?.cancel()
    dismissal = nil
    panel?.orderOut(nil)
    panel = nil
  }
}
