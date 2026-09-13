import Foundation

protocol DoubaoVoiceTransport: AnyObject {
  func start(endpoint: URL) async throws
  func start(endpoint: URL, handshake: DoubaoHandshake) async throws
  func send(binary frame: Data) async throws
  func receive() async throws -> Data
  func finish()
}

/// Coordinates a host transport with generation-checked voice text application.
final class DoubaoVoiceCoordinator {
  static let pcmChunkBytes = 6400
  typealias ApplyText = (_ text: String, _ generation: UInt64) -> Void
  typealias DecodeFrame = (_ frame: Data) -> (isFinal: Bool, text: String?)?
  typealias AudioFrameBuilder = (_ sequence: Int32, _ pcm: Data, _ final: Bool) -> Data

  struct FrameCodec {
    let startFrame: () throws -> Data
    let audioFrame: (_ sequence: Int32, _ pcm: Data, _ final: Bool) throws -> Data
    let decodeFrame: DecodeFrame

    init(startFrame: @escaping () throws -> Data,
         audioFrame: @escaping (_ sequence: Int32, _ pcm: Data, _ final: Bool) throws -> Data,
         decodeFrame: @escaping DecodeFrame) {
      self.startFrame = startFrame
      self.audioFrame = audioFrame
      self.decodeFrame = decodeFrame
    }
  }

  private let transport: DoubaoVoiceTransport
  private let applyText: ApplyText
  private let decodeFrame: DecodeFrame

  init(transport: DoubaoVoiceTransport, applyText: @escaping ApplyText,
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
    try await sendAudio(pcm: pcm, buildAudioFrame: buildAudioFrame)
    try await receiveUntilFinal(generation: generation)
  }

  /// Runs a complete PCM recording using a host-injected codec. The codec is
  /// normally backed by `MSIMEClientSession` and therefore keeps wire layout
  /// ownership in client-core instead of duplicating it in Swift.
  func run(endpoint: URL, handshake: DoubaoHandshake, generation: UInt64,
           pcm: Data, codec: FrameCodec) async throws {
    try await transport.start(endpoint: endpoint, handshake: handshake)
    defer { transport.finish() }
    try await transport.send(binary: codec.startFrame())
    try await sendAudio(pcm: pcm) { sequence, chunk, final in
      try codec.audioFrame(sequence, chunk, final)
    }
    try await receiveUntilFinal(generation: generation, decode: codec.decodeFrame)
  }

  private func receiveAndApply(generation: UInt64, audioFrames: [Data]) async throws {
    defer { transport.finish() }
    for frame in audioFrames { try await transport.send(binary: frame) }
    try await receiveUntilFinal(generation: generation)
  }

  private func sendAudio(pcm: Data, buildAudioFrame: (_ sequence: Int32, _ pcm: Data, _ final: Bool) throws -> Data) async throws {
    var pending = pcm
    var sequence: Int32 = 2
    while pending.count > Self.pcmChunkBytes {
      try await transport.send(binary: try buildAudioFrame(sequence, pending.prefix(Self.pcmChunkBytes), false))
      pending.removeFirst(Self.pcmChunkBytes)
      sequence += 1
    }
    try await transport.send(binary: try buildAudioFrame(-sequence, pending, true))
  }

  private func receiveUntilFinal(generation: UInt64) async throws {
    try await receiveUntilFinal(generation: generation, decode: decodeFrame)
  }

  private func receiveUntilFinal(generation: UInt64, decode: @escaping DecodeFrame) async throws {
    while true {
      guard let response = decode(try await transport.receive()) else { continue }
      if let text = response.text, !text.isEmpty { applyText(text, generation) }
      if response.isFinal { return }
    }
  }
}
