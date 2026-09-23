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
    // 数字行是整整一排键，平板加一排的高度而不是压扁字母；手机不带数字行。
    XCTAssertGreaterThan(KeyboardFormFactor.tablet.baseHeight(landscape: false, handwriting: false, numberRow: true), portrait + 40)
    XCTAssertGreaterThan(KeyboardFormFactor.tablet.baseHeight(landscape: true, handwriting: false, numberRow: true), landscape + 40)
    XCTAssertTrue(KeyboardFormFactor.tablet.canShowFullKeys)
    XCTAssertFalse(KeyboardFormFactor.phone.canShowFullKeys)
  }

  /// iPad 全尺寸键盘有数字行和 Tab 键，可以在设置里关掉；手机（以及 iPad 的窄键盘）始终没有。
  func testTabletCarriesTheDigitRowAndTabUnlessTurnedOff() throws {
    let stored = KeyboardLayoutPreference.defaults.object(forKey: KeyboardLayoutPreference.tabletFullKeysKey)
    defer { KeyboardLayoutPreference.defaults.set(stored, forKey: KeyboardLayoutPreference.tabletFullKeysKey) }
    KeyboardLayoutPreference.defaults.removeObject(forKey: KeyboardLayoutPreference.tabletFullKeysKey)
    XCTAssertTrue(KeyboardLayoutPreference.tabletFullKeys, "on by default")

    let phone = KeyboardViewController()
    phone.loadViewIfNeeded()
    phone.view.frame = CGRect(x: 0, y: 0, width: 440, height: 292)
    phone.view.layoutIfNeeded()
    XCTAssertTrue(try view("numberRow", in: phone).isHidden)
    XCTAssertTrue(try key("tabKey", in: phone).isHidden)

    let tablet = tabletController()
    let numberRow = try view("numberRow", in: tablet)
    XCTAssertFalse(numberRow.isHidden)
    XCTAssertFalse(try key("tabKey", in: tablet).isHidden)
    XCTAssertEqual(try key("numberRowKey0", in: tablet).configuration?.title, "0")
    let tab = try key("tabKey", in: tablet)
    let firstRow = try XCTUnwrap(tab.superview as? UIStackView)
    XCTAssertEqual(firstRow.arrangedSubviews.first, tab, "Tab comes before Q")
    XCTAssertGreaterThan(tab.bounds.width, firstRow.arrangedSubviews[1].bounds.width * 1.3)
    let withRow = try XCTUnwrap(tablet.view.constraints.first { $0.identifier == "keyboardHeight" }).constant

    KeyboardLayoutPreference.tabletFullKeys = false
    let plain = tabletController()
    XCTAssertTrue(try view("numberRow", in: plain).isHidden)
    XCTAssertTrue(try key("tabKey", in: plain).isHidden)
    let withoutRow = try XCTUnwrap(plain.view.constraints.first { $0.identifier == "keyboardHeight" }).constant
    XCTAssertGreaterThan(withRow, withoutRow)
  }

  /// Tab 在组字时对应桌面端的 `navigation.tab` 翻页，默认开。
  func testTabFollowsTheSharedPagingSwitch() {
    XCTAssertTrue(KeyboardViewController.tabShowsMoreCandidates(nil))
    XCTAssertTrue(KeyboardViewController.tabShowsMoreCandidates(["navigation": ["tab": true]]))
    XCTAssertFalse(KeyboardViewController.tabShowsMoreCandidates(["navigation": ["tab": false]]))
  }

  /// The App's iPad switch writes `navigation.tab` and leaves the other paging keys where they were.
  func testTheIPadSwitchWritesOnlyTheTabPagingKey() throws {
    let state = FileManager.default.temporaryDirectory
      .appendingPathComponent("msime-tab-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: state) }
    _ = MetasequoiaInputSessionBridge(stateRoot: state)
    let before = try XCTUnwrap(MetasequoiaInputSessionBridge.loadSharedPreferences(stateRoot: state)?["navigation"] as? [String: Any])

    XCTAssertTrue(KeyboardLayoutPreference.saveTabShowsMoreCandidates(false, stateRoot: state))
    let stored = MetasequoiaInputSessionBridge.loadSharedPreferences(stateRoot: state)
    XCTAssertFalse(KeyboardLayoutPreference.tabShowsMoreCandidates(stored))
    let after = try XCTUnwrap(stored?["navigation"] as? [String: Any])
    XCTAssertEqual(Set(after.keys), Set(before.keys))
    for (name, value) in before where name != "tab" {
      XCTAssertEqual(after[name] as? NSObject, value as? NSObject, name)
    }
  }

  private func tabletController() -> KeyboardViewController {
    let tablet = KeyboardViewController()
    tablet.traitOverrides.userInterfaceIdiom = .pad
    tablet.traitOverrides.horizontalSizeClass = .regular
    tablet.loadViewIfNeeded()
    tablet.view.frame = CGRect(x: 0, y: 0, width: 1032, height: 440)
    tablet.view.layoutIfNeeded()
    return tablet
  }

  private func view(_ identifier: String, in controller: KeyboardViewController) throws -> UIView {
    try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == identifier })
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
