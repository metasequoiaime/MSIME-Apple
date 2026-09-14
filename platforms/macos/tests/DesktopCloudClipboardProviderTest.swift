import Foundation

@MainActor final class SyntheticClipboardAPI: DesktopCloudClipboardAPI {
  var calls = 0
  var uploaded = ""
  func clipboard(token: String, search: String) async throws -> BackendAccountClient.ClipboardPage {
    calls += 1
    return .init(enabled: true, items: [.init(id: String(repeating: "a", count: 64), text: "synthetic\n\t合成", updated_at: "synthetic-time")])
  }
  func addClipboard(_ text: String, token: String) async throws -> BackendAccountClient.ClipboardItem {
    calls += 1; uploaded = text
    return .init(id: String(repeating: "a", count: 64), text: text, updated_at: "synthetic-time")
  }
  func deleteClipboard(id: String?, token: String) async throws { calls += 1; assert(id?.count == 64) }
  func setClipboardEnabled(_ enabled: Bool, token: String) async throws { calls += 1; assert(!enabled) }
}

@main enum DesktopCloudClipboardProviderTest {
  @MainActor static func main() async throws {
    let api = SyntheticClipboardAPI()
    let provider = BackendCloudClipboardProvider(client: api, credentials: { "synthetic-token" })
    let page = try await provider.execute(["operation":"list", "search":"合成"])
    assert((page["items"] as? [[String: Any]])?.count == 1)
    let text = String(repeating: "界", count: 3997) + "\n\r\t"
    _ = try await provider.execute(["operation":"add", "text":text])
    assert(api.uploaded == text)
    _ = try await provider.execute(["operation":"delete", "id":String(repeating: "a", count: 64)])
    _ = try await provider.execute(["operation":"set_enabled", "enabled":false])
    assert(api.calls == 4)
    for request: NSDictionary in [
      ["operation":"add", "text":String(repeating: "界", count: 4001)],
      ["operation":"add", "text":"synthetic\0"], ["operation":"list", "search":"bad\n"],
      ["operation":"delete", "id":"bad/id"], ["operation":"set_enabled", "enabled":1],
      ["operation":"token"],
    ] {
      do { _ = try await provider.execute(request); assertionFailure("invalid action accepted") } catch { }
    }
    assert(api.calls == 4)
    var identities = 0
    let changed = BackendCloudClipboardProvider(client: api, credentials: {
      identities += 1
      if identities > 1 { throw CancellationError() }
      return "synthetic-token"
    })
    do { _ = try await changed.execute(["operation":"list"]); assertionFailure("old account data exposed") } catch { }
    let before = api.calls
    let missing = BackendCloudClipboardProvider(client: api, credentials: { throw CancellationError() })
    do { _ = try await missing.execute(["operation":"add", "text":"synthetic"]); assertionFailure("signed-out mutation") } catch { }
    assert(api.calls == before)
    let response: NSDictionary = await withCheckedContinuation { continuation in
      let progress = provider.request(["operation":"add", "text":"synthetic"], completion: { continuation.resume(returning: $0) })
      progress.cancel()
    }
    assert(response["ok"] as? Bool == false && api.calls == before)
    assert(response["error"] as? String == "unavailable")
  }
}
