import Foundation
import XCTest

final class WAVPCMExtractorTests: XCTestCase {
  func testExtractsDataAfterExtendedFormatAndPaddedMetadataChunks() {
    let pcm = [UInt8](repeating: 0x2A, count: 6)
    let wav = makeWAV(chunks: [
      chunk("fmt ", Array(repeating: 0, count: 40)),
      chunk("JUNK", [1, 2, 3]),
      chunk("data", pcm),
    ])

    XCTAssertEqual(WAVPCMExtractor.extract(from: wav), Data(pcm))
  }

  func testRejectsMissingDataAndInvalidChunkBounds() {
    let missingData = makeWAV(chunks: [chunk("fmt ", [0, 0])])
    XCTAssertNil(WAVPCMExtractor.extract(from: missingData))

    var malformed = makeWAV(chunks: [chunk("fmt ", [0, 0])])
    malformed.replaceSubrange(16..<20, with: [0xFF, 0xFF, 0xFF, 0x7F])
    XCTAssertNil(WAVPCMExtractor.extract(from: malformed))
  }

  private func chunk(_ id: String, _ payload: [UInt8]) -> [UInt8] {
    var bytes = Array(id.utf8)
    bytes += littleEndian(UInt32(payload.count))
    bytes += payload
    if payload.count % 2 == 1 { bytes.append(0) }
    return bytes
  }

  private func makeWAV(chunks: [[UInt8]]) -> Data {
    let body = chunks.flatMap { $0 }
    var bytes = Array("RIFF".utf8)
    bytes += littleEndian(UInt32(body.count + 4))
    bytes += Array("WAVE".utf8)
    bytes += body
    return Data(bytes)
  }

  private func littleEndian(_ value: UInt32) -> [UInt8] {
    [
      UInt8(value & 0xFF),
      UInt8((value >> 8) & 0xFF),
      UInt8((value >> 16) & 0xFF),
      UInt8((value >> 24) & 0xFF),
    ]
  }
}
