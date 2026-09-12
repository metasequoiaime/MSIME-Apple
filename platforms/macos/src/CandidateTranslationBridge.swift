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
  private static let client = BackendAccountClient()
  // Resolved once per launch: the catalogue rarely changes and a model lookup per keystroke would
  // cost more than the translation it precedes.
  private static var cachedModel: String?

  static func translate(words: [String], languageName: String, generation: UInt64) {
    guard !words.isEmpty, !languageName.isEmpty else { return }
    Task {
      do {
        let token = try await session.accessToken()
        let model = try await resolveModel(token: token)
        let reply = try await client.chat(messages: prompt(words: words, languageName: languageName),
                                          model: model, token: token)
        let translations = parse(reply: reply, words: words)
        guard !translations.isEmpty else { return }
        await MainActor.run {
          NotificationCenter.default.post(name: notification, object: nil,
                                          userInfo: ["generation": generation, "translations": translations])
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
  private static func prompt(words: [String], languageName: String) -> [BackendAccountClient.ChatMessage] {
    let instruction = """
      Translate each Chinese word into \(languageName). Reply with nothing but a JSON object whose \
      keys are exactly the input words and whose values are the translations. Keep each translation \
      under four words, with no pronunciation, no notes and no punctuation at the end.
      """
    let payload = (try? JSONEncoder().encode(words)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    return [.init(role: "system", content: instruction), .init(role: "user", content: payload)]
  }

  private static func parse(reply: String, words: [String]) -> [String: String] {
    // Models fence JSON in code blocks often enough that the object is taken from the first brace
    // to the last rather than from the reply as a whole.
    guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
          let data = String(reply[start...end]).data(using: .utf8),
          let decoded = try? JSONDecoder().decode([String: String].self, from: data)
    else { return [:] }
    let asked = Set(words)
    var translations: [String: String] = [:]
    for (word, translation) in decoded {
      let trimmed = translation.trimmingCharacters(in: .whitespacesAndNewlines)
      // A word that was not asked about, an empty answer, or one long enough to be an explanation
      // rather than a gloss, is dropped: the strip has room for a few words beside a candidate.
      guard asked.contains(word), !trimmed.isEmpty, trimmed.count <= 40 else { continue }
      translations[word] = trimmed
    }
    return translations
  }
}

@_cdecl("MSIMETranslateCandidates")
func translateCandidates(_ wordsJSON: UnsafePointer<CChar>, _ languageName: UnsafePointer<CChar>,
                         _ generation: UInt64) {
  let payload = String(cString: wordsJSON)
  guard let data = payload.data(using: .utf8),
        let words = try? JSONDecoder().decode([String].self, from: data)
  else { return }
  CandidateTranslationBridge.translate(words: words, languageName: String(cString: languageName),
                                       generation: generation)
}

// Whether an account is signed in, so the settings can say what a provider needs before anyone
// turns it on. Reading the keychain is cheap and synchronous, and the token itself is not needed to
// answer this much.
@_cdecl("MSIMEBackendAccountSignedIn")
func backendAccountSignedIn() -> Bool {
  ((try? BackendKeychain().load()) ?? nil) != nil
}
