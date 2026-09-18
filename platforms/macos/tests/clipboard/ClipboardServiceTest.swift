import Foundation

@MainActor private final class ServiceFixture {
  var started: [String] = []
  var pending: [String: CheckedContinuation<Void, Never>] = [:]
  var publish: [String: (MacClipboardMonitor.Status) -> Void] = [:]
  var active = 0
  var maximum = 0
  func run(_ directory: String, _ callback: @escaping (MacClipboardMonitor.Status) -> Void) async {
    started.append(directory)
    active += 1
    maximum = max(maximum, active)
    publish[directory] = callback
    callback(.monitoring)
    await withCheckedContinuation { pending[directory] = $0 }
    active -= 1
  }
  func finish(_ directory: String) { pending.removeValue(forKey: directory)?.resume() }
}

@main enum ClipboardServiceTest {
  @MainActor static func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<1000 {
      if condition() { return }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
    preconditionFailure("synthetic service did not reach expected state")
  }
  @MainActor static func main() async {
    let fixture = ServiceFixture()
    let service = MacClipboardService(run: { await fixture.run($0, $1) })
    service.start(directory: "/synthetic-a")
    await waitUntil { fixture.started.count == 1 }
    service.start(directory: "/synthetic-a")
    assert(fixture.started.count == 1 && service.status == .monitoring)
    service.start(directory: "/synthetic-b")
    fixture.publish["/synthetic-a"]?(.saveFailed)
    assert(service.status == nil)
    await Task.yield()
    assert(fixture.started.count == 1)
    fixture.finish("/synthetic-a")
    await waitUntil { fixture.started.count == 2 }
    service.stop()
    fixture.publish["/synthetic-b"]?(.monitoring)
    assert(service.status == .disabled)
    service.start(directory: "/synthetic-c")
    service.start(directory: "/synthetic-d")
    fixture.finish("/synthetic-b")
    await waitUntil { fixture.started.count == 3 }
    assert(fixture.started == ["/synthetic-a", "/synthetic-b", "/synthetic-d"])
    assert(fixture.maximum == 1)
    service.start(directory: "relative")
    assert(service.status == .unavailable)
    fixture.publish["/synthetic-d"]?(.monitoring)
    assert(service.status == .unavailable)
    fixture.finish("/synthetic-d")
    await waitUntil { fixture.active == 0 }
    print("Clipboard service deduplication, serialized restart, stop and stale status tests passed")
  }
}
