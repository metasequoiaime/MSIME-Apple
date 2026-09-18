import Foundation

private actor HistoryFixture {
  var reads = 0
  func read() throws -> MacEmojiClipboardHistory {
    reads += 1
    switch reads {
    case 1, 2: return .init(enabled: true, entries: ["synthetic alpha"])
    case 3: return .init(enabled: true, entries: ["synthetic beta", "synthetic alpha"])
    case 4: return .init(enabled: false, entries: [])
    case 5: throw NSError(domain: "SyntheticHistory", code: 1)
    default: return .init(enabled: true, entries: ["synthetic recovery"])
    }
  }
}

private actor PendingRead {
  var continuation: CheckedContinuation<MacEmojiClipboardHistory, Never>?
  var started: Bool { continuation != nil }
  func read() async -> MacEmojiClipboardHistory {
    await withCheckedContinuation { continuation = $0 }
  }
  func finish() {
    continuation?.resume(returning: .init(enabled: true, entries: ["synthetic late result"]))
    continuation = nil
  }
}

@main enum EmojiClipboardObservationTest {
  @MainActor static func main() async throws {
    let fixture = HistoryFixture()
    var updates: [MacEmojiClipboardHistory?] = []
    let observer = Task {
      await MacEmojiClipboardHistory.observe(interval: 1_000_000, read: {
        try await fixture.read()
      }, publish: { updates.append($0) })
    }
    for _ in 0..<1000 {
      if updates.count >= 5 { break }
      try await Task.sleep(nanoseconds: 1_000_000)
    }
    observer.cancel()
    await observer.value
    precondition(updates.count == 5)
    precondition(updates[0]?.entries == ["synthetic alpha"])
    precondition(updates[1]?.entries == ["synthetic beta", "synthetic alpha"])
    precondition(updates[2]?.enabled == false && updates[2]?.entries == [])
    precondition(updates[3] == nil)
    precondition(updates[4]?.entries == ["synthetic recovery"])
    let stoppedReads = await fixture.reads
    try await Task.sleep(nanoseconds: 5_000_000)
    let afterStop = await fixture.reads
    precondition(stoppedReads == afterStop)

    let pending = PendingRead()
    var latePublications = 0
    let cancelled = Task {
      await MacEmojiClipboardHistory.observe(read: { await pending.read() }, publish: { _ in latePublications += 1 })
    }
    for _ in 0..<1000 {
      if await pending.started { break }
      try await Task.sleep(nanoseconds: 1_000_000)
    }
    let started = await pending.started
    precondition(started)
    cancelled.cancel()
    await pending.finish()
    await cancelled.value
    precondition(latePublications == 0)
    print("History live updates, deduplication, disable, recovery and cancellation checks passed")
  }
}
