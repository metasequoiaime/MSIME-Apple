// The macOS 26 SDK is the first with SpeechAnalyzer, and Swift 6.2 is the first compiler that ships with it. An older toolchain builds MSIMEBackend without this file's classes, and VoiceInputService stays on SFSpeechRecognizer.
#if compiler(>=6.2)
import AVFoundation
import Foundation
import Speech

// Entry point for VoiceInputService.mm through BackendSpeechAnalyzer.h. The class itself is available everywhere so the lookup by name always succeeds; it hands out sessions only on macOS 26 and later, and only for a locale whose on-device model is already installed. The first request for any other locale starts the check and installation in the background and returns nil, so that one dictation goes through SFSpeechRecognizer instead of waiting on a download.
@objc(MSIMEBackendSpeechAnalyzer)
final class BackendSpeechAnalyzer: NSObject {
  private struct Prepared {
    let locale: Locale
    let format: AVAudioFormat
  }

  private static let lock = NSLock()
  nonisolated(unsafe) private static var prepared: [String: Prepared] = [:]
  nonisolated(unsafe) private static var preparing: Set<String> = []
  // Locales the transcriber does not support at all. Asking again cannot change the answer until the system updates, which restarts this process anyway.
  nonisolated(unsafe) private static var unsupported: Set<String> = []

  @objc(sessionWithLocale:textHandler:)
  static func session(locale identifier: String, textHandler: @escaping (String, Bool) -> Void) -> NSObject? {
    guard #available(macOS 26, *), SpeechTranscriber.isAvailable else { return nil }
    let (ready, start): (Prepared?, Bool) = lock.withLock {
      if let ready = prepared[identifier] { return (ready, false) }
      if unsupported.contains(identifier) { return (nil, false) }
      return (nil, preparing.insert(identifier).inserted)
    }
    if let ready {
      return BackendSpeechAnalyzerSession(locale: ready.locale, format: ready.format, handler: textHandler)
    }
    if start { Task.detached(priority: .utility) { await prepare(identifier) } }
    return nil
  }

  @available(macOS 26, *)
  private static func prepare(_ identifier: String) async {
    defer { lock.withLock { _ = preparing.remove(identifier) } }
    guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier)) else {
      lock.withLock { _ = unsupported.insert(identifier) }
      return
    }
    let transcriber = BackendSpeechAnalyzerSession.makeTranscriber(locale)
    do {
      if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
        try await request.downloadAndInstall()
      }
    } catch {
      // No network or no room for the model: the next dictation asks again.
      return
    }
    guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { return }
    lock.withLock { prepared[identifier] = Prepared(locale: locale, format: format) }
  }
}

// One dictation. Audio arrives on the capture thread, is converted to the analyzer's format there and queued; results are assembled into the whole text so far - the finalized part plus the latest volatile guess for what follows it - and handed to main.
@available(macOS 26, *)
@objc(MSIMEBackendSpeechAnalyzerSession)
final class BackendSpeechAnalyzerSession: NSObject {
  private let analyzer: SpeechAnalyzer
  private let format: AVAudioFormat
  private let input: AsyncStream<AnalyzerInput>.Continuation
  private var converter: AVAudioConverter?  // capture thread only
  private var handler: ((String, Bool) -> Void)?  // main only

  static func makeTranscriber(_ locale: Locale) -> SpeechTranscriber {
    SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
  }

  init(locale: Locale, format: AVAudioFormat, handler: @escaping (String, Bool) -> Void) {
    let transcriber = Self.makeTranscriber(locale)
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    let (stream, input) = AsyncStream.makeStream(of: AnalyzerInput.self)
    self.analyzer = analyzer
    self.format = format
    self.input = input
    self.handler = handler
    super.init()
    // Subscribed before the analyzer starts, so no result can come out ahead of the reader.
    Task { [weak self] in
      var finalized = ""
      var volatile = ""
      do {
        for try await result in transcriber.results {
          let text = String(result.text.characters)
          if result.isFinal {
            finalized += text
            volatile = ""
          } else {
            volatile = text
          }
          self?.deliver(finalized + volatile, final: false)
        }
        self?.deliver(finalized, final: true)
      } catch {
        self?.deliver("", final: true)
      }
    }
    Task { [weak self] in
      do {
        try await analyzer.start(inputSequence: stream)
      } catch {
        self?.deliver("", final: true)
      }
    }
  }

  deinit {
    input.finish()
    let analyzer = analyzer
    Task { await analyzer.cancelAndFinishNow() }
  }

  private func deliver(_ text: String, final: Bool) {
    DispatchQueue.main.async { [weak self] in
      guard let self, let handler = self.handler else { return }
      if final { self.handler = nil }
      handler(text, final)
    }
  }

  @objc(appendBuffer:)
  func append(_ buffer: AVAudioPCMBuffer) {
    guard let converted = convert(buffer) else { return }
    input.yield(AnalyzerInput(buffer: converted))
  }

  @objc func finishAudio() {
    input.finish()
    let analyzer = analyzer
    Task { [weak self] in
      do {
        try await analyzer.finalizeAndFinishThroughEndOfInput()
      } catch {
        self?.deliver("", final: true)
      }
    }
  }

  @objc func cancel() {
    handler = nil
    input.finish()
    let analyzer = analyzer
    Task { await analyzer.cancelAndFinishNow() }
  }

  // Always a fresh buffer: the tap reuses its own once the callback returns, and the analyzer reads this one later. The converter persists for the session so resampling carries over between buffers.
  private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    if converter == nil || converter?.inputFormat != buffer.format {
      converter = AVAudioConverter(from: buffer.format, to: format)
    }
    guard let converter, buffer.frameLength > 0 else { return nil }
    let ratio = format.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
    guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
    var consumed = false
    var error: NSError?
    let status = converter.convert(to: output, error: &error) { _, inputStatus in
      if consumed {
        inputStatus.pointee = .noDataNow
        return nil
      }
      consumed = true
      inputStatus.pointee = .haveData
      return buffer
    }
    guard status != .error, output.frameLength > 0 else { return nil }
    return output
  }
}
#endif
