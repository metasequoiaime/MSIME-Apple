import AppKit
import SwiftUI

@MainActor final class ScrollFixture: ObservableObject {
  @Published var resetID = ["synthetic", "0"]
  @Published var refresh = 0
}

struct ScrollFixtureView: View {
  @ObservedObject var fixture: ScrollFixture
  var body: some View {
    MacEmojiScroll(resetID: fixture.resetID) {
      VStack {
        Text("Synthetic refresh \(fixture.refresh)")
        Color.clear.frame(width: 200, height: 2000)
      }
    }.frame(width: 240, height: 200)
  }
}

@main enum EmojiScrollTest {
  @MainActor static func main() {
    _ = NSApplication.shared
    let fixture = ScrollFixture()
    let host = NSHostingView(rootView: ScrollFixtureView(fixture: fixture))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 200),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    func settle() {
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.1))
      host.layoutSubtreeIfNeeded()
    }
    func findScroll(_ view: NSView) -> NSScrollView? {
      if let scroll = view as? NSScrollView { return scroll }
      return view.subviews.lazy.compactMap { findScroll($0) }.first
    }
    func scroll() -> NSScrollView {
      guard let value = findScroll(host) else { fatalError("Missing native scroll view") }
      return value
    }
    settle()
    for resetID in [["new synthetic query", "0"], ["new synthetic query", "1"]] {
      let before = scroll()
      before.contentView.scroll(to: NSPoint(x: 0, y: 500))
      before.reflectScrolledClipView(before.contentView)
      settle()
      assert(before.contentView.bounds.origin.y > 100)
      fixture.refresh += 1
      settle()
      assert(scroll() === before, "Ordinary refresh must preserve viewport identity")
      assert(scroll().contentView.bounds.origin.y > 100)
      fixture.resetID = resetID
      settle()
      assert(abs(scroll().contentView.bounds.origin.y) < 1, "Query/navigation reset must return to top")
    }
    print("Native viewport resets for query/navigation; ordinary refresh preserves scroll")
  }
}
