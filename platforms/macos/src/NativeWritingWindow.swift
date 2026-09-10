import AppKit
import SwiftUI

@MainActor
final class MacWritingContext {
  let text: String
  private let check: @convention(block) () -> Bool
  private let restore: @convention(block) () -> Void
  private let replace: @convention(block) (NSString, NSString) -> Bool
  private let invalidate: @convention(block) () -> Void
  init(_ parameters: NSDictionary) {
    text = parameters["text"] as? String ?? ""
    // Private in-process bridge: these blocks are created by the IMK controller.
    check = unsafeBitCast(parameters["validate"] as AnyObject, to: (@convention(block) () -> Bool).self)
    restore = unsafeBitCast(parameters["restore"] as AnyObject, to: (@convention(block) () -> Void).self)
    replace = unsafeBitCast(parameters["apply"] as AnyObject, to: (@convention(block) (NSString, NSString) -> Bool).self)
    invalidate = unsafeBitCast(parameters["cancel"] as AnyObject, to: (@convention(block) () -> Void).self)
  }
  var valid: Bool { check() }
  func cancel() { invalidate() }
  func apply(_ text: String, task: WritingTask, authorize: @MainActor () async throws -> Void = {}) async -> Bool {
    guard !Task.isCancelled, valid else { return false }
    restore()
    // Activation is asynchronous. Wait for IMK to reactivate the original client;
    // the native callback rechecks foreground app, selection and one-shot validity.
    for _ in 0..<20 {
      do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return false }
      guard !Task.isCancelled, valid else { return false }
      // Account/template/provider changes may arrive while activation is pending.
      do { try await authorize() } catch { return false }
      guard !Task.isCancelled, valid else { return false }
      if replace(text as NSString, task.rawValue as NSString) { return true }
    }
    return false
  }
}

private struct NativeWritingEntry: View {
  let context: MacWritingContext?
  let close: () -> Void
  @State private var accountID: String?
  @State private var status = "正在读取账户…"
  var body: some View {
    Group {
      if let accountID { MacWritingView(accountID: accountID, context: context, close: close) }
      else {
        VStack(spacing: 16) {
          Text(status)
          Button("打开账户登录") { BackendAccountWindow.shared.showAccount() }
          Button("关闭", action: close)
        }.padding(30).frame(minWidth: 420, minHeight: 160)
      }
    }.task {
      do {
        let user = try await BackendAccountSession.shared.user()
        try Task.checkCancellation()
        accountID = user?.id ?? ""
      } catch { if !Task.isCancelled { accountID = "" } }
    }
  }
}

@objc(MSIMEMacWriting)
@MainActor
final class NativeWritingWindow: NSWindowController, NSWindowDelegate {
  private static var current: NativeWritingWindow?
  private let context: MacWritingContext?
  @objc(show:) static func show(_ parameters: NSDictionary) {
    current?.close()
    let controller = NativeWritingWindow(context: MacWritingContext(parameters))
    current = controller
    controller.showWindow(nil)
    controller.window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  static func showWithoutSelection() {
    current?.close()
    let controller = NativeWritingWindow(context: nil)
    current = controller
    controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  private init(context: MacWritingContext?) {
    self.context = context
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 600),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    super.init(window: window)
    window.title = context == nil ? "AI 写作助手" : "润色选中文字"; window.isReleasedWhenClosed = false; window.delegate = self
    window.contentView = NSHostingView(rootView: NativeWritingEntry(context: context, close: { [weak self] in self?.close() }))
    window.center()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func windowWillClose(_ notification: Notification) {
    context?.cancel(); window?.contentView = nil
    if Self.current === self { Self.current = nil }
  }
}

@_cdecl("MSIMEShowWritingServices")
func showWritingServices() { Task { @MainActor in NativeWritingWindow.showWithoutSelection() } }
