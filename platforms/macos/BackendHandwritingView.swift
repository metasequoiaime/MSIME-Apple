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
  var onCandidate: (String) -> Void = { text in NotificationCenter.default.post(name: .msimeHandwritingCandidateSelected, object: nil, userInfo: ["text": text]) }
  var body: some View {
    VStack(spacing: 8) {
      MacInkCanvas(strokes: $strokes).frame(minHeight: 180).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary))
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
        ForEach(candidates, id: \.self) { candidate in
          Button(candidate) { onCandidate(candidate) }.font(.system(size: 24)).frame(maxWidth: .infinity, minHeight: 52)
        }
      }
      HStack { Button("↶  撤销") { _ = strokes.popLast(); onSubmit(strokes) }.disabled(strokes.isEmpty); Button("×  重写") { strokes.removeAll(); onSubmit([]) }.disabled(strokes.isEmpty); Spacer() }
    }
  }
}

extension Notification.Name { static let msimeHandwritingCandidateSelected = Notification.Name("MSIMEHandwritingCandidateSelected") }

/// Own the window's presentation state separately from the reusable ink canvas.
struct MacHandwritingToolView: View {
  @State private var strokes: [MacInkStroke] = []
  @State private var candidates: [String] = []
  @State private var socketPath = ""
  @State private var message: String?
  @State private var busy = false
  @State private var pending: Task<Void, Never>?
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("水杉手写识别板").font(.headline)
      TextField("provider socket 路径", text: $socketPath).disabled(busy)
      MacHandwritingCanvasView(strokes: $strokes, onSubmit: recognize, candidates: candidates)
        .disabled(busy)
      if busy { ProgressView("正在识别…") }
      if let message { Text(message).foregroundStyle(.secondary) }
    }.padding(20).frame(width: 640, height: 460)
    .onChange(of: strokes.count) { _ in candidates = []; if !strokes.isEmpty { recognize(strokes) } }
    .onChange(of: socketPath) { _ in candidates = []; message = nil }
    .onDisappear { pending?.cancel(); pending = nil; candidates = []; strokes = [] }
  }
  private func recognize(_ ink: [MacInkStroke]) {
    guard !busy else { return }
    busy = true; candidates = []; message = nil
    let path = socketPath
    pending = Task { @MainActor in
      defer { busy = false }
      do {
        let work = Task.detached(priority: .userInitiated) {
          try MacHandwritingProvider.recognize(ink, socketPath: path)
        }
        let result = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
        try Task.checkCancellation()
        candidates = result
        if result.isEmpty { message = "没有识别到候选，请重新书写。" }
      } catch {
        if !Task.isCancelled { message = error.localizedDescription }
      }
    }
  }
}
