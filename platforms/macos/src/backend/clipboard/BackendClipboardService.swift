import Foundation
import Combine

/// One monitor per input-method process; windows only observe its status.
@MainActor final class MacClipboardService: ObservableObject {
  static let shared = MacClipboardService()
  @Published private(set) var status: MacClipboardMonitor.Status?
  private var task: Task<Void, Never>?
  private var directory: String?
  private var generation: UInt64 = 0
  private let run: (String, @escaping (MacClipboardMonitor.Status) -> Void) async -> Void

  init(run: @escaping (String, @escaping (MacClipboardMonitor.Status) -> Void) async -> Void = {
    directory, publish in await MacClipboardMonitor.run(directory: directory, publish: publish)
  }) { self.run = run }

  func start(directory: String) {
    guard NSString(string: directory).isAbsolutePath else { stop(); status = .unavailable; return }
    guard self.directory != directory || task == nil else { return }
    let previous = task
    previous?.cancel()
    generation &+= 1
    let token = generation
    self.directory = directory
    status = nil
    task = Task { [self] in
      // Drain a cancelled read/write before starting another monitor.
      await previous?.value
      guard !Task.isCancelled else { return }
      await run(directory) { [weak self] status in
        guard let self, self.generation == token else { return }
        self.status = status
      }
      if generation == token { task = nil }
    }
  }

  func stop() {
    generation &+= 1
    task?.cancel()
    // Retain the draining task so a subsequent start must wait for it.
    directory = nil
    status = .disabled
  }
}
