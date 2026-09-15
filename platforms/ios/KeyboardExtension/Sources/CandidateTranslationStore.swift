import Foundation

/// 把一批词译成一种语言。回来的条数必须和送出去的一样多 —— 释义是按位置配回候选的。
///
/// 抽成协议是为了让测试能不联网地驱动整条路径:键盘的单测跑在模拟器上,发真请求既慢又要账号。
protocol CandidateTranslationService: Sendable {
  func translate(words: [String], target: String) async throws -> [String]
}

/// 走账号的翻译接口,客户端不持有任何第三方密钥。
///
/// 用匿名账号:真实登录的会话存在宿主 App 的钥匙串里,键盘扩展没有共享的 keychain group,读不到;而匿名凭据和它换来的会话都在 App Group 的文件里,两边都看得见。没有就现场建一个 —— 这跟 macOS 首次激活时做的是同一件事,只是 iOS 这边推迟到用户真的打开了联网释义。
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

/// 候选词的联网释义。
///
/// 一页候选一种语言发一个请求,回来的释义按「语言|词」存在内存里,重绘时按词取。缓存不带代际:释义讲的是这个词本身,晚一个按键到达也仍然是它的释义,丢掉只会让下次再问一遍。
@MainActor
final class CandidateTranslationStore {
  /// 有新释义落表时调用,交给调用方重绘候选。
  var onArrival: (() -> Void)?

  /// 安静这么久才发请求。组字是连着敲出来的,每敲一下就问一次等于把一次输入拆成七八个请求。
  static let quietInterval: TimeInterval = 0.35

  private let service: any CandidateTranslationService
  private var cache: [String: String] = [:]
  /// 上一次真正问出去的那一页的签名。同一页问过一次就够了,答案没回来之前重绘多少次都不该再发。
  private var signature: String?
  private var debounce: Timer?

  init(service: any CandidateTranslationService = BackendCandidateTranslationService()) {
    self.service = service
  }

  /// 这个候选能不能送去联网翻译。只有含汉字的可以 —— 拼音缓冲和纯 ASCII 串译过去没有意义,而且会把用户的原始按键序列送给翻译服务。判据跟 macOS 的 `CandidateSupportsOnlineGloss` 一致。
  static func translatable(_ word: String) -> Bool {
    word.unicodeScalars.contains { scalar in
      (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
        || (0xF900...0xFAFF).contains(scalar.value) || (0x20000...0x3FFFF).contains(scalar.value)
    }
  }

  func gloss(word: String, code: String) -> String? {
    cache[Self.key(word: word, code: code)]
  }

  /// 排一次请求。这一页的词一个都不缺时不发,签名没变时也不发。
  func refresh(words: [String], codes: [String]) {
    debounce?.invalidate()
    debounce = nil
    let wanted = words.filter(Self.translatable)
    guard !wanted.isEmpty, !codes.isEmpty else { return }
    let timer = Timer(timeInterval: Self.quietInterval, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated { self?.send(words: wanted, codes: codes) }
    }
    RunLoop.main.add(timer, forMode: .common)
    debounce = timer
  }

  /// 排队中的请求作废 —— 组字结束了,这一页候选已经不在屏幕上。
  func cancel() {
    debounce?.invalidate()
    debounce = nil
  }

  private func send(words: [String], codes: [String]) {
    debounce = nil
    let stamp = (codes + words).joined(separator: "|")
    var pending: [String: [String]] = [:]
    for code in codes {
      let missing = words.filter { cache[Self.key(word: $0, code: code)] == nil }
      if !missing.isEmpty { pending[code] = missing }
    }
    // 一页都齐了就把签名记下:下次同一页连查都不用查。
    guard !pending.isEmpty else {
      signature = stamp
      return
    }
    guard stamp != signature else { return }
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
    // 少一条就对不上号了 —— 宁可整批丢掉也不能错位。
    guard words.count == glosses.count else { return }
    var arrived = false
    for (word, gloss) in zip(words, glosses) {
      let text = gloss.trimmingCharacters(in: .whitespacesAndNewlines)
      // 译文和原词一样等于没译出来。留着它只会占住位置,让这个词再也不会被重问。
      guard !text.isEmpty, text != word else { continue }
      cache[Self.key(word: word, code: code)] = text
      arrived = true
    }
    if arrived { onArrival?() }
  }

  private static func key(word: String, code: String) -> String { "\(code)|\(word)" }
}
