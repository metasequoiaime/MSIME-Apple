import XCTest

/// The strip's desktop candidate palette resolves skin, theme and colour overrides the way Android does, and stays off until the iOS switch is on.
final class CandidatePaletteTests: XCTestCase {
  override func tearDown() {
    CandidatePalette.defaults.removeObject(forKey: CandidatePalette.followsDesktopKey)
    super.tearDown()
  }

  private func hex(_ color: UIColor) -> String { CandidatePalette.hex(color) }

  /// The keyboard skin keeps the strip until the switch is on, whatever skin the shared document names.
  func testFollowsTheKeyboardSkinUntilSwitchedOn() {
    CandidatePalette.defaults.set(false, forKey: CandidatePalette.followsDesktopKey)
    XCTAssertNil(CandidatePalette.active(in: ["candidate_skin": "wechat"], systemDark: false))
    CandidatePalette.defaults.set(true, forKey: CandidatePalette.followsDesktopKey)
    XCTAssertEqual(CandidatePalette.active(in: ["candidate_skin": "wechat"], systemDark: false),
                   CandidatePalette.builtIn("wechat", dark: false))
  }

  /// `candidate_theme` wins, then the global `theme`, then the system.
  func testThemeResolutionOrder() {
    XCTAssertTrue(CandidatePalette.isDark(candidateTheme: "dark", globalTheme: "light", systemDark: false))
    XCTAssertFalse(CandidatePalette.isDark(candidateTheme: "light", globalTheme: "dark", systemDark: true))
    XCTAssertTrue(CandidatePalette.isDark(candidateTheme: "follow", globalTheme: "dark", systemDark: false))
    XCTAssertFalse(CandidatePalette.isDark(candidateTheme: "follow", globalTheme: "system", systemDark: false))
    XCTAssertTrue(CandidatePalette.isDark(candidateTheme: nil, globalTheme: nil, systemDark: true))
  }

  /// An unknown or external skin id falls back to the shared default rather than to no colours.
  func testUnknownSkinFallsBackToWillowGreen() {
    XCTAssertEqual(CandidatePalette.resolve(["candidate_skin": "someone.external"], systemDark: true),
                   CandidatePalette.builtIn("willow_green", dark: true))
    XCTAssertEqual(hex(CandidatePalette.builtIn("willow_green", dark: false).surface), "#f4f5f3")
    XCTAssertEqual(hex(CandidatePalette.builtIn("wechat", dark: true).selected), "#07c160")
  }

  /// A custom text colour sets the number colour to itself half-transparent, unless the number colour is set as well.
  func testTextOverrideDerivesTheNumberColour() {
    let derived = CandidatePalette.resolve(["candidate_text_color": "#112233"], systemDark: false)
    XCTAssertEqual(hex(derived.text), "#112233")
    XCTAssertEqual(hex(derived.number), "#112233")
    XCTAssertEqual(derived.number.cgColor.alpha, CGFloat(0x9d) / 255, accuracy: 0.001)

    let explicit = CandidatePalette.resolve(["candidate_text_color": "#112233", "candidate_number_color": "#445566"],
                                            systemDark: false)
    XCTAssertEqual(hex(explicit.number), "#445566")
    XCTAssertEqual(explicit.number.cgColor.alpha, 1)
  }

  /// Linux's `candidate_background_color` outranks `candidate_surface_color`; malformed colours are ignored.
  func testSurfaceOverridesAndMalformedColours() {
    let both = CandidatePalette.resolve(["candidate_background_color": "#010203", "candidate_surface_color": "#040506"],
                                        systemDark: false)
    XCTAssertEqual(hex(both.surface), "#010203")
    XCTAssertEqual(hex(CandidatePalette.resolve(["candidate_surface_color": "#040506"], systemDark: false).surface), "#040506")

    let fallback = CandidatePalette.builtIn("willow_green", dark: false)
    for bad in ["#12345", "123456", "#12345g", "#1234567", ""] {
      XCTAssertEqual(CandidatePalette.resolve(["candidate_hover_color": bad], systemDark: false), fallback, bad)
    }
  }

  /// What the App's colour picker writes reads back as the same colour.
  func testHexRoundTrip() throws {
    let color = try XCTUnwrap(CandidatePalette.color(hex: "#A0b1C2"))
    XCTAssertEqual(CandidatePalette.hex(color), "#a0b1c2")
  }
}
