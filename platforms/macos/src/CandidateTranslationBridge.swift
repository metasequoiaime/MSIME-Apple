import Foundation

// Glosses candidates through the account's own model, so nobody has to hold a translation vendor's
// keys to see what a candidate means. The words go out as one request and come back as one object,
// which is both cheaper than a call per candidate and what lets the model keep a page consistent.
//
// The controller drives this from Objective-C, so the entry point is a C function and the answer
// comes back as a notification rather than a block: a @_cdecl function cannot take an Objective-C
// block, and the controller already listens for the preference notifications next to this one.
enum CandidateTranslationBridge {
  static let notification = Notification.Name("MetasequoiaCandidateTranslationsDidArrive")

  private static let session = BackendAccountSession()
  // 匿名会话不在钥匙串里,所以取 token 时两处都要试:用户自己登录过就用他的,否则用匿名的。
  private static let anonymousSession = BackendAccountSession(storage: BackendAnonymousAccount.sessionStorage())

  private static func anyAccessToken() async throws -> String {
    if let token = try? await session.accessToken() { return token }
    return try await anonymousSession.accessToken()
  }
  private static let client = BackendAccountClient()
  // Resolved once per launch: the catalogue rarely changes and a model lookup per keystroke would
  // cost more than the translation it precedes.
  private static var cachedModel: String?

  // 两种语言一次要回来。候选格同时摆英文和日文,分两次请求就是把每次组字的调用翻倍 —— 模型一次
  // answer 两栏和答一栏的代价几乎一样,而账号是按调用计的。
  static func translate(words: [String], languageName: String, secondaryLanguageName: String,
                        generation: UInt64) {
    guard !words.isEmpty, !languageName.isEmpty else { return }
    Task {
      do {
        let token = try await anyAccessToken()
        let model = try await resolveModel(token: token)
        let reply = try await client.chat(
          messages: prompt(words: words, languageName: languageName,
                           secondaryLanguageName: secondaryLanguageName),
          model: model, token: token)
        let (primary, secondary) = parse(reply: reply, words: words,
                                         wantsSecondary: !secondaryLanguageName.isEmpty)
        guard !primary.isEmpty || !secondary.isEmpty else { return }
        await MainActor.run {
          NotificationCenter.default.post(name: notification, object: nil,
                                          userInfo: ["generation": generation, "translations": primary,
                                                     "secondaryTranslations": secondary])
        }
      } catch {
        // Signed out, offline, or a model that would not answer in the shape asked for. The strip
        // simply stays as it is; a candidate window is the wrong place to report a failed request.
      }
    }
  }

  private static func resolveModel(token: String) async throws -> String {
    if let cachedModel { return cachedModel }
    let catalog = try await client.chatModels(token: token)
    cachedModel = catalog.default_model
    return catalog.default_model
  }

  // The model is asked for an object keyed by the words themselves, so a reply that drops or
  // reorders an entry still lands against the right candidate instead of shifting the whole page.
  private static func prompt(words: [String], languageName: String,
                            secondaryLanguageName: String) -> [BackendAccountClient.ChatMessage] {
    let shape = secondaryLanguageName.isEmpty
      ? "whose values are the \(languageName) translations"
      : "whose values are objects with the keys \"a\" for \(languageName) and \"b\" for \(secondaryLanguageName)"
    let instruction = """
      Translate each Chinese word. Reply with nothing but a JSON object whose keys are exactly the \
      input words and \(shape). Keep each translation under four words, with no pronunciation, no \
      notes and no punctuation at the end.
      """
    let payload = (try? JSONEncoder().encode(words)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    return [.init(role: "system", content: instruction), .init(role: "user", content: payload)]
  }

  private struct Pair: Decodable { let a: String?; let b: String? }

  private static func parse(reply: String, words: [String],
                            wantsSecondary: Bool) -> ([String: String], [String: String]) {
    // Models fence JSON in code blocks often enough that the object is taken from the first brace
    // to the last rather than from the reply as a whole.
    guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
          let data = String(reply[start...end]).data(using: .utf8)
    else { return ([:], [:]) }
    let asked = Set(words)
    var primary: [String: String] = [:]
    var secondary: [String: String] = [:]
    // A word that was not asked about, an empty answer, or one long enough to be an explanation
    // rather than a gloss, is dropped: a candidate cell has room for a few words, not a sentence.
    func take(_ word: String, _ value: String?, into table: inout [String: String]) {
      guard asked.contains(word), let value else { return }
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, trimmed.count <= 40 else { return }
      table[word] = trimmed
    }
    if wantsSecondary, let decoded = try? JSONDecoder().decode([String: Pair].self, from: data) {
      for (word, pair) in decoded {
        take(word, pair.a, into: &primary)
        take(word, pair.b, into: &secondary)
      }
      return (primary, secondary)
    }
    // 模型没按两栏的形状答就退回单栏,而不是整包丢掉:一条释义也比没有强。
    if let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
      for (word, value) in decoded {
        take(word, value, into: &primary)
      }
    }
    return (primary, secondary)
  }
}

@_cdecl("MSIMETranslateCandidates")
func translateCandidates(_ wordsJSON: UnsafePointer<CChar>, _ languageName: UnsafePointer<CChar>,
                         _ secondaryLanguageName: UnsafePointer<CChar>, _ generation: UInt64) {
  let payload = String(cString: wordsJSON)
  guard let data = payload.data(using: .utf8),
        let words = try? JSONDecoder().decode([String].self, from: data)
  else { return }
  CandidateTranslationBridge.translate(words: words, languageName: String(cString: languageName),
                                       secondaryLanguageName: String(cString: secondaryLanguageName),
                                       generation: generation)
}

// Whether an account is signed in, so the settings can say what a provider needs before anyone
// turns it on. Reading the keychain is cheap and synchronous, and the token itself is not needed to
// answer this much.
@_cdecl("MSIMEBackendAccountSignedIn")
func backendAccountSignedIn() -> Bool {
  ((try? BackendKeychain().load()) ?? nil) != nil
}

// 首次激活时自动开一个匿名账号。The controller is Objective-C and this target emits no -Swift.h, so the
// entry point is a @_cdecl function like the rest of the bridges in this file.
//
// 只尝试一次,失败就算了:开户不成功不该拦着用户打字,下次激活会再试。登录成功前不写钥匙串,所以失败
// 不会留下一把永远登不上的凭据。
private actor AnonymousBootstrap {
  static let shared = AnonymousBootstrap()
  private var attempted = false
  func runOnce() async {
    guard !attempted else { return }
    attempted = true
    // 用户主动挂上去的身份在钥匙串里;先问它,匿名账号不能把它顶掉。
    let signedIn = BackendAccountSession()
    if (try? await signedIn.accessToken()) != nil { return }
    // 匿名账号连同它换来的会话都留在本机文件里,不进钥匙串 —— 自动生成、用户全程不知情的东西不该
    // 让输入法去问登录密码。
    let anonymous = BackendAccountSession(storage: BackendAnonymousAccount.sessionStorage())
    if (try? await anonymous.accessToken()) != nil { return }
    _ = try? await BackendAnonymousAccount.ensureSignedIn(session: anonymous, client: BackendAccountClient())
  }
}

@_cdecl("MSIMEEnsureAnonymousAccount")
func ensureAnonymousAccount() {
  Task { await AnonymousBootstrap.shared.runOnce() }
}
