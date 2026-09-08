import XCTest
import UIKit

@MainActor
final class HandwritingTests: XCTestCase {
  // Pen trajectories for 中国, not text rendered using a font.
  private var chineseInk: [[CGPoint]] {
    let points: [[(Double, Double)]] = [
      [(35, 40), (35, 105)], [(35, 40), (125, 40), (125, 105)], [(35, 105), (125, 105)], [(80, 15), (80, 140)],
      [(175, 20), (175, 140)], [(175, 20), (280, 20), (280, 140)], [(175, 140), (280, 140)],
      [(192, 45), (261, 45)], [(198, 78), (257, 78)], [(226, 45), (226, 112)], [(190, 112), (264, 112)], [(247, 91), (256, 101)],
    ]
    return points.map { $0.map { CGPoint(x: $0.0, y: $0.1) } }
  }
  func testRealChineseInkRecognition() async throws {
    let canvas = HandwritingCanvas(frame: CGRect(x: 0, y: 0, width: 320, height: 155))
    canvas.setTestStrokes(chineseInk)
    let recognizer = HandwritingRecognizer()
    try await recognizer.download { _ in }
    let words = try await recognizer.recognize(Array(chineseInk.prefix(4)), width: 160, height: 155)
    XCTAssertEqual(words.first, "中", "Actual candidates: \(words)")
  }
  func testCommonCharactersFromPenTrajectories() async throws {
    let recognizer = HandwritingRecognizer()
    try await recognizer.download { _ in }
    let examples: [(String, [[(Double, Double)]])] = [
      ("人", [[(80,20),(75,55),(60,95),(30,140)],[(73,65),(90,100),(130,140)]]),
      ("大", [[(25,65),(135,65)],[(80,20),(75,70),(60,110),(25,145)],[(78,70),(95,110),(140,145)]]),
      ("木", [[(25,60),(135,60)],[(80,15),(80,145)],[(76,65),(55,95),(20,125)],[(85,70),(105,100),(140,125)]]),
      ("水", [[(80,15),(80,135),(73,145),(58,135)],[(20,65),(55,65),(45,90),(18,120)],[(130,40),(95,75)],[(85,60),(103,100),(140,130)]]),
      ("天", [[(35,30),(125,30)],[(20,65),(140,65)],[(80,30),(75,80),(55,120),(20,145)],[(78,80),(100,120),(140,145)]]),
      ("日", [[(40,20),(40,140)],[(40,20),(120,20),(120,140)],[(40,80),(120,80)],[(40,140),(120,140)]]),
    ]
    for (expected, strokes) in examples {
      let ink = strokes.map { $0.map { CGPoint(x: $0.0, y: $0.1) } }
      let words = try await recognizer.recognize(ink, width: 160, height: 160)
      print("Handwriting \(expected): \(words)")
      XCTAssertEqual(words.first, expected, "Actual candidates for \(expected): \(words)")
    }
  }
  func testCandidateSelectionInsertsOnlyAfterConfirmation() async throws {
    try await HandwritingRecognizer().download { _ in }
    let panel = HandwritingInputView(frame: CGRect(x: 0, y: 0, width: 414, height: 160))
    panel.layoutIfNeeded()
    var inserted = ""
    panel.onInsert = { inserted += $0 }
    panel.canvas.setTestStrokes(chineseInk.prefix(4).map { $0.map { CGPoint(x: $0.x * 0.6 + 5, y: $0.y * 0.6 + 5) } })
    for _ in 0..<100 {
      if !panel.results.isEmpty { break }
      try await Task.sleep(nanoseconds: 50_000_000)
    }
    XCTAssertTrue(panel.results.contains("中"))
    XCTAssertEqual(inserted, "")
    let candidate = try XCTUnwrap(nodes(panel).first { ($0 as? UIButton)?.title(for: .normal) == "中" } as? UIButton)
    candidate.sendActions(for: .primaryActionTriggered)
    XCTAssertEqual(inserted, "中")
    XCTAssertFalse(panel.hasInk)
    XCTAssertTrue(panel.results.isEmpty)
    candidate.sendActions(for: .primaryActionTriggered)
    XCTAssertEqual(inserted, "中", "A stale candidate must not insert again")
  }

  func testClearInvalidatesPendingRecognitionAndUndoRemovesOneStroke() async throws {
    let panel = HandwritingInputView(frame: CGRect(x: 0, y: 0, width: 414, height: 160))
    panel.layoutIfNeeded()
    panel.canvas.setTestStrokes(chineseInk)
    panel.canvas.undo()
    XCTAssertEqual(panel.canvas.strokes.count, chineseInk.count - 1)
    panel.clear()
    try await Task.sleep(nanoseconds: 900_000_000)
    XCTAssertFalse(panel.hasInk)
    XCTAssertTrue(panel.results.isEmpty)
    XCTAssertTrue(panel.canvas.strokes.isEmpty)
  }
  func testHandwritingSchemeKeepsToolbarAndSwitchesBackToLetters() throws {
    let previous = InputSchemePreference.scheme
    let enabled = InputSchemePreference.enabledSchemes
    defer { InputSchemePreference.enabledSchemes = enabled; InputSchemePreference.scheme = previous }
    InputSchemePreference.enabledSchemes = ChineseInputScheme.allCases
    InputSchemePreference.scheme = .handwriting
    let controller = KeyboardViewController(); controller.loadViewIfNeeded()
    for width in [320.0, 414.0] {
      controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 260); controller.view.layoutIfNeeded()
      let panel = try XCTUnwrap(nodes(controller.view).first { $0.accessibilityIdentifier == "handwritingInput" } as? HandwritingInputView)
      XCTAssertFalse(panel.isHidden)
      XCTAssertGreaterThan(panel.canvas.bounds.height, 90)
      XCTAssertGreaterThan(panel.canvas.bounds.width, 200)
      let shot = XCTAttachment(image: UIGraphicsImageRenderer(bounds: controller.view.bounds).image { controller.view.layer.render(in: $0.cgContext) }); shot.name = "Handwriting keyboard \(Int(width))"; shot.lifetime = .keepAlways; add(shot)
    }
    let language = try XCTUnwrap(nodes(controller.view).first { $0.accessibilityIdentifier == "bottomLanguageKey" } as? UIButton)
    language.sendActions(for: .primaryActionTriggered)
    XCTAssertTrue(try XCTUnwrap(nodes(controller.view).first { $0.accessibilityIdentifier == "handwritingInput" }).isHidden)
    language.sendActions(for: .primaryActionTriggered)
    XCTAssertFalse(try XCTUnwrap(nodes(controller.view).first { $0.accessibilityIdentifier == "handwritingInput" }).isHidden)
  }
  private func nodes(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(nodes) }
}
