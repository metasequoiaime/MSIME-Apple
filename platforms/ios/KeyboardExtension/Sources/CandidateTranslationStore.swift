import Foundation

protocol CandidateTranslationService: Sendable {
  func translate(words: [String], target: String) async throws -> [String]
}

struct BackendCandidateTranslationService: CandidateTranslationService {
  private static let client = BackendAccountClient()
  private static let session = BackendAccountSession(storage: BackendAnonymousAccount.sessionStorage())
  func translate(words: [String], target: String) async throws -> [String] {
    try await Self.client.translate(texts: words, target: target, token: token())
  }
  private func token() async throws -> String {
    if let value = try? await Self.session.accessToken() { return value }
    _ = try await BackendAnonymousAccount.ensureSignedIn(session: Self.session, client: Self.client)
    return try await Self.session.accessToken()
  }
}

@MainActor
final class CandidateTranslationStore {
  var onArrival: (() -> Void)?
  static let quietInterval: TimeInterval = 0.35
  private let service: any CandidateTranslationService
  private var cache: [String: String] = [:]
  private var signature: String?
  private var debounce: Timer?
  init(service: any CandidateTranslationService = BackendCandidateTranslationService()) { self.service = service }
  static func translatable(_ word: String) -> Bool {
    word.unicodeScalars.contains { scalar in
      (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
        || (0xF900...0xFAFF).contains(scalar.value) || (0x20000...0x3FFFF).contains(scalar.value)
    }
  }
  func gloss(word: String, code: String) -> String? { cache["\(code)|\(word)"] }
  func refresh(words: [String], codes: [String]) {
    debounce?.invalidate(); debounce = nil
    let wanted = words.filter(Self.translatable)
    guard !wanted.isEmpty, !codes.isEmpty else { return }
    let timer = Timer(timeInterval: Self.quietInterval, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated { self?.send(words: wanted, codes: codes) }
    }
    RunLoop.main.add(timer, forMode: .common); debounce = timer
  }
  func cancel() { debounce?.invalidate(); debounce = nil }
  private func send(words: [String], codes: [String]) {
    debounce = nil
    let stamp = (codes + words).joined(separator: "|")
    var pending: [String: [String]] = [:]
    for code in codes {
      let missing = words.filter { cache["\(code)|\($0)"] == nil }
      if !missing.isEmpty { pending[code] = missing }
    }
    guard !pending.isEmpty, stamp != signature else { signature = stamp; return }
    signature = stamp
    for (code, missing) in pending {
      let service = service
      Task { [weak self] in
        guard let glosses = try? await service.translate(words: missing, target: code) else { return }
        self?.absorb(code: code, words: missing, glosses: glosses)
      }
    }
  }
  private func absorb(code: String, words: [String], glosses: [String]) {
    guard words.count == glosses.count else { return }
    var arrived = false
    for (word, gloss) in zip(words, glosses) {
      let text = gloss.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty, text != word, text.utf8.count <= 4096 else { continue }
      cache["\(code)|\(word)"] = text; arrived = true
    }
    if arrived { onArrival?() }
  }
}
