import AppKit
import SwiftUI

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
  var body: some View {
    VStack(spacing: 8) {
      MacInkCanvas(strokes: $strokes).frame(minHeight: 180).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary))
      HStack { Button("撤销") { _ = strokes.popLast() }.disabled(strokes.isEmpty); Button("清空") { strokes.removeAll() }.disabled(strokes.isEmpty); Spacer(); Button("识别") { onSubmit(strokes) }.disabled(strokes.isEmpty) }
    }
  }
}
