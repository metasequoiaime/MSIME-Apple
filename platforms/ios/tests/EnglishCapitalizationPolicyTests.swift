import Foundation

private func expect(
  _ expected: Bool,
  _ mode: EnglishCapitalizationMode,
  _ context: String?,
  file: StaticString = #file,
  line: UInt = #line
) {
  let actual = EnglishCapitalizationPolicy.shouldShift(
    for: mode, contextBeforeInput: context)
  precondition(
    actual == expected,
    "Expected \(expected) for \(mode) with context \(String(describing: context)), got \(actual)",
    file: file,
    line: line)
}

@main
struct EnglishCapitalizationPolicyTests {
  static func main() {
    expect(false, .none, "")
    expect(false, .sentences, nil)
    expect(true, .allCharacters, nil)

    expect(true, .words, "")
    expect(true, .words, "hello ")
    expect(false, .words, "hel")
    expect(false, .words, "don't")
    expect(false, .words, "don'")

    expect(true, .sentences, "")
    expect(false, .sentences, "Hello")
    expect(true, .sentences, "Hello. ")
    expect(true, .sentences, "Really!\n")
    expect(true, .sentences, "Done.” ")
  }
}
