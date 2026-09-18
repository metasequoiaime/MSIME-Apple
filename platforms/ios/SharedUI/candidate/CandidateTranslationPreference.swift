import Foundation

struct CandidateTranslationLanguage: Equatable, Sendable {
  let title: String
  let code: String
}

enum CandidateTranslationPreference {
  static let primaryKey = "candidate.translationLanguage"
  static let secondaryKey = "candidate.translationSecondaryLanguage"
  static let onlineKey = "candidate.translationOnline"
  static var defaults: UserDefaults {
    UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier) ?? .standard
  }
  static let languages = [
    CandidateTranslationLanguage(title: "英语", code: "EN"),
    CandidateTranslationLanguage(title: "日语", code: "JA"),
    CandidateTranslationLanguage(title: "韩语", code: "KO"),
    CandidateTranslationLanguage(title: "西班牙语", code: "ES"),
    CandidateTranslationLanguage(title: "法语", code: "FR"),
    CandidateTranslationLanguage(title: "德语", code: "DE"),
  ]
  static func language(at index: Int) -> CandidateTranslationLanguage {
    languages.indices.contains(index) ? languages[index] : languages[0]
  }
  static var primaryIndex: Int {
    get { languageIndex(defaults.object(forKey: primaryKey) as? Int ?? 0, fallback: 0) }
    set { defaults.set(languageIndex(newValue, fallback: 0), forKey: primaryKey) }
  }
  static var secondaryIndex: Int {
    get {
      guard let value = defaults.object(forKey: secondaryKey) as? Int else { return -1 }
      return languages.indices.contains(value) ? value : -1
    }
    set { defaults.set(languages.indices.contains(newValue) ? newValue : -1, forKey: secondaryKey) }
  }
  static var onlineEnabled: Bool {
    get { defaults.object(forKey: onlineKey) as? Bool ?? true }
    set { defaults.set(newValue, forKey: onlineKey) }
  }
  static var primary: CandidateTranslationLanguage { language(at: primaryIndex) }
  static var secondary: CandidateTranslationLanguage? {
    let index = secondaryIndex
    return languages.indices.contains(index) ? languages[index] : nil
  }
  static func needsNetwork(_ language: CandidateTranslationLanguage) -> Bool { language.code != "EN" }
  private static func languageIndex(_ value: Int, fallback: Int) -> Int {
    languages.indices.contains(value) ? value : fallback
  }
}
