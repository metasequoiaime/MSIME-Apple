import Foundation

/// 候选词下面显示释义。语言由 [CandidateTranslationPreference] 决定。
///
/// macOS has carried this since the candidate panel learned to draw a second column; iOS had the dictionary in its bundle the whole time and nothing that read it.
///
/// 默认开,和 macOS 一致。当初默认关的理由是「释义挤在候选右边,是在改键盘的读法」—— 那条理由随着释义搬到自己一行就没有了,而留着默认关的结果是功能做完了没人看见:得先知道它存在,才找得到那个开关。代价是键盘高出一行,以及联网那一档默认也是开的(仍然要键盘有完全访问权限才发得出请求),关掉它的人一次就关掉了。
enum CandidateGlossPreference {
  static let enabledKey = "candidate.englishGloss"
  static var defaults: UserDefaults {
    UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier) ?? .standard
  }

  static var enabled: Bool {
    get { defaults.object(forKey: enabledKey) as? Bool ?? true }
    set { defaults.set(newValue, forKey: enabledKey) }
  }
}
