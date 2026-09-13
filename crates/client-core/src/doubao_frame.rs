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
        let frame = encode_json_frame(9, 0, 1, b"{}");
        assert_eq!(&frame[..4], &[0x11, 0x90, 0x11, 0]);
        let mut response = frame[..4].to_vec();
        response.extend_from_slice(&frame[8..12]);
        response.extend_from_slice(&frame[12..]);
        let (last, sequence, payload) = decode_json_frame(&response).unwrap();
        assert!(!last && sequence == 0 && payload == b"{}");
        let mut final_response = response.clone();
        final_response[1] |= 2;
        assert!(decode_json_frame(&final_response).unwrap().0);
        let mut invalid = response;
        invalid[2] = 0x10;
        assert!(decode_json_frame(&invalid).is_none());
    }
}

pub fn decode_json_frame(frame: &[u8]) -> Option<(bool, i32, Vec<u8>)> {
    if frame.len() < 8 || (frame[0] & 0x0f) != 1 || (frame[1] >> 4) != 0x09 || frame[2] != 0x11 {
        return None;
    }
    let flags = frame[1] & 0x0f;
    let mut offset = 4usize;
    if flags & 0x01 != 0 {
        offset += 4;
    }
    if flags & 0x04 != 0 {
        offset += 4;
    }
    if offset + 4 > frame.len() {
        return None;
    }
    let size = i32::from_be_bytes(frame[offset..offset + 4].try_into().ok()?) as usize;
    offset += 4;
    if frame.len() < offset + size {
        return None;
    }
    let mut decoder = flate2::read::GzDecoder::new(&frame[offset..offset + size]);
    let mut payload = Vec::new();
    std::io::Read::read_to_end(&mut decoder, &mut payload).ok()?;
    Some(((flags & 0x02) != 0, 0, payload))
}
