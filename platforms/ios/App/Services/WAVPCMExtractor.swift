import Foundation

/// Extracts the raw payload of a RIFF/WAVE `data` chunk.
///
/// The recorder writes linear PCM in a WAV container, while the Doubao wire
/// format accepts only the PCM payload. This parser deliberately ignores the
/// shape of `fmt ` and any other chunks so it remains valid for WAV files with
/// optional metadata or extended format headers.
enum WAVPCMExtractor {
  static func extract(from wav: Data) -> Data? {
    let bytes = [UInt8](wav)
    guard bytes.count >= 12,
          matches(bytes, at: 0, string: "RIFF"),
          matches(bytes, at: 8, string: "WAVE") else {
      return nil
    }

    let riffSize = UInt64(readUInt32LE(bytes, at: 4))
    guard riffSize >= 4 else { return nil }
    let riffEnd = UInt64(8) + riffSize
    guard riffEnd <= UInt64(bytes.count), riffEnd <= UInt64(Int.max) else { return nil }

    let end = Int(riffEnd)
    var offset = 12
    while offset < end {
      guard end - offset >= 8 else { return nil }
      let chunkSize = UInt64(readUInt32LE(bytes, at: offset + 4))
      let payloadStart = UInt64(offset) + 8
      let payloadEnd = payloadStart + chunkSize
      guard payloadEnd >= payloadStart,
            payloadEnd <= UInt64(end),
            payloadEnd <= UInt64(Int.max) else {
        return nil
      }

      let payloadStartIndex = Int(payloadStart)
      let payloadEndIndex = Int(payloadEnd)
      let next = payloadEnd + (chunkSize & 1)
      guard next > UInt64(offset), next <= UInt64(end), next <= UInt64(Int.max) else {
        return nil
      }
      if matches(bytes, at: offset, string: "data") {
        return Data(bytes[payloadStartIndex..<payloadEndIndex])
      }

      offset = Int(next)
    }
    return nil
  }

  private static func matches(_ bytes: [UInt8], at offset: Int, string: String) -> Bool {
    let signature = Array(string.utf8)
    guard offset >= 0, offset <= bytes.count, signature.count <= bytes.count - offset else { return false }
    return bytes[offset..<(offset + signature.count)].elementsEqual(signature)
  }

  private static func readUInt32LE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
    UInt32(bytes[offset])
      | (UInt32(bytes[offset + 1]) << 8)
      | (UInt32(bytes[offset + 2]) << 16)
      | (UInt32(bytes[offset + 3]) << 24)
  }
}
