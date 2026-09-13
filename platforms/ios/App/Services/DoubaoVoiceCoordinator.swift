import Foundation

/// Coordinates a host transport with generation-checked voice text application.
final class DoubaoVoiceCoordinator {
  typealias ApplyText = (_ text: String, _ generation: UInt64) -> Void
  typealias DecodeFrame = (_ frame: Data) -> (isFinal: Bool, text: String?)?

  private let transport: DoubaoWebSocketTransport
  private let applyText: ApplyText
  private let decodeFrame: DecodeFrame

  init(transport: DoubaoWebSocketTransport, applyText: @escaping ApplyText,
       decodeFrame: @escaping DecodeFrame) {
    self.transport = transport
    self.applyText = applyText
    self.decodeFrame = decodeFrame
  }

  func run(endpoint: URL, generation: UInt64, audioFrames: [Data]) async throws {
    try await transport.start(endpoint: endpoint)
    defer { transport.finish() }
    for frame in audioFrames { try await transport.send(binary: frame) }
    while true {
      guard let response = decodeFrame(try await transport.receive()) else { continue }
      if let text = response.text, !text.isEmpty { applyText(text, generation) }
      if response.isFinal { return }
    }
  }
}
