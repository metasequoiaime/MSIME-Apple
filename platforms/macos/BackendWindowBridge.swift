import AppKit
import SwiftUI

/// Objective-C entry points for native macOS controllers that need to present
/// the shared SwiftUI backend surfaces. Each window owns its hosting controller
/// and is rebuilt after closing or when the requesting account changes.
@MainActor @objc(MSIMEBackendWindowBridge)
final class BackendWindowBridge: NSObject {
  @objc static let shared = BackendWindowBridge()
  private let windows = BackendAccountWindowCache<NSWindowController>()

  func closeAll() {
    windows.closeAll { controller in
      controller.close()
      controller.window?.contentViewController = nil
    }
  }

  @objc func showDictionary(forAccountID accountID: String) { show("dictionary", accountID: accountID, title: "云词典", size: NSSize(width: 660, height: 650)) { MacCloudDictionaryView(accountID: accountID) } }
  @objc func showClipboard(forAccountID accountID: String) { show("clipboard", accountID: accountID, title: "云剪贴板", size: NSSize(width: 560, height: 560)) { MacCloudClipboardView(accountID: accountID) } }
  @objc func showSnapshot(forAccountID accountID: String) { show("snapshot", accountID: accountID, title: "词库快照", size: NSSize(width: 560, height: 460)) { MacCloudSnapshotView(accountID: accountID) } }
  @objc func showSettings(forAccountID accountID: String) { show("settings", accountID: accountID, title: "桌面设置同步", size: NSSize(width: 540, height: 520)) { MacCloudSettingsView(accountID: accountID) } }
  @objc func showCommunityResources(forAccountID accountID: String) { show("resources", accountID: accountID, title: "词包与回复模板", size: NSSize(width: 650, height: 650)) { BackendCommunityResourcesView(accountID: accountID) } }

  private func show<Content: View>(_ key: String, accountID: String, title: String, size: NSSize, @ViewBuilder content: () -> Content) {
    let controller = windows.window(for: key, accountID: accountID,
      reusable: { $0.window?.isVisible == true || $0.window?.isMiniaturized == true },
      close: { controller in
        controller.close()
        controller.window?.contentViewController = nil
      }) {
      let host = NSHostingController(rootView: content())
      let window = NSWindow(contentViewController: host)
      window.title = title; window.setContentSize(size); window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
      window.isReleasedWhenClosed = false
      let controller = NSWindowController(window: window)
      window.center()
      return controller
    }
    controller.window?.deminiaturize(nil)
    controller.showWindow(nil)
    controller.window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}
