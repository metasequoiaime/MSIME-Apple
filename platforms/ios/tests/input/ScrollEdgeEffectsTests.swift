import XCTest
import UIKit

final class ScrollEdgeEffectsTests: XCTestCase {
  func testUIKitHelperHidesEveryIOS26EdgeEffect() throws {
    guard #available(iOS 26.0, *) else { throw XCTSkip("Edge effects require iOS 26") }
    let scrollView = UIScrollView()

    scrollView.disableEdgeEffects()

    XCTAssertTrue(scrollView.topEdgeEffect.isHidden)
    XCTAssertTrue(scrollView.bottomEdgeEffect.isHidden)
    XCTAssertTrue(scrollView.leftEdgeEffect.isHidden)
    XCTAssertTrue(scrollView.rightEdgeEffect.isHidden)
  }
}
