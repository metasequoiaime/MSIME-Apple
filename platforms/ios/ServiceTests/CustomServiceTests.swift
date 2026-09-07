import XCTest
import Foundation

final class FixtureProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let denied = request.url?.path == "/denied"
    let data = Data((denied ? "private server detail" : "{\"choices\":[{\"message\":{\"content\":\"润色结果\"}}]}").utf8)
    let response = HTTPURLResponse(url: request.url!, statusCode: denied ? 401 : 200,
                                   httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

final class CustomServiceTests: XCTestCase {
  func testPresetsAreUsableAndKeepSeparateSavedConfigurations() throws {
    let suite = "msime-provider-tests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var custom = CustomServiceConfiguration()
    custom.endpoint = "https://custom.invalid/v1/chat/completions"
    custom.model = "custom-model"
    try custom.save(.ai, token: "", defaults: defaults)
    for provider in AIProviderPreset.allCases where provider != .custom {
      var configuration = CustomServiceConfiguration.loadPreset(provider, defaults: defaults)
      XCTAssertEqual(configuration.provider, provider)
      XCTAssertEqual(try configuration.validatedURL().absoluteString, provider.endpoint)
      XCTAssertNotNil(provider.documentation)
      configuration.model = "my-\(provider.rawValue)-model"
      try configuration.save(.ai, token: "", defaults: defaults)
      XCTAssertEqual(CustomServiceConfiguration.load(.ai, defaults: defaults).provider, provider)
    }
    for provider in AIProviderPreset.allCases where provider != .custom {
      XCTAssertEqual(CustomServiceConfiguration.loadPreset(provider, defaults: defaults).model,
                     "my-\(provider.rawValue)-model")
    }
    XCTAssertEqual(CustomServiceConfiguration.loadPreset(.custom, defaults: defaults).endpoint, custom.endpoint)
    XCTAssertEqual(CustomServiceConfiguration.loadPreset(.custom, defaults: defaults).model, custom.model)
  }

  func testConfigurationRejectsUnsafeOrIncompleteEndpoints() {
    for endpoint in ["http://example.invalid/v1", "https://user:password@example.invalid/v1", "https://example.invalid/v1#fragment", ""] {
      var configuration = CustomServiceConfiguration()
      configuration.endpoint = endpoint
      configuration.model = "fixture"
      XCTAssertThrowsError(try configuration.validatedURL())
    }
    var configuration = CustomServiceConfiguration()
    configuration.endpoint = "https://example.invalid/v1/chat/completions"
    XCTAssertThrowsError(try configuration.validatedURL())
    configuration.model = "fixture"
    XCTAssertEqual(try configuration.validatedURL().path, "/v1/chat/completions")
  }

  func testEngineCodecsPreserveTextAndAudioAndRejectMalformedResponses() throws {
    let text = "你好\n\"测试\""
    let data = try AppServicesBridge.polishBody("fixture", prompt: "润色", text: text)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
    XCTAssertEqual(messages.last?["content"], text)
    let wav = Data([0x52, 0x49, 0x46, 0x46, 0, 255, 17])
    let multipart = try AppServicesBridge.transcriptionBody(wav, model: "asr-fixture")
    let body = try XCTUnwrap(multipart["body"] as? Data)
    XCTAssertNotNil(body.range(of: wav))
    XCTAssertTrue(try XCTUnwrap(multipart["contentType"] as? String).contains("boundary="))
    XCTAssertEqual(try AppServicesBridge.parseResponse(Data("{\"text\":\"语音测试\"}".utf8), voice: true), "语音测试")
    XCTAssertThrowsError(try AppServicesBridge.parseResponse(Data("{\"error\":\"private\"}".utf8), voice: false))
  }

  func testTransportUsesConfiguredEndpointAndReportsHTTPFailure() async throws {
    let session = URLSessionConfiguration.ephemeral
    session.protocolClasses = [FixtureProtocol.self]
    var configuration = CustomServiceConfiguration()
    configuration.endpoint = "https://msime-tests.invalid/success"
    configuration.model = "fixture"
    let result = try await CustomServiceClient.request(kind: .ai, configuration: configuration,
      text: "你好", token: "fixture-token", sessionConfiguration: session)
    XCTAssertEqual(result, "润色结果")
    configuration.endpoint = "https://msime-tests.invalid/denied"
    do {
      _ = try await CustomServiceClient.request(kind: .ai, configuration: configuration,
        text: "你好", token: "fixture-token", sessionConfiguration: session)
      XCTFail("HTTP failure was accepted")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("401"))
      XCTAssertFalse(error.localizedDescription.contains("private server detail"))
    }
  }
}
