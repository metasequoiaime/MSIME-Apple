import AppKit
import SwiftUI

struct MacEmojiExitHandler: ViewModifier {
  let category: String
  let goHome: () -> Void
  func body(content: Content) -> some View {
    content.background(MacEmojiExitCapture(enabled: category != "home", goHome: goHome).frame(width: 0, height: 0))
  }
}

private struct MacEmojiExitCapture: NSViewRepresentable {
  let enabled: Bool
  let goHome: () -> Void
  func makeNSView(context: Context) -> MacEmojiExitView { MacEmojiExitView() }
  func updateNSView(_ view: MacEmojiExitView, context: Context) {
    view.enabled = enabled; view.goHome = goHome
  }
  static func dismantleNSView(_ view: MacEmojiExitView, coordinator: ()) { view.stop() }
}

final class MacEmojiExitView: NSView {
  var enabled = false
  var goHome: () -> Void = {}
  private var monitor: Any?
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow(); stop()
    guard window != nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      self?.handle(event) == true ? nil : event
    }
  }
  func handle(_ event: NSEvent) -> Bool {
    guard enabled, let window, event.window === window, event.keyCode == 53,
      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
    goHome(); return true
  }
  func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; enabled = false }
  deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
