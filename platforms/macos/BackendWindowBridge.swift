import AppKit
import SwiftUI

/// Objective-C entry points for native macOS controllers that need to present
/// the shared SwiftUI backend surfaces. Each window owns its hosting controller
/// and is rebuilt after closing or when the requesting account changes.
@MainActor @objc(MSIMEBackendWindowBridge)
final class BackendWindowBridge: NSObject {
  @objc static let shared = BackendWindowBridge()
  private let windows = BackendAccountWindowCache<NSWindowController>()
  private let emojiDeliveryNotice = MacEmojiDeliveryNotice()

  @objc func showEmojiDeliveryFailure() { emojiDeliveryNotice.show() }

  @objc func applyEmojiPreferences(_ preferences: NSDictionary) { MacEmojiAppearance.shared.apply(preferences) }

  func closeAll() {
    emojiDeliveryNotice.dismiss()
    windows.closeAll { controller in
      controller.close()
      controller.window?.contentViewController = nil
    }
  }

  @objc func showDictionary(forAccountID accountID: String) { show("dictionary", accountID: accountID, title: "云词典", size: NSSize(width: 660, height: 650)) { MacCloudDictionaryView(accountID: accountID) } }
  @objc func showClipboard(forAccountID accountID: String) { show("clipboard", accountID: accountID, title: "云剪贴板", size: NSSize(width: 560, height: 560)) { MacCloudClipboardView(accountID: accountID) } }
  @objc func showSnapshot(forAccountID accountID: String) { show("snapshot", accountID: accountID, title: "词库快照", size: NSSize(width: 560, height: 460)) { MacCloudSnapshotView(accountID: accountID) } }
  @objc func showSettings(forAccountID accountID: String) { show("settings", accountID: accountID, title: "桌面设置同步", size: NSSize(width: 540, height: 520)) { MacCloudSettingsView(accountID: accountID) } }
  @objc func showHandwriting() { show("handwriting", accountID: "local", title: "手写输入", size: NSSize(width: 560, height: 360)) { MacHandwritingToolView() } }
  @objc func showEmoji(withOptions options: NSDictionary, selectionAttempt selection: @escaping (String) -> Bool) {
    weak var presented: NSWindowController?
    // Each presentation binds a new target; never reuse an older selection closure.
    presented = show("emoji", accountID: UUID().uuidString, title: "表情与符号", size: NSSize(width: 420, height: 560)) {
      MacEmojiView(resources: options["resources"] as? String ?? "", preferencesDirectory: options["preferences_directory"] as? String ?? "", onSelect: { text in
        let accepted = selection(text)
        if accepted { presented?.close() }
        return accepted
      })
    }
  }
  @objc func showCommunityResources(forAccountID accountID: String) { show("resources", accountID: accountID, title: "词包与回复模板", size: NSSize(width: 650, height: 650)) { BackendCommunityResourcesView(accountID: accountID) } }

  @discardableResult private func show<Content: View>(_ key: String, accountID: String, title: String, size: NSSize, @ViewBuilder content: () -> Content) -> NSWindowController {
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
    return controller
  }
}
