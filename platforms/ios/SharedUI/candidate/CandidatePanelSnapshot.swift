import Foundation

/// A bounded, generation-stable copy of every candidate used by expanded keyboard panels.
struct CandidatePanelSnapshot: Equatable, Sendable {
  struct Entry: Equatable, Sendable {
    let text: String
    let code: String
    let translation: String
    /// The Engine's display suffix: a helpcode, or the spelling a correction replaced.
    var annotation = ""
    let index: UInt64
  }

  let generation: UInt64
  let preedit: String
  let entries: [Entry]

  enum Failure: Error {
    case invalidResponse
  }

  static func decode(_ value: [String: Any]) throws -> CandidatePanelSnapshot {
    guard let generationValue = value["generation"] as? NSNumber,
          generationValue.int64Value >= 0,
          let preedit = value["preedit"] as? String, bounded(preedit),
          let candidates = value["candidates"] as? [[String: Any]],
          candidates.count <= 4096 else { throw Failure.invalidResponse }
    let generation = generationValue.uint64Value
    var seen = Set<UInt64>()
    let entries = try candidates.map { candidate -> Entry in
      guard let text = candidate["text"] as? String, !text.isEmpty, bounded(text),
            let identity = candidate["id"] as? [String: Any],
            let identityGeneration = identity["generation"] as? NSNumber,
            identityGeneration.int64Value >= 0,
            identityGeneration.uint64Value == generation,
            let indexValue = identity["index"] as? NSNumber,
            indexValue.int64Value >= 0 else { throw Failure.invalidResponse }
      let index = indexValue.uint64Value
      guard index < UInt64(candidates.count), seen.insert(index).inserted else {
        throw Failure.invalidResponse
      }
      let code = candidate["code"] as? String ?? ""
      let translation = candidate["translation"] as? String ?? ""
      let annotation = candidate["annotation"] as? String ?? ""
      guard code.utf8.count <= WubiCodeHintPreference.maxCodeLength,
            bounded(translation), bounded(annotation) else { throw Failure.invalidResponse }
      return Entry(text: text, code: code, translation: translation, annotation: annotation, index: index)
    }
    return CandidatePanelSnapshot(generation: generation, preedit: preedit, entries: entries)
  }

  private static func bounded(_ value: String) -> Bool {
    value.utf8.count <= CandidateGlossModel.maxEntryBytes
  }
}
