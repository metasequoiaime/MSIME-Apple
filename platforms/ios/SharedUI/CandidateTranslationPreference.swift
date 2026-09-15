import Foundation

/// 候选释义的目标语言。
///
/// 表跟 `platforms/macos/src/CandidateTranslationLanguage.h` 的 `kCandidateTranslationLanguages` 一一对应,顺序也一样:两端存的都是**下标**,顺序一旦分叉,同一个偏好在两个平台上就是两种语言。`ProjectConfigurationTests` 会把两张表读出来比一遍。
struct CandidateTranslationLanguage: Equatable, Sendable {
  /// 设置里显示的名字。
  let title: String
  /// 机器翻译接口接受的语言代码。
  let code: String
}

/// 候选词释义的语言选择与联网开关。
///
/// 开关本身仍然是 [CandidateGlossPreference]:那是「要不要在候选后面写释义」这一件事,这里只回答「写成哪种语言」。释义关着的时候这里的设置一律不生效,也就不会有任何网络请求。
enum CandidateTranslationPreference {
  /// 第一条释义的语言,存的是 [languages] 的下标。
  static let primaryKey = "candidate.translationLanguage"
  /// 第二条释义的语言,-1 表示只要一条。
  static let secondaryKey = "candidate.translationSecondaryLanguage"
  /// 本机词库答不上来时,要不要向账号的翻译接口补一次。
  static let onlineKey = "candidate.translationOnline"

  static var defaults: UserDefaults {
    UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier) ?? .standard
  }

  static let languages: [CandidateTranslationLanguage] = [
    CandidateTranslationLanguage(title: "英语", code: "EN"),
    CandidateTranslationLanguage(title: "日语", code: "JA"),
    CandidateTranslationLanguage(title: "韩语", code: "KO"),
    CandidateTranslationLanguage(title: "西班牙语", code: "ES"),
    CandidateTranslationLanguage(title: "法语", code: "FR"),
    CandidateTranslationLanguage(title: "德语", code: "DE"),
  ]

  /// 越界的下标答第一种语言,而不是读出表外的东西。这张表长过一次,还会再长;旧版本读到新版本写下的下标时,不该由它来决定指向哪里。
  static func language(at index: Int) -> CandidateTranslationLanguage {
    languages.indices.contains(index) ? languages[index] : languages[0]
  }

  static var primaryIndex: Int {
    get {
      let stored = defaults.object(forKey: primaryKey) as? Int ?? 0
      return languages.indices.contains(stored) ? stored : 0
    }
    set { defaults.set(languages.indices.contains(newValue) ? newValue : 0, forKey: primaryKey) }
  }

  /// -1 表示不要第二条。读日文的人开它值一行,不读的人白白让候选栏高一截,所以默认关。
  static var secondaryIndex: Int {
    get {
      let stored = defaults.object(forKey: secondaryKey) as? Int ?? -1
      return languages.indices.contains(stored) ? stored : -1
    }
    set { defaults.set(languages.indices.contains(newValue) ? newValue : -1, forKey: secondaryKey) }
  }

  /// 默认开。释义总开关关着的时候它什么都不做,而一旦用户主动打开释义,只有英语能靠随包的离线词库答上来 —— 别的语言不联网就是一片空白。
  static var onlineEnabled: Bool {
    get { defaults.object(forKey: onlineKey) as? Bool ?? true }
    set { defaults.set(newValue, forKey: onlineKey) }
  }

  static var primary: CandidateTranslationLanguage { language(at: primaryIndex) }

  static var secondary: CandidateTranslationLanguage? {
    let index = secondaryIndex
    return languages.indices.contains(index) ? languages[index] : nil
  }

  /// 离线词库只有英汉两个方向。选了别的语言就只能联网,这决定了设置里要不要提示、以及要不要发请求。
  static func needsNetwork(_ language: CandidateTranslationLanguage) -> Bool {
    language.code != "EN"
  }
}
