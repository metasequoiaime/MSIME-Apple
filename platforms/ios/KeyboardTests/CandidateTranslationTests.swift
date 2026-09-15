import XCTest
import UIKit

/// 不联网的翻译服务。单测跑在模拟器上,真请求既慢又要一个账号。
private final class StubTranslationService: CandidateTranslationService, @unchecked Sendable {
  private let answers: [String: [String: String]]
  private let lock = NSLock()
  private var recorded: [(code: String, words: [String])] = []

  init(answers: [String: [String: String]]) { self.answers = answers }

  var calls: [(code: String, words: [String])] { lock.withLock { recorded } }

  func translate(words: [String], target: String) async throws -> [String] {
    lock.withLock { recorded.append((target, words)) }
    return words.map { answers[target]?[$0] ?? "" }
  }
}

/// 回来的条数比送出去的少一条 —— 释义是按位置配回候选的,错位比没有更糟。
private struct TruncatingTranslationService: CandidateTranslationService {
  func translate(words: [String], target: String) async throws -> [String] {
    Array(words.dropLast()).map { $0 + "?" }
  }
}

@MainActor
final class CandidateTranslationTests: XCTestCase {
  func testOnlyCandidatesWithHanCharactersGoOutToTheNetwork() {
    XCTAssertTrue(CandidateTranslationStore.translatable("你好"))
    XCTAssertTrue(CandidateTranslationStore.translatable("啊"))
    XCTAssertFalse(CandidateTranslationStore.translatable("nihao"), "拼音缓冲不是词,译过去没有意义")
    XCTAssertFalse(CandidateTranslationStore.translatable("OpenAI"))
    XCTAssertFalse(CandidateTranslationStore.translatable("123"))
    XCTAssertFalse(CandidateTranslationStore.translatable("😀"))
  }

  func testEachLanguageIsAskedOnceAndTheAnswerIsKept() async throws {
    let service = StubTranslationService(
      answers: ["EN": ["你好": "hello"], "JA": ["你好": "こんにちは"]])
    let store = CandidateTranslationStore(service: service)
    let arrived = expectation(description: "释义到达")
    arrived.expectedFulfillmentCount = 2
    store.onArrival = { arrived.fulfill() }

    store.refresh(words: ["你好", "nihao"], codes: ["EN", "JA"])
    await fulfillment(of: [arrived], timeout: 5)

    XCTAssertEqual(store.gloss(word: "你好", code: "EN"), "hello")
    XCTAssertEqual(store.gloss(word: "你好", code: "JA"), "こんにちは")
    XCTAssertEqual(service.calls.count, 2, "一种语言一个请求,不是一个词一个请求")
    XCTAssertTrue(service.calls.allSatisfy { $0.words == ["你好"] }, "只有含汉字的候选送得出去")

    // 同一页再排一次:都在缓存里了,不该再问一遍。
    store.refresh(words: ["你好", "nihao"], codes: ["EN", "JA"])
    try await Task.sleep(nanoseconds: 900_000_000)
    XCTAssertEqual(service.calls.count, 2, "整页都有释义时不该再发请求")
  }

  func testABatchThatComesBackShortIsDroppedWhole() async throws {
    let store = CandidateTranslationStore(service: TruncatingTranslationService())
    store.refresh(words: ["你好", "中国"], codes: ["EN"])
    try await Task.sleep(nanoseconds: 900_000_000)
    XCTAssertNil(store.gloss(word: "你好", code: "EN"), "条数对不上就整批丢掉,不能错位")
    XCTAssertNil(store.gloss(word: "中国", code: "EN"))
  }

  func testAQueuedRequestIsCancelledWhenTheCompositionEnds() async throws {
    let service = StubTranslationService(answers: ["EN": ["你好": "hello"]])
    let store = CandidateTranslationStore(service: service)
    store.refresh(words: ["你好"], codes: ["EN"])
    store.cancel()
    try await Task.sleep(nanoseconds: 900_000_000)
    XCTAssertTrue(service.calls.isEmpty, "组字结束后这一页已经不在屏幕上了")
  }

  func testGlossTakesItsOwnLineUnderTheCandidate() throws {
    let previousScheme = InputSchemePreference.scheme
    let previousGloss = CandidateGlossPreference.enabled
    defer {
      InputSchemePreference.scheme = previousScheme
      CandidateGlossPreference.enabled = previousGloss
    }
    InputSchemePreference.scheme = .quanpin
    CandidateGlossPreference.enabled = true

    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 306)
    controller.viewWillAppear(false)
    for letter in ["字母 N", "字母 I", "字母 H", "字母 A", "字母 O"] {
      try XCTUnwrap(descendants(controller.view).first { $0.accessibilityLabel == letter } as? UIButton)
        .sendActions(for: .primaryActionTriggered)
    }
    controller.view.layoutIfNeeded()
    let chip = try XCTUnwrap(
      descendants(controller.view).first { $0.accessibilityIdentifier == "candidate-1" } as? UIButton)
    let title = try XCTUnwrap(chip.configuration?.attributedTitle.map { String($0.characters) })
    let lines = title.split(separator: "\n", omittingEmptySubsequences: false)
    XCTAssertEqual(lines.count, 2, "释义独占一行,不再挤在候选右边:\(title)")
    XCTAssertEqual(lines.first, "你好")
    XCTAssertTrue(lines[1].lowercased().contains("hello"), "释义来自随包的离线词库:\(title)")
    XCTAssertEqual(chip.titleLabel?.numberOfLines, 2, "行数没跟上就会被截掉")
  }

  func testARowIsReservedOnlyForAGlossThatCanActuallyBeFetched() throws {
    let previousGloss = CandidateGlossPreference.enabled
    let previousSecondary = CandidateTranslationPreference.secondaryIndex
    defer {
      CandidateGlossPreference.enabled = previousGloss
      CandidateTranslationPreference.secondaryIndex = previousSecondary
    }

    CandidateGlossPreference.enabled = false
    CandidateTranslationPreference.secondaryIndex = -1
    XCTAssertEqual(KeyboardViewController.configuredGlossLines(fullAccess: true), 0, "关着释义时一行都不留")

    CandidateGlossPreference.enabled = true
    XCTAssertEqual(KeyboardViewController.configuredGlossLines(fullAccess: false), 1,
                   "英语走随包的离线词库,没有网络也答得上")

    CandidateTranslationPreference.secondaryIndex = 1
    XCTAssertEqual(KeyboardViewController.configuredGlossLines(fullAccess: false), 1,
                   "没有完全访问权限就没有网络,日语那一行永远填不上,不给它留空白")
    XCTAssertEqual(KeyboardViewController.configuredGlossLines(fullAccess: true), 2,
                   "能取到了才长这一行")
  }

  func testTheKeyboardGrowsByTheRowsTheStripReserves() throws {
    let previousGloss = CandidateGlossPreference.enabled
    let previousSecondary = CandidateTranslationPreference.secondaryIndex
    defer {
      CandidateGlossPreference.enabled = previousGloss
      CandidateTranslationPreference.secondaryIndex = previousSecondary
    }
    CandidateTranslationPreference.secondaryIndex = -1

    func keyboardHeight() -> CGFloat? {
      let controller = KeyboardViewController()
      controller.loadViewIfNeeded()
      controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 320)
      controller.viewWillAppear(false)
      return controller.view.constraints.first { $0.identifier == "keyboardHeight" }?.constant
    }

    CandidateGlossPreference.enabled = false
    let bare = try XCTUnwrap(keyboardHeight())
    CandidateGlossPreference.enabled = true
    let glossed = try XCTUnwrap(keyboardHeight())
    XCTAssertEqual(glossed - bare, KeyboardViewController.glossLineHeight,
                   "释义那一行是键盘长出来的,不是从按键身上挪的")
  }

  func testTheExpandedPanelDrawsTheSameGlossesAsTheStrip() throws {
    // 展开面板是另一套格子。它一直只画五笔剩余编码,于是打开释义之后展开候选,那里仍然什么都没有。
    let panel = KeyboardCandidatePanelView(
      candidates: ["你好", "泥好"], hints: ["", ""], glosses: [["hello", "こんにちは"], []],
      preedit: "nihao", display: { $0 }, onSelect: { _ in }, onClose: {})
    panel.frame = CGRect(x: 0, y: 0, width: 390, height: 220)
    panel.layoutIfNeeded()

    let glossed = try XCTUnwrap(
      descendants(panel).first { $0.accessibilityIdentifier == "panelCandidate-1" } as? UIButton)
    let title = try XCTUnwrap(glossed.configuration?.attributedTitle.map { String($0.characters) })
    XCTAssertEqual(title.split(separator: "\n", omittingEmptySubsequences: false),
                   ["你好", "hello", "こんにちは"])
    XCTAssertEqual(glossed.titleLabel?.numberOfLines, 3)

    let bare = try XCTUnwrap(
      descendants(panel).first { $0.accessibilityIdentifier == "panelCandidate-2" } as? UIButton)
    XCTAssertEqual(bare.configuration?.title, "泥好", "没有释义的候选还是一行")
  }

  func testPanelChipsAreAsWideAsTheirWidestLine() throws {
    // 带释义的标题是多行的,而多行标签在压缩优先级下能缩到任意窄。照 systemLayoutSizeFitting 量出来的宽度接近零,于是每个格子都被排成一丁点宽,候选被截成「您…」,后面几排干脆只剩「…」。
    let panel = KeyboardCandidatePanelView(
      candidates: ["您好", "你好"], hints: ["", ""],
      glosses: [["hello; how do you do"], []], preedit: "nhao",
      display: { $0 }, onSelect: { _ in }, onClose: {})
    panel.frame = CGRect(x: 0, y: 0, width: 390, height: 240)
    panel.layoutIfNeeded()

    func chip(_ identifier: String) throws -> UIButton {
      try XCTUnwrap(descendants(panel).first { $0.accessibilityIdentifier == identifier } as? UIButton)
    }
    let glossed = try chip("panelCandidate-1")
    let gloss = NSAttributedString(string: "hello; how do you do",
                                   attributes: [.font: UIFont.preferredFont(forTextStyle: .caption2)])
    XCTAssertGreaterThanOrEqual(glossed.bounds.width, gloss.size().width,
                               "格子要容得下最宽的那一行,否则候选被截成「您…」")

    let bare = try chip("panelCandidate-2")
    let word = NSAttributedString(string: "你好",
                                  attributes: [.font: UIFont.preferredFont(forTextStyle: .body)])
    XCTAssertGreaterThanOrEqual(bare.bounds.width, word.size().width, "没有释义的格子也不该被压窄")
  }

  func testTheLanguageTableAnswersTheFirstEntryForAnIndexOutOfRange() {
    XCTAssertEqual(CandidateTranslationPreference.language(at: 0).code, "EN")
    XCTAssertEqual(CandidateTranslationPreference.language(at: 1).code, "JA")
    XCTAssertEqual(CandidateTranslationPreference.language(at: 99).code, "EN")
    XCTAssertEqual(CandidateTranslationPreference.language(at: -1).code, "EN")
    XCTAssertFalse(CandidateTranslationPreference.needsNetwork(.init(title: "英语", code: "EN")))
    XCTAssertTrue(CandidateTranslationPreference.needsNetwork(.init(title: "日语", code: "JA")))
  }

  private func descendants(_ view: UIView) -> [UIView] {
    [view] + view.subviews.flatMap { descendants($0) }
  }
}
