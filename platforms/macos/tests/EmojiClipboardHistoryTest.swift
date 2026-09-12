import Foundation

@objc(MSIMEClientSession) final class HistorySessionStub: NSObject {
  @objc class func enableClipboardHistoryRequest(_ directory: String) -> NSDictionary {
    directory == "/synthetic-state" ? ["enabled": true] : ["error": true]
  }
  @objc class func removeClipboardHistoryRequest(_ request: NSDictionary) -> NSDictionary {
    precondition(request["directory"] as? String == "/synthetic-state")
    switch request["text"] as? String {
    case "synthetic present": return ["removed": true]
    case "synthetic absent": return ["removed": false]
    case "synthetic malformed": return ["removed": 1]
    default: return ["error": true]
    }
  }
  @objc class func clipboardHistoryRequest(_ directory: String) -> NSDictionary {
    return ["enabled": true, "entries": ["Synthetic Alpha", "synthetic beta"]]
  }
}

@main struct EmojiClipboardHistoryTest {
  static func main() throws {
    try MacEmojiClipboardHistory.enable(directory: "/synthetic-state")
    for directory in ["relative", "/synthetic-error"] {
      do { try MacEmojiClipboardHistory.enable(directory: directory); preconditionFailure("invalid enable accepted") }
      catch { }
    }
    let removed = try MacEmojiClipboardHistory.remove(directory: "/synthetic-state", text: "synthetic present")
    precondition(removed)
    let absent = try MacEmojiClipboardHistory.remove(directory: "/synthetic-state", text: "synthetic absent")
    precondition(!absent)
    for text in ["", String(repeating: "界", count: 1366), "synthetic malformed", "synthetic error"] {
      do { _ = try MacEmojiClipboardHistory.remove(directory: "/synthetic-state", text: text); preconditionFailure("invalid removal accepted") }
      catch { }
    }
    let history = try MacEmojiClipboardHistory.load(directory: "/synthetic-state")
    precondition(history.enabled && history.entries.count == 2)
    precondition(history.matching("ALPHA").map(\.text) == ["Synthetic Alpha"])
    precondition(history.matching("missing").isEmpty)
    precondition(history.matching("").count == 2)
    let disabled = try MacEmojiClipboardHistory.decode(["enabled": false, "entries": []])
    precondition(!disabled.enabled && disabled.matching("").isEmpty)
    let invalid: [NSDictionary] = [
      [:], ["enabled": true], ["enabled": 1, "entries": []],
      ["enabled": false, "entries": ["synthetic"]],
      ["enabled": true, "entries": [""]],
      ["enabled": true, "entries": ["synthetic", "synthetic"]],
      ["enabled": true, "entries": [String(repeating: "界", count: 1366)]],
      ["enabled": true, "entries": (0..<51).map { "synthetic-\($0)" }],
      ["enabled": true, "entries": [], "error": true]
    ]
    for response in invalid {
      do { _ = try MacEmojiClipboardHistory.decode(response); preconditionFailure("invalid history accepted") }
      catch { }
    }
    do { _ = try MacEmojiClipboardHistory.load(directory: "relative"); preconditionFailure("relative path accepted") }
    catch { }
    print("Clipboard history decoder, search and adapter tests passed")
  }
}
