import XCTest

// InputSchemePreference.scheme silently substitutes enabledSchemes[0] for a scheme the user has
// hidden, so a test that assigns a scheme without first enabling it gets whatever the simulator
// happened to have left in the app group. That state outlives a test bundle: a UI test that hides
// a scheme and fails before restoring it turned every nine-key assertion in this target red on CI
// while the same commit stayed green locally. Tests that depend on a scheme claim the whole set.
extension XCTestCase {
  func enableAllInputSchemes() {
    let previous = InputSchemePreference.enabledSchemes
    InputSchemePreference.enabledSchemes = ChineseInputScheme.allCases
    addTeardownBlock { InputSchemePreference.enabledSchemes = previous }
  }
}
