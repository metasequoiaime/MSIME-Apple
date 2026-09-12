import AVFoundation
import Foundation

@MainActor
final class VoiceRecorder: ObservableObject {
  @Published private(set) var isRecording = false
  @Published private(set) var isPreparing = false
  @Published private(set) var audio: Data?
  private var recorder: AVAudioRecorder?
  private var file: URL?
  private var limit: Task<Void, Never>?

  func start() async throws {
    guard !isPreparing && !isRecording else { return }
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
      isRecording = true
      limit = Task { [weak self] in
        do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
        self?.stop()
      }
    } catch {
      discard()
      throw error
    }
  }

  func stop() {
    limit?.cancel()
    limit = nil
    recorder?.stop()
    recorder = nil
    isRecording = false
    if let file {
      audio = try? Data(contentsOf: file)
      try? FileManager.default.removeItem(at: file)
    }
    file = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  func discard() {
    stop()
    audio = nil
  }
}
