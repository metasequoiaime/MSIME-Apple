import Foundation

private func expect(
  _ expected: String,
  _ text: String,
  traditional: Bool,
  file: StaticString = #file,
  line: UInt = #line
) {
  let actual = ChineseTextConversion.outputString(text, traditional: traditional)
  precondition(
    actual == expected,
    "Expected \(expected) for \(text) with traditional \(traditional), got \(actual)",
    file: file,
    line: line)
}

@main
struct ChineseTextConversionTests {
  static func main() {
    expect("水杉输入法", "水杉输入法", traditional: false)
    expect("水杉輸入法", "水杉输入法", traditional: true)

    expect("", "", traditional: true)
    expect("metasequoia", "metasequoia", traditional: true)
    expect("，。！", "，。！", traditional: true)

    // Already-traditional and mixed text stays readable instead of being mangled.
    expect("輸入法", "輸入法", traditional: true)
    expect("輸入 abc 法", "输入 abc 法", traditional: true)
  }
}
