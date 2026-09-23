import AVFoundation
import Foundation

@MainActor
final class VoiceRecorder: ObservableObject {
  @Published private(set) var isRecording = false
  @Published private(set) var isPreparing = false
  @Published private(set) var audio: Data?
  var pcmAudio: Data? { audio.flatMap { WAVPCMExtractor.extract(from: $0) } }
  private var recorder: AVAudioRecorder?
  private var file: URL?
  private var limit: Task<Void, Never>?
  /// A live recording: the engine capturing it, where its PCM goes out, and everything captured so far.
  private var engine: AVAudioEngine?
  private var live: AsyncStream<Data>.Continuation?
  private var capture: LiveCapture?

  func start() async throws {
    guard try await prepare() else { return }
    do {
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
      file = url
      let recorder = try AVAudioRecorder(url: url, settings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
      ])
      self.recorder = recorder
      guard recorder.record() else { throw ServiceFailure(message: "无法开始录音，请重试。") }
      began()
    } catch {
      discard()
      throw error
    }
  }

  /// Records through the audio engine and hands out 16 kHz mono PCM16 as it is captured, for a service that recognizes while the user speaks. The stream finishes when recording stops, and `audio` then holds the whole recording, so it can still be sent the ordinary way if the live request failed.
  func startStreaming() async throws -> AsyncStream<Data>? {
    guard try await prepare() else { return nil }
    let (stream, continuation) = AsyncStream<Data>.makeStream()
    do {
      let engine = AVAudioEngine()
      let input = engine.inputNode
      let source = input.outputFormat(forBus: 0)
      guard source.sampleRate > 0,
            let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true),
            let converter = AVAudioConverter(from: source, to: target)
      else { throw ServiceFailure(message: "无法开始录音，请重试。") }
      let capture = LiveCapture()
      input.installTap(onBus: 0, bufferSize: 4096, format: source,
                       block: Self.tap(converter: converter, target: target, capture: capture, continuation: continuation))
      engine.prepare()
      try engine.start()
      self.engine = engine
      self.capture = capture
      live = continuation
      began()
      return stream
    } catch {
      continuation.finish()
      discard()
      throw error
    }
  }

  private func prepare() async throws -> Bool {
    guard !isPreparing && !isRecording else { return false }
    isPreparing = true
    defer { isPreparing = false }
    let session = AVAudioSession.sharedInstance()
    let allowed = await withCheckedContinuation { continuation in
      session.requestRecordPermission { continuation.resume(returning: $0) }
    }
    try Task.checkCancellation()
    guard allowed else { throw ServiceFailure(message: "请在系统设置中允许水杉使用麦克风。") }
    discard()
    do {
      try session.setCategory(.record, mode: .default)
      try session.setActive(true)
    } catch {
      discard()
      throw error
    }
    return true
  }

  private func began() {
    isRecording = true
    limit = Task { [weak self] in
      do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
      self?.stop()
    }
  }

  /// The engine's tap runs on the audio thread, so it is built outside the main actor and only touches the lock-guarded capture and the stream.
  private nonisolated static func tap(converter: AVAudioConverter, target: AVAudioFormat, capture: LiveCapture,
                                      continuation: AsyncStream<Data>.Continuation) -> AVAudioNodeTapBlock {
    { buffer, _ in
      let ratio = target.sampleRate / buffer.format.sampleRate
      guard let converted = AVAudioPCMBuffer(pcmFormat: target,
                                             frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1)
      else { return }
      var supplied = false
      var error: NSError?
      converter.convert(to: converted, error: &error) { _, status in
        if supplied { status.pointee = .noDataNow; return nil }
        supplied = true
        status.pointee = .haveData
        return buffer
      }
      guard error == nil, converted.frameLength > 0, let samples = converted.int16ChannelData else { return }
      let pcm = Data(bytes: samples[0], count: Int(converted.frameLength) * MemoryLayout<Int16>.size)
      guard capture.append(pcm) else { return }
      continuation.yield(pcm)
    }
  }

  func stop() {
    limit?.cancel()
    limit = nil
    recorder?.stop()
    recorder = nil
    if let engine {
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
      self.engine = nil
    }
    live?.finish()
    live = nil
    isRecording = false
    if let file {
      audio = try? Data(contentsOf: file)
      try? FileManager.default.removeItem(at: file)
    }
    file = nil
    if let capture {
      audio = CustomServiceClient.silentWAV(capture.finish())
      self.capture = nil
    }
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  func discard() {
    stop()
    audio = nil
  }
}

/// The PCM a live recording has captured, written from the audio thread and read once when it stops.
private final class LiveCapture: @unchecked Sendable {
  /// 60 seconds of 16 kHz PCM16, the same bound as the file recording.
  private static let limit = 60 * 32_000
  private let lock = NSLock()
  private var pcm = Data()
  private var finished = false

  /// False once the recording has stopped or reached the limit, so nothing more goes out.
  func append(_ chunk: Data) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !finished, pcm.count + chunk.count <= Self.limit else { return false }
    pcm.append(chunk)
    return true
  }

  func finish() -> Data {
    lock.lock()
    defer { lock.unlock() }
    finished = true
    return pcm
  }
}
