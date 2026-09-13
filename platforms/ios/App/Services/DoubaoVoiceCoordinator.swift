import Foundation

/// Coordinates a host transport with generation-checked voice text application.
final class DoubaoVoiceCoordinator {
  static let pcmChunkBytes = 6400
  typealias ApplyText = (_ text: String, _ generation: UInt64) -> Void
  typealias DecodeFrame = (_ frame: Data) -> (isFinal: Bool, text: String?)?
  typealias AudioFrameBuilder = (_ sequence: Int32, _ pcm: Data, _ final: Bool) -> Data

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
    try await receiveAndApply(generation: generation, audioFrames: audioFrames)
  }

  func run(endpoint: URL, handshake: DoubaoHandshake, generation: UInt64,
           audioFrames: [Data]) async throws {
    try await transport.start(endpoint: endpoint, handshake: handshake)
    try await receiveAndApply(generation: generation, audioFrames: audioFrames)
  }

  /// Send one complete PCM recording using the Windows 200 ms packet cadence.
  /// The caller supplies the start frame and the platform bridge's frame builder.
  func run(endpoint: URL, handshake: DoubaoHandshake, generation: UInt64,
           startFrame: Data, pcm: Data, buildAudioFrame: @escaping AudioFrameBuilder) async throws {
    try await transport.start(endpoint: endpoint, handshake: handshake)
    defer { transport.finish() }
    try await transport.send(binary: startFrame)
    var pending = pcm
    var sequence: Int32 = 2
    while pending.count > Self.pcmChunkBytes {
      try await transport.send(binary: buildAudioFrame(sequence, pending.prefix(Self.pcmChunkBytes), false))
      pending.removeFirst(Self.pcmChunkBytes)
      sequence += 1
    }
    try await transport.send(binary: buildAudioFrame(-sequence, pending, true))
    try await receiveUntilFinal(generation: generation)
  }

  private func receiveAndApply(generation: UInt64, audioFrames: [Data]) async throws {
    defer { transport.finish() }
    for frame in audioFrames { try await transport.send(binary: frame) }
    try await receiveUntilFinal(generation: generation)
  }

  private func receiveUntilFinal(generation: UInt64) async throws {
    while true {
      guard let response = decodeFrame(try await transport.receive()) else { continue }
      if let text = response.text, !text.isEmpty { applyText(text, generation) }
      if response.isFinal { return }
    }
  }
}
