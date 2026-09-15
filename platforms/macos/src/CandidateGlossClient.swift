import Foundation

// 候选释义走 /v1/translate,不走聊天模型。实测经 api.msime.app:专用机器翻译 0.5-0.7s,聊天模型
// 中位 2.0s 且长尾到 7.5s。组字往往只有两三秒,慢的那条根本赶不上 —— 答案回来时组字已经结束,只能
// 进缓存等下次,这就是「第一次没有、第二次才有」的由来。
//
// 代价是一次只能一个目标语言,英文和日文要发两次;但 2 × 0.5s 仍然远快于 1 × 2.0s,而且没有长尾。
enum CandidateGlossClient {
  static let notification = Notification.Name("MetasequoiaCandidateTranslationsDidArrive")

  private static let session = BackendAccountSession()
  private static let anonymous = BackendAccountSession(storage: BackendAnonymousAccount.sessionStorage())
  private static let client = BackendAccountClient()

  private static func token() async throws -> String {
    if let value = try? await session.accessToken() { return value }
    return try await anonymous.accessToken()
  }

  /// words 是这一页还没有释义的词;primaryCode/secondaryCode 是语言代码(EN/JA/…),后者为空表示不要第二条。
  /// 每种语言一个批量请求,两种语言并发发出 —— 一页九个候选的英日释义总共两个请求,而不是十八个。
  static func fetch(words: [String], primaryCode: String, secondaryCode: String, generation: UInt64) {
    guard !words.isEmpty, !primaryCode.isEmpty else { return }
    Task {
      guard let token = try? await token() else { return }
      await withTaskGroup(of: Void.self) { group in
        for (code, isSecondary) in [(primaryCode, false), (secondaryCode, true)] where !code.isEmpty {
          group.addTask {
            guard let glosses = try? await client.translate(texts: words, target: code, token: token)
            else { return }
            // let 而不是 var:跨越 await 被闭包捕获的可变量在 Swift 6 下是错误。
            // 同一页出现两个相同的词是可能的(不同编码打出同一个字),所以按第一条取,不能用
            // uniqueKeysWithValues —— 那个碰上重复键直接崩。
            let table = Dictionary(zip(words, glosses).filter { !$0.1.isEmpty && $0.1 != $0.0 },
                                   uniquingKeysWith: { first, _ in first })
            guard !table.isEmpty else { return }
            await MainActor.run {
              let key = isSecondary ? "secondaryTranslations" : "translations"
              NotificationCenter.default.post(name: notification, object: nil,
                                              userInfo: ["generation": generation, key: table])
            }
          }
        }
      }
    }
  }
}

@_cdecl("MSIMEFetchCandidateGlosses")
func fetchCandidateGlosses(_ wordsJSON: UnsafePointer<CChar>, _ primaryCode: UnsafePointer<CChar>,
                           _ secondaryCode: UnsafePointer<CChar>, _ generation: UInt64) {
  guard let data = String(cString: wordsJSON).data(using: .utf8),
        let words = try? JSONDecoder().decode([String].self, from: data)
  else { return }
  CandidateGlossClient.fetch(words: words, primaryCode: String(cString: primaryCode),
                             secondaryCode: String(cString: secondaryCode), generation: generation)
}
