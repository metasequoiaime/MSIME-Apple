import XCTest

final class VoiceLevelTests: XCTestCase {
  func testDecibelsMapOntoBarHeights() {
    XCTAssertEqual(VoiceLevel.normalized(decibels: 0), 1)
    XCTAssertEqual(VoiceLevel.normalized(decibels: -25), 0.5, accuracy: 0.001)
    XCTAssertEqual(VoiceLevel.normalized(decibels: -80), 0)
    XCTAssertEqual(VoiceLevel.normalized(decibels: 6), 1, "a clipping reading stays inside the bar")
    // AVAudioRecorder reports -infinity-like values before the first buffer.
    XCTAssertEqual(VoiceLevel.normalized(decibels: -.infinity), 0)
    XCTAssertEqual(VoiceLevel.normalized(decibels: .nan), 0)
  }

  func testPCMLevelIsTheRMSInDecibels() {
    XCTAssertEqual(VoiceLevel.decibels(pcm16: Data()), VoiceLevel.floorDecibels)
    XCTAssertEqual(VoiceLevel.decibels(pcm16: Data(count: 640)), VoiceLevel.floorDecibels)
    // A full-scale square wave has an RMS of 1, which is 0 dBFS.
    var square = Data()
    for index in 0..<320 {
      let sample: Int16 = index.isMultiple(of: 2) ? .max : .min
      withUnsafeBytes(of: sample.littleEndian) { square.append(contentsOf: $0) }
    }
    XCTAssertEqual(VoiceLevel.decibels(pcm16: square), 0, accuracy: 0.01)
    // Half scale is about -6 dB.
    var half = Data()
    for _ in 0..<320 { withUnsafeBytes(of: Int16(16_384).littleEndian) { half.append(contentsOf: $0) } }
    XCTAssertEqual(VoiceLevel.decibels(pcm16: half), -6.02, accuracy: 0.05)
  }

  func testTheWaveformKeepsTheNewestSamples() {
    var levels: [Float] = []
    for step in 0..<30 { levels = VoiceLevel.appending(Float(step), to: levels) }
    XCTAssertEqual(levels.count, VoiceLevel.history)
    XCTAssertEqual(levels.first, 6)
    XCTAssertEqual(levels.last, 29)
  }
}
