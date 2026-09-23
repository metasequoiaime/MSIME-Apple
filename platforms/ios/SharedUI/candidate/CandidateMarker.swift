import Foundation

/// A small glyph drawn after a candidate: where it came from, and whether the user pinned it.
///
/// The Windows candidate window appends ☁️ to a cloud candidate and 🤖 to an AI one (`event_listener.cpp`), and draws a pinned word in its accent colour. iOS asks the user to opt in before either network source runs, so a suggestion that came back from Google or a language model should not look like a dictionary word. Symbols stand in for the emoji so the glyph takes the skin's colour, and each one carries a spoken form because a colour or icon alone says nothing to VoiceOver.
struct CandidateMarker: Equatable {
  let symbol: String
  let spoken: String

  /// Engine `CandidateSource` values, shared by every host through the runtime's view.
  static let cloudSource = 2
  static let aiSource = 3

  static func markers(source: Int, fixedPosition: Int) -> [CandidateMarker] {
    var markers: [CandidateMarker] = []
    if source == cloudSource { markers.append(CandidateMarker(symbol: "cloud", spoken: "云候选")) }
    if source == aiSource { markers.append(CandidateMarker(symbol: "sparkles", spoken: "AI 候选")) }
    if fixedPosition > 0 {
      markers.append(CandidateMarker(symbol: "pin.fill", spoken: "已固定第 \(fixedPosition) 位"))
    }
    return markers
  }
}
