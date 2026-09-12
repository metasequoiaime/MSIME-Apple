struct MacEmojiSymbolGroup: Hashable, Sendable {
  let parent: String
  let title: String

  static func queryFilters(search: String, parent: String, group: String) -> (parent: String, group: String) {
    search.isEmpty ? (parent, group) : ("", "")
  }

  static func parents(_ groups: [Self]) -> [String] { unique(groups.map(\.parent)) }
  static func titles(_ groups: [Self], parent: String) -> [String] {
    unique(groups.filter { parent.isEmpty || $0.parent == parent }.map(\.title))
  }
  private static func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
  }
}
