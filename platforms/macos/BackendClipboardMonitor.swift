import AppKit

@MainActor final class MacClipboardMonitor {
  enum Status: Equatable {
    case disabled, monitoring, unavailable, saveFailed
    var message: String {
      switch self {
      case .disabled: return "剪贴板采集已停用"
      case .monitoring: return "输入法运行且历史开启时，保存新复制的文本"
      case .unavailable: return "无法读取共享设置，剪贴板采集已暂停"
      case .saveFailed: return "剪贴板历史保存失败，将重试"
      }
    }
  }
  private let capture: MacClipboardCapture
  init(source: any MacClipboardSource) { capture = MacClipboardCapture(source: source) }

  func run(interval: UInt64 = 400_000_000,
    enabled: () async throws -> Bool,
    save: (String) async throws -> Bool,
    publish: (Status) -> Void
  ) async {
    defer { _ = capture.sample(enabled: false) }
    var previous: Status?
    while !Task.isCancelled {
      let status: Status
      do {
        let allowed = try await enabled()
        guard !Task.isCancelled else { return }
        if !allowed {
          _ = capture.sample(enabled: false)
          status = .disabled
        } else if let sample = capture.sample(enabled: true) {
          do {
            let saved = try await save(sample.text)
            guard !Task.isCancelled else { return }
            if saved {
              capture.acknowledge(sample)
              status = .monitoring
            } else {
              _ = capture.sample(enabled: false)
              status = .disabled
            }
          } catch {
            status = .saveFailed
          }
        } else {
          status = .monitoring
        }
      } catch {
        _ = capture.sample(enabled: false)
        status = .unavailable
      }
      guard !Task.isCancelled else { return }
      if previous != status { publish(status); previous = status }
      do { try await Task.sleep(nanoseconds: interval) }
      catch { return }
    }
  }

  static func run(directory: String, publish: (Status) -> Void) async {
    let monitor = MacClipboardMonitor(source: MacPasteboardSource(pasteboard: .general))
    await monitor.run(enabled: {
      try await Task.detached { try MacEmojiClipboardHistory.captureEnabled(directory: directory) }.value
    }, save: { text in
      try await Task.detached { try MacEmojiClipboardHistory.capture(directory: directory, text: text) }.value
    }, publish: publish)
  }
}
