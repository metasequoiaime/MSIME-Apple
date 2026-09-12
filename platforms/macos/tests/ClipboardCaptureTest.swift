import AppKit

@MainActor private final class FakeClipboard: MacClipboardSource {
  var changeCount = 0
  var types: [NSPasteboard.PasteboardType]? = [.string]
  var value: String? = "synthetic initial"
  var reads = 0
  var changeWhileReading = false
  func text() -> String? {
    reads += 1
    if changeWhileReading { changeCount += 1 }
    return value
  }
}

@main enum ClipboardCaptureTest {
  @MainActor static func main() {
    let source = FakeClipboard()
    let capture = MacClipboardCapture(source: source)
    assert(capture.sample(enabled: false) == nil && source.reads == 0)
    assert(capture.sample(enabled: true) == nil && source.reads == 0)
    source.changeCount += 1
    source.value = "synthetic changed\nline\tvalue"
    let first = capture.sample(enabled: true)!
    assert(first.text == source.value)
    assert(capture.sample(enabled: true) != nil, "failed saves must remain retryable")
    capture.acknowledge(first)
    let reads = source.reads
    assert(capture.sample(enabled: true) == nil && source.reads == reads)
    for marker in MacClipboardCapture.excludedTypes {
      source.changeCount += 1
      source.types = [.string, NSPasteboard.PasteboardType(marker)]
      assert(capture.sample(enabled: true) == nil && source.reads == reads)
    }
    source.types = [.string]
    for invalid in ["", "synthetic\0invalid", String(repeating: "界", count: 1366)] {
      source.changeCount += 1
      source.value = invalid
      assert(capture.sample(enabled: true) == nil)
    }
    source.changeCount += 1
    source.value = "synthetic race"
    source.changeWhileReading = true
    assert(capture.sample(enabled: true) == nil)
    source.changeWhileReading = false
    let pending = capture.sample(enabled: true)!
    assert(capture.sample(enabled: false) == nil)
    source.changeCount += 1
    assert(capture.sample(enabled: true) == nil)
    capture.acknowledge(pending)
    assert(capture.sample(enabled: true) == nil, "old acknowledgement must not undo restart baseline")

    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    board.setString("synthetic existing", forType: .string)
    let native = MacClipboardCapture(source: MacPasteboardSource(pasteboard: board))
    assert(native.sample(enabled: true) == nil)
    board.clearContents()
    board.setString("synthetic native change", forType: .string)
    let sample = native.sample(enabled: true)!
    assert(sample.text == "synthetic native change")
    native.acknowledge(sample)
    assert(native.sample(enabled: true) == nil)
    board.clearContents()
    board.setString("synthetic marked", forType: .string)
    board.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
    assert(native.sample(enabled: true) == nil)
    print("Clipboard sampling baseline, filters, retry, race, restart and isolated pasteboard tests passed")
  }
}
