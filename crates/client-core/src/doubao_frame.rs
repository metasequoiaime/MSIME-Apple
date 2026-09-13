use flate2::{write::GzEncoder, Compression};
use std::io::Write;

pub fn encode_json_frame(message_type: u8, flags: u8, sequence: i32, payload: &[u8]) -> Vec<u8> {
    let mut gzip = GzEncoder::new(Vec::new(), Compression::default());
    gzip.write_all(payload).expect("gzip write to memory");
    let compressed = gzip.finish().expect("gzip finish");
    let mut frame = Vec::with_capacity(12 + compressed.len());
    frame.extend_from_slice(&[0x11, (message_type << 4) | (flags & 0x0f), 0x11, 0]);
    frame.extend_from_slice(&sequence.to_be_bytes());
    frame.extend_from_slice(&(compressed.len() as i32).to_be_bytes());
    frame.extend_from_slice(&compressed);
    frame
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn encodes_protocol_header_and_gzip_payload() {
        let frame = encode_json_frame(1, 0, 1, b"{}");
        assert_eq!(&frame[..12], &[0x11, 0x10, 0x11, 0, 0, 0, 0, 1, 0, 0, 0, frame[11]]);
        assert!(frame.len() > 12);
        let (last, sequence, payload) = decode_json_frame(&frame).unwrap();
        assert!(!last && sequence == 1 && payload == b"{}");
    }
}

pub fn decode_json_frame(frame: &[u8]) -> Option<(bool, i32, Vec<u8>)> {
    if frame.len() < 12 || (frame[0] & 0x0f) != 1 || frame[2] != 0x11 { return None; }
    let flags = frame[1] & 0x0f;
    let sequence = i32::from_be_bytes(frame[4..8].try_into().ok()?);
    let size = i32::from_be_bytes(frame[8..12].try_into().ok()?) as usize;
    if frame.len() < 12 + size { return None; }
    let mut decoder = flate2::read::GzDecoder::new(&frame[12..12 + size]);
    let mut payload = Vec::new();
    std::io::Read::read_to_end(&mut decoder, &mut payload).ok()?;
    Some(((flags & 0x02) != 0, sequence, payload))
}
