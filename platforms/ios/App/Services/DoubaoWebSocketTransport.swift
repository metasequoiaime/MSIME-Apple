import Foundation

/// iOS host-side WebSocket lifecycle for the injected client-core voice transport.
final class DoubaoWebSocketTransport: NSObject, URLSessionWebSocketDelegate {
  enum Failure: Error { case notConnected, closed }

  private var session: URLSession?
  private var task: URLSessionWebSocketTask?
  private(set) var isConnected = false

  func start(endpoint: URL, headers: [String: String] = [:]) async throws {
    guard task == nil else { return }
    let configuration = URLSessionConfiguration.ephemeral
    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    var request = URLRequest(url: endpoint)
    request.allHTTPHeaderFields = headers
    let task = session.webSocketTask(with: request)
    self.session = session
    self.task = task
    task.resume()
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      task.sendPing { error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      }
    }
    isConnected = true
  }

  func send(binary frame: Data) async throws {
    guard let task, isConnected else { throw Failure.notConnected }
    try await task.send(.data(frame))
  }

  func receive() async throws -> Data {
    guard let task, isConnected else { throw Failure.notConnected }
    switch try await task.receive() {
    case .data(let frame): return frame
    case .string: throw Failure.closed
    @unknown default: throw Failure.closed
    }
  }

  func finish() {
    task?.cancel(with: .normalClosure, reason: nil)
    task = nil
    session?.invalidateAndCancel()
    session = nil
    isConnected = false
  }

  func cancel() {
    task?.cancel(with: .goingAway, reason: nil)
    task = nil
    session?.invalidateAndCancel()
    session = nil
    isConnected = false
  }

  func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                  didOpenWithProtocol protocol: String?) {
    isConnected = true
  }

  func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                  didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
    isConnected = false
  }
}
