import UIKit
import XCTest

/// What one keystroke costs inside the extension, key by key.
///
/// The shared runtime answers in well under a millisecond, so anything a person feels as the
/// keyboard falling behind is spent above it — in the view work each key triggers. This measures
/// the controller's own path rather than a mean over a word: dropped frames come from the tail,
/// and a mean hides it behind the many cheap keys around it.
@MainActor
final class KeystrokeLatencyTests: XCTestCase {
  override func setUp() {
    super.setUp()
    enableAllInputSchemes()
  }

  private func controller(_ scheme: ChineseInputScheme, width: CGFloat = 390) -> KeyboardViewController {
    InputSchemePreference.scheme = scheme
    let controller = KeyboardViewController()
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(
      x: 0, y: 0, width: width, height: 260 + KeyboardViewController.stripExtraHeight)
    controller.viewWillAppear(false)
    controller.view.layoutIfNeeded()
    return controller
  }

  private func descendants(_ view: UIView) -> [UIView] {
    [view] + view.subviews.flatMap { descendants($0) }
  }

  private func key(_ label: String, in controller: KeyboardViewController) throws -> UIButton {
    try XCTUnwrap(
      descendants(controller.view).first { $0.accessibilityLabel == label } as? UIButton,
      "no key labelled \(label)")
  }

  private func report(_ label: String, _ samples: [Double]) {
    let sorted = samples.sorted()
    let at = { (q: Double) in sorted[Int((Double(sorted.count - 1) * q).rounded())] }
    let mean = samples.reduce(0, +) / Double(samples.count)
    print(String(
      format: "LATENCY %@ n=%d mean=%.2fms p50=%.2fms p95=%.2fms max=%.2fms",
      label, samples.count, mean, at(0.5), at(0.95), at(1.0)))
  }

  func testWhatOneKeystrokeCosts() throws {
    let previous = InputSchemePreference.scheme
    defer { InputSchemePreference.scheme = previous }

    for scheme in [ChineseInputScheme.quanpin] {
      let controller = self.controller(scheme)
      let labels = scheme == .nineKey
        ? ["九键 6", "九键 4", "九键 4", "九键 2", "九键 6"]
        : ["字母 N", "字母 I", "字母 H", "字母 A", "字母 O"]
      var letters: [Double] = []
      var spaces: [Double] = []
      for _ in 0..<50 {
        for label in labels {
          let button = try key(label, in: controller)
          let started = Date()
          button.sendActions(for: .primaryActionTriggered)
          controller.view.layoutIfNeeded()
          letters.append(Date().timeIntervalSince(started) * 1000)
        }
        let space = try key("空格", in: controller)
        let started = Date()
        space.sendActions(for: .primaryActionTriggered)
        controller.view.layoutIfNeeded()
        spaces.append(Date().timeIntervalSince(started) * 1000)
      }
      report("\(scheme.rawValue)-letter", letters)
      report("\(scheme.rawValue)-space", spaces)
    }
  }
}
