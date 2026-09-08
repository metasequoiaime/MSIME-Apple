import XCTest

@MainActor
private final class FakeAppIconClient: AppIconClient {
  var supportsAlternateIcons = true
  var alternateIconName: String?
  var requests: [String?] = []
  var fails = false
  var beforeCompletion: (() async -> Void)?

  func setIcon(_ name: String?) async throws {
    requests.append(name)
    await beforeCompletion?()
    if fails { throw NSError(domain: "IconTest", code: 1) }
    alternateIconName = name
  }
}

final class AppIconSettingsTests: XCTestCase {
  @MainActor
  func testUsesSystemSelectionAndRestoresDefaultWithNil() async {
    let client = FakeAppIconClient()
    client.alternateIconName = "AppIconSky"
    let model = AppIconSettingsModel(client: client)
    XCTAssertEqual(model.selected, .sky)
    await model.select(.classic)
    XCTAssertEqual(client.requests.count, 1)
    XCTAssertNil(client.requests[0])
    XCTAssertEqual(model.selected, .classic)
    XCTAssertNil(model.pending)
  }

  @MainActor
  func testFailureKeepsActualIconAndAllowsRetry() async {
    let client = FakeAppIconClient()
    let model = AppIconSettingsModel(client: client)
    client.fails = true
    await model.select(.forest)
    XCTAssertEqual(model.selected, .classic)
    XCTAssertNotNil(model.errorMessage)
    XCTAssertNil(model.pending)
    client.fails = false
    await model.select(.forest)
    XCTAssertEqual(model.selected, .forest)
    XCTAssertNil(model.errorMessage)
  }

  @MainActor
  func testSuppressesConcurrentAndAlreadySelectedRequests() async {
    let client = FakeAppIconClient()
    let model = AppIconSettingsModel(client: client)
    client.beforeCompletion = {
      XCTAssertEqual(model.pending, .dusk)
      XCTAssertEqual(model.selected, .classic)
      await model.select(.sky)
    }
    await model.select(.dusk)
    await model.select(.dusk)
    XCTAssertEqual(client.requests.count, 1)
    XCTAssertEqual(model.selected, .dusk)
  }

  @MainActor
  func testUnsupportedAndUnknownSystemIcon() async {
    let client = FakeAppIconClient()
    client.supportsAlternateIcons = false
    client.alternateIconName = "FutureIcon"
    let model = AppIconSettingsModel(client: client)
    XCTAssertNil(model.selected)
    await model.select(.forest)
    XCTAssertTrue(client.requests.isEmpty)
    client.alternateIconName = nil
    model.refresh()
    XCTAssertEqual(model.selected, .classic)
  }
}
