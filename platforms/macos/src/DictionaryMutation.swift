import Foundation

@MainActor
enum MacDictionaryMutation {
  // A busy writer sends a native wake-up hint to other IME processes. Yield to
  // their main loops, then retry under the same exclusive lease and receipt ID.
  // An acknowledgement cannot establish safety: only the lease may allow a write.
  static func perform<T>(_ operation: () async throws -> T) async throws -> T {
    for attempt in 0...3 {
      try Task.checkCancellation()
      do { return try await operation() }
      catch {
        let failure = error as NSError
        guard attempt < 3, failure.domain == "app.msime.snapshot", failure.code == 423,
              failure.userInfo["retryableDictionaryBusy"] as? Bool == true else { throw error }
        try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 150_000_000)
      }
    }
    throw CancellationError()
  }
}
