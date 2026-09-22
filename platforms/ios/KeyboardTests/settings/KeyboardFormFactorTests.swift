import XCTest
import UIKit

/// iPhone 与 iPad 键盘的区分。
///
/// iPad 不等于平板键盘:浮动键盘和窄窗口是 compact 宽度,系统键盘在那里也画手机布局,这个键盘要跟着同一条规则走。
final class KeyboardFormFactorTests: XCTestCase {
  func testOnlyARegularWidthIPadGetsTheTabletKeyboard() {
    XCTAssertEqual(KeyboardFormFactor.resolve(idiom: .pad, horizontalSizeClass: .regular), .tablet)
    XCTAssertEqual(KeyboardFormFactor.resolve(idiom: .pad, horizontalSizeClass: .unspecified), .tablet)
    XCTAssertEqual(KeyboardFormFactor.resolve(idiom: .pad, horizontalSizeClass: .compact), .phone)
    XCTAssertEqual(KeyboardFormFactor.resolve(idiom: .phone, horizontalSizeClass: .regular), .phone)
    XCTAssertEqual(KeyboardFormFactor.resolve(idiom: .phone, horizontalSizeClass: .compact), .phone)
  }

  /// 手机高度保持原值;平板更高,而且横屏比竖屏高,与系统键盘一致。
  func testHeights() {
    XCTAssertEqual(KeyboardFormFactor.phone.baseHeight(landscape: false, handwriting: false), 260)
    XCTAssertEqual(KeyboardFormFactor.phone.baseHeight(landscape: false, handwriting: true), 260)
    XCTAssertEqual(KeyboardFormFactor.phone.baseHeight(landscape: true, handwriting: false), 216)
    XCTAssertEqual(KeyboardFormFactor.phone.baseHeight(landscape: true, handwriting: true), 240)
    let portrait = KeyboardFormFactor.tablet.baseHeight(landscape: false, handwriting: false)
    let landscape = KeyboardFormFactor.tablet.baseHeight(landscape: true, handwriting: false)
    XCTAssertGreaterThan(portrait, 260)
    XCTAssertGreaterThan(landscape, portrait)
  }

  /// 手机上第三排没有逗号句号;平板上有,并且中文模式下键面是中文标点。
  func testTabletLetterRowCarriesCommaAndFullStop() throws {
    let phone = KeyboardViewController()
    phone.loadViewIfNeeded()
    phone.view.frame = CGRect(x: 0, y: 0, width: 440, height: 292)
    phone.view.layoutIfNeeded()
    XCTAssertTrue(try key("letterRowCommaKey", in: phone).isHidden)
    XCTAssertTrue(try key("letterRowPeriodKey", in: phone).isHidden)

    let tablet = KeyboardViewController()
    tablet.traitOverrides.userInterfaceIdiom = .pad
    tablet.traitOverrides.horizontalSizeClass = .regular
    tablet.loadViewIfNeeded()
    tablet.view.frame = CGRect(x: 0, y: 0, width: 1032, height: 380)
    tablet.view.layoutIfNeeded()
    let comma = try key("letterRowCommaKey", in: tablet)
    XCTAssertFalse(comma.isHidden)
    XCTAssertFalse(try key("letterRowPeriodKey", in: tablet).isHidden)
    XCTAssertEqual(comma.configuration?.title, "，")

    let phoneHeight = try XCTUnwrap(phone.view.constraints.first { $0.identifier == "keyboardHeight" }).constant
    let tabletHeight = try XCTUnwrap(tablet.view.constraints.first { $0.identifier == "keyboardHeight" }).constant
    XCTAssertGreaterThan(tabletHeight, phoneHeight)
  }

  private func key(_ identifier: String, in controller: KeyboardViewController) throws -> UIButton {
    try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == identifier } as? UIButton)
  }

  private func descendants(_ view: UIView) -> [UIView] {
    [view] + view.subviews.flatMap { descendants($0) }
  }
}
