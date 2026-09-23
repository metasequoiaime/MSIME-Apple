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

  private func skinsRoot(_ manifests: [String: String]) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: root) }
    for (id, manifest) in manifests {
      let folder = root.appendingPathComponent(id, isDirectory: true)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try manifest.write(to: folder.appendingPathComponent("skin.toml"), atomically: true, encoding: .utf8)
    }
    return root
  }

  private func manifest(_ id: String, layouts: String = "'horizontal', 'vertical'", themes: String = "'light'",
                        colors: String) -> String {
    """
    schema_version = 1
    id = '\(id)'
    name = 'Sample'
    version = '1.0'
    base = 'wechat'
    [supports]
    layouts = [\(layouts)]
    themes = [\(themes)]
    [candidate_window]
    [candidate_window.decoration]
    [candidate.light]
    \(colors)
    """
  }

  /// An imported skin extends its base with the colours it declares; the user's own overrides still come last.
  func testImportedSkinExtendsItsBase() throws {
    let root = try skinsRoot(["sakura": manifest("sakura", colors: """
      surface = '#fff0f5'
      text = '#112233'
      border = '#ff000080'
      accent = 'pink'
      """)])
    let palette = CandidatePalette.resolve(["candidate_skin": "sakura", "candidate_theme": "light"],
                                           systemDark: false, skinsRoot: root)
    let base = CandidatePalette.builtIn("wechat", dark: false)
    XCTAssertEqual(hex(palette.surface), "#fff0f5")
    XCTAssertEqual(hex(palette.text), "#112233")
    XCTAssertEqual(hex(palette.border), "#ff0000")
    XCTAssertEqual(palette.border.cgColor.alpha, CGFloat(0x80) / 255, accuracy: 0.001)
    XCTAssertEqual(palette.accent, base.accent, "a colour the desktop windows would refuse is ignored")
    XCTAssertEqual(palette.selected, base.selected)

    let overridden = CandidatePalette.resolve(
      ["candidate_skin": "sakura", "candidate_theme": "light", "candidate_surface_color": "#010203"],
      systemDark: false, skinsRoot: root)
    XCTAssertEqual(hex(overridden.surface), "#010203")
  }

  /// A package is drawn only for the horizontal layout and a theme it declares; a folder the catalog rejects is never drawn.
  func testImportedSkinOutsideWhatItSupportsFallsBack() throws {
    let root = try skinsRoot([
      "tall": manifest("tall", layouts: "'vertical'", colors: "surface = '#fff0f5'"),
      "lightonly": manifest("lightonly", colors: "surface = '#fff0f5'"),
      "mismatch": manifest("other", colors: "surface = '#fff0f5'"),
    ])
    let fallbackLight = CandidatePalette.builtIn("willow_green", dark: false)
    XCTAssertEqual(CandidatePalette.resolve(["candidate_skin": "tall", "candidate_theme": "light"],
                                            systemDark: false, skinsRoot: root), fallbackLight)
    XCTAssertEqual(CandidatePalette.resolve(["candidate_skin": "mismatch", "candidate_theme": "light"],
                                            systemDark: false, skinsRoot: root), fallbackLight)
    XCTAssertEqual(CandidatePalette.resolve(["candidate_skin": "lightonly", "candidate_theme": "dark"],
                                            systemDark: false, skinsRoot: root),
                   CandidatePalette.builtIn("willow_green", dark: true))
    XCTAssertEqual(hex(CandidatePalette.resolve(["candidate_skin": "lightonly", "candidate_theme": "light"],
                                                systemDark: false, skinsRoot: root).surface), "#fff0f5")
  }

  /// The native settings app copies a folder picked in Files into the shared root through the Rust import, and can delete it again.
  func testAPickedFolderIsImportedListedAndRemoved() throws {
    let files = try skinsRoot(["sakura": manifest("sakura", colors: "surface = '#fff0f5'")])
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: root) }
    let source = files.appendingPathComponent("sakura", isDirectory: true)
    XCTAssertEqual(try ExternalCandidateSkin.importFolder(source, root: root).get(), "sakura")
    let listed = try XCTUnwrap(ExternalCandidateSkin.scan(root))
    XCTAssertEqual(listed.map(\.id), ["sakura"])
    XCTAssertEqual(listed.first?.skin.name, "Sample")
    XCTAssertEqual(hex(CandidatePalette.resolve(["candidate_skin": "sakura", "candidate_theme": "light"],
                                                systemDark: false, skinsRoot: root).surface), "#fff0f5")

    let bare = files.appendingPathComponent("bare", isDirectory: true)
    try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
    XCTAssertEqual(ExternalCandidateSkin.importFolder(bare, root: root), .failure(.manifest))
    let builtIn = files.appendingPathComponent("fluent", isDirectory: true)
    try FileManager.default.createDirectory(at: builtIn, withIntermediateDirectories: true)
    try "id = 'fluent'".write(to: builtIn.appendingPathComponent("skin.toml"), atomically: true, encoding: .utf8)
    XCTAssertEqual(ExternalCandidateSkin.importFolder(builtIn, root: root), .failure(.name))

    XCTAssertFalse(ExternalCandidateSkin.remove("../sakura", root: root))
    XCTAssertFalse(ExternalCandidateSkin.remove(".hidden", root: root))
    XCTAssertTrue(ExternalCandidateSkin.remove("sakura", root: root))
    XCTAssertEqual(ExternalCandidateSkin.scan(root)?.count, 0)
  }

  func testBorderAcceptsAlphaAndTransparent() {
    XCTAssertEqual(CandidatePalette.borderColor("transparent")?.cgColor.alpha, 0)
    XCTAssertEqual(CandidatePalette.borderColor("#00ff00").map(hex), "#00ff00")
    XCTAssertNil(CandidatePalette.borderColor("#00ff0"))
    XCTAssertNil(CandidatePalette.borderColor("#00ff00zz"))
  }
}
