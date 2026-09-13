import Foundation

private typealias MSIMEByte = UInt8

@_silgen_name("msime_client_doubao_decode_frame")
private func msimeClientDoubaoDecodeFrame(_ frame: UnsafePointer<MSIMEByte>?, _ length: UInt) -> UnsafeMutablePointer<CChar>?

@_silgen_name("msime_client_doubao_start_frame")
private func msimeClientDoubaoStartFrame(_ enableITN: Bool, _ enablePunctuation: Bool, _ enableDDC: Bool,
                                         _ boostingTable: UnsafePointer<MSIMEByte>?, _ boostingTableLength: UInt,
                                         _ output: UnsafeMutablePointer<MSIMEByte>?, _ outputCapacity: UInt,
                                         _ outputLength: UnsafeMutablePointer<UInt>?) -> Bool

@_silgen_name("msime_client_doubao_audio_frame")
private func msimeClientDoubaoAudioFrame(_ sequence: Int32, _ pcm: UnsafePointer<MSIMEByte>?, _ pcmLength: UInt,
                                         _ finalChunk: Bool, _ output: UnsafeMutablePointer<MSIMEByte>?,
                                         _ outputCapacity: UInt, _ outputLength: UnsafeMutablePointer<UInt>?) -> Bool

@_silgen_name("msime_client_string_free")
private func msimeClientStringFree(_ value: UnsafeMutablePointer<CChar>?)

/// Swift closures over the host-api Doubao C ABI. The frame layout stays in
/// client-core; this adapter only owns pointer lifetime and response JSON
/// extraction for the iOS transport coordinator.
enum DoubaoHostFrameCodec {
  enum Failure: Error { case startFrame, audioFrame }

  static func make(enableITN: Bool, punctuation: Bool, DDC: Bool,
                   boostingTable: String) -> DoubaoVoiceCoordinator.FrameCodec {
    DoubaoVoiceCoordinator.FrameCodec(
      startFrame: {
        try startFrame(enableITN: enableITN, punctuation: punctuation, DDC: DDC,
                        boostingTable: boostingTable)
      },
      audioFrame: { sequence, pcm, final in
        try audioFrame(sequence: sequence, pcm: Data(pcm), final: final)
      },
      decodeFrame: decodeFrame
    )
  }

  private static func startFrame(enableITN: Bool, punctuation: Bool, DDC: Bool,
                                 boostingTable: String) throws -> Data {
    let table = Data(boostingTable.utf8)
    var output = Data(count: 1_048_576)
    var written: UInt = 0
    let ok = output.withUnsafeMutableBytes { outputBytes in
      table.withUnsafeBytes { tableBytes in
        msimeClientDoubaoStartFrame(
          enableITN, punctuation, DDC,
          tableBytes.bindMemory(to: MSIMEByte.self).baseAddress, UInt(table.count),
          outputBytes.bindMemory(to: MSIMEByte.self).baseAddress, UInt(output.count), &written)
      }
    }
    guard ok, written <= UInt(output.count) else { throw Failure.startFrame }
    output.removeSubrange(Int(written)..<output.count)
    return output
  }

  private static func audioFrame(sequence: Int32, pcm: Data, final: Bool) throws -> Data {
    var output = Data(count: pcm.count + 65_536)
    var written: UInt = 0
    let ok = output.withUnsafeMutableBytes { outputBytes in
      pcm.withUnsafeBytes { pcmBytes in
        msimeClientDoubaoAudioFrame(
          sequence, pcmBytes.bindMemory(to: MSIMEByte.self).baseAddress, UInt(pcm.count), final,
          outputBytes.bindMemory(to: MSIMEByte.self).baseAddress, UInt(output.count), &written)
      }
    }
    guard ok, written <= UInt(output.count) else { throw Failure.audioFrame }
    output.removeSubrange(Int(written)..<output.count)
    return output
  }

  private static func decodeFrame(_ frame: Data) -> (isFinal: Bool, text: String?)? {
    let raw: UnsafeMutablePointer<CChar>? = frame.withUnsafeBytes { bytes in
      msimeClientDoubaoDecodeFrame(bytes.bindMemory(to: MSIMEByte.self).baseAddress, UInt(frame.count))
    }
    guard let raw else { return nil }
    defer { msimeClientStringFree(raw) }
    guard let data = String(cString: raw).data(using: .utf8),
          let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    guard let ok = envelope["ok"] as? Bool, ok,
          let value = envelope["value"] as? [String: Any]
    else { return (true, nil) }
    if value["error_code"] != nil { return (true, nil) }
    let isFinal = value["last"] as? Bool ?? false
    guard let payload = value["payload"] as? String,
          let payloadData = payload.data(using: .utf8),
          let body = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
    else { return (isFinal, nil) }
    let result = body["result"] as? [String: Any]
    let text = (result?["text"] as? String) ?? (body["text"] as? String)
    return (isFinal, text)
  }
}
