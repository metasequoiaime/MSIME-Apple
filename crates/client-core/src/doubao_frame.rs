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
    }
}
