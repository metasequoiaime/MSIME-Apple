import AppKit
import SwiftUI

enum MacHandwritingProvider {
  static func recognize(_ strokes: [MacInkStroke], language: String = "zh-CN", socketPath: String) throws -> [String] {
    let payload: [[String: Any]] = strokes.map { ["points": $0.points.map { ["x": Float($0.x), "y": Float($0.y)] }] }
    let request: NSDictionary = ["language": language, "strokes": payload, "socket_path": socketPath]
    guard let type = NSClassFromString("MSIMEClientSession") as? NSObject.Type,
          let result = type.perform(NSSelectorFromString("handwritingProviderRequest:"), with: request)?.takeUnretainedValue() as? NSDictionary else { throw NSError(domain: "MSIMEHandwriting", code: 503) }
    if let error = result["error"] as? NSError { throw error }
    return (result["candidates"] as? [String]) ?? []
  }
}

struct MacInkStroke: Identifiable {
  let id = UUID()
  var points: [CGPoint]
}

private struct MacInkCanvas: NSViewRepresentable {
  @Binding var strokes: [MacInkStroke]
  func makeNSView(context: Context) -> CanvasView { let view = CanvasView(); view.onChange = { strokes = $0 }; return view }
  func updateNSView(_ view: CanvasView, context: Context) { view.strokes = strokes; view.needsDisplay = true }
  final class CanvasView: NSView {
    var strokes: [MacInkStroke] = []
    var onChange: (([MacInkStroke]) -> Void)?
    private var active: [CGPoint] = []
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
      NSColor.controlBackgroundColor.setFill(); dirtyRect.fill()
      NSColor.labelColor.setStroke()
      for stroke in strokes + (active.isEmpty ? [] : [MacInkStroke(points: active)]) {
        guard stroke.points.count > 1 else { continue }
        let path = NSBezierPath(); path.lineWidth = 3; path.lineCapStyle = .round
        path.move(to: stroke.points[0]); for point in stroke.points.dropFirst() { path.line(to: point) }; path.stroke()
      }
    }
    override func mouseDown(with event: NSEvent) { active = [convert(event.locationInWindow, from: nil)]; needsDisplay = true }
    override func mouseDragged(with event: NSEvent) { active.append(convert(event.locationInWindow, from: nil)); needsDisplay = true }
    override func mouseUp(with event: NSEvent) { active.append(convert(event.locationInWindow, from: nil)); if active.count > 1 { strokes.append(MacInkStroke(points: active)); onChange?(strokes) }; active = []; needsDisplay = true }
  }
}

struct MacHandwritingCanvasView: View {
  @Binding var strokes: [MacInkStroke]
  var onSubmit: ([MacInkStroke]) -> Void
  var candidates: [String] = []
  var onCandidate: (String) -> Void = { _ in }
  var body: some View {
    VStack(spacing: 8) {
      MacInkCanvas(strokes: $strokes).frame(minHeight: 180).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary))
      if !candidates.isEmpty { ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(candidates, id: \.self) { candidate in Button(candidate) { onCandidate(candidate) }.buttonStyle(.bordered) } } } }
      HStack { Button("撤销") { _ = strokes.popLast() }.disabled(strokes.isEmpty); Button("清空") { strokes.removeAll() }.disabled(strokes.isEmpty); Spacer(); Button("识别") { onSubmit(strokes) }.disabled(strokes.isEmpty) }
    }
  }
}

struct MacHandwritingToolView: View {
  @State private var strokes: [MacInkStroke] = []
  @State private var candidates: [String] = []
  @State private var socketPath = ""
  @State private var message: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("手写输入").font(.title2)
      TextField("provider socket 路径", text: $socketPath)
      MacHandwritingCanvasView(strokes: $strokes, onSubmit: { ink in
        do { candidates = try MacHandwritingProvider.recognize(ink, socketPath: socketPath) ; message = nil }
        catch { candidates = []; message = error.localizedDescription }
      }, candidates: candidates)
      if let message { Text(message).foregroundStyle(.secondary) }
    }.padding(20).frame(width: 560, height: 360)
  }
}
