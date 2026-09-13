import Foundation

@objc(MSIMEClientSession) final class HandwritingSessionStub: NSObject {
  static var request: NSDictionary?

  @objc class func handwritingProviderRequest(_ request: NSDictionary) -> NSDictionary {
    self.request = request
    return ["candidates": ["synthetic-candidate"]]
  }
}

@main enum HandwritingProviderTest {
  static func main() throws {
    let strokes = [MacInkStroke(points: [CGPoint(x: 10, y: 12), CGPoint(x: 20, y: 24)])]
    let candidates = try MacHandwritingProvider.recognize(strokes, socketPath: "/tmp/synthetic-handwriting.sock")
    assert(candidates == ["synthetic-candidate"])
    let request = HandwritingSessionStub.request!
    assert(request["language"] as? String == "zh-CN")
    let rows = request["strokes"] as? [[NSDictionary]]
    assert(rows?.count == 1 && rows?.first?.count == 2)
    assert((rows?.first?.first?["x"] as? NSNumber)?.floatValue == 10)
    assert((rows?.first?.first?["y"] as? NSNumber)?.floatValue == 12)

    do {
      _ = try MacHandwritingProvider.recognizeLocal([])
      assertionFailure("empty local handwriting input was accepted")
    } catch { }
    print("macOS handwriting provider payload and local-input bounds passed")
  }
}
