import AppKit
import SwiftUI

/// Objective-C entry points for native macOS controllers that need to present
/// the shared SwiftUI backend surfaces. Each window owns its hosting controller
/// and is replaced only when the caller explicitly asks for another surface.
@MainActor @objc(MSIMEBackendWindowBridge)
final class BackendWindowBridge: NSObject {
  @objc static let shared = BackendWindowBridge()
  private var windows: [String: NSWindowController] = [:]

  @objc func showDictionary(forAccountID accountID: String) { show("dictionary", accountID: accountID, title: "云词典", size: NSSize(width: 660, height: 650)) { MacCloudDictionaryView(accountID: accountID) } }
  @objc func showClipboard(forAccountID accountID: String) { show("clipboard", accountID: accountID, title: "云剪贴板", size: NSSize(width: 560, height: 560)) { MacCloudClipboardView(accountID: accountID) } }
  @objc func showSnapshot(forAccountID accountID: String) { show("snapshot", accountID: accountID, title: "词库快照", size: NSSize(width: 560, height: 460)) { MacCloudSnapshotView(accountID: accountID) } }
  @objc func showSettings(forAccountID accountID: String) { show("settings", accountID: accountID, title: "桌面设置同步", size: NSSize(width: 540, height: 520)) { MacCloudSettingsView(accountID: accountID) } }

  private func show<Content: View>(_ key: String, accountID: String, title: String, size: NSSize, @ViewBuilder content: () -> Content) {
    if let existing = windows[key] { existing.showWindow(nil); existing.window?.makeKeyAndOrderFront(nil); return }
    let host = NSHostingController(rootView: content())
    let window = NSWindow(contentViewController: host)
    window.title = title; window.setContentSize(size); window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.isReleasedWhenClosed = false
    let controller = NSWindowController(window: window)
    windows[key] = controller
    controller.showWindow(nil); window.center(); NSApp.activate(ignoringOtherApps: true)
  }
}
