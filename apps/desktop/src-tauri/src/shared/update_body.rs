use std::io::{self, Read};

const MAX_MANIFEST_BYTES: usize = 64 * 1024;

/// Read one extra byte to distinguish an exact-limit response from truncation.
/// This also bounds streams without a trustworthy Content-Length header.
pub(crate) fn read_manifest(reader: impl Read) -> io::Result<Vec<u8>> {
    let mut bytes = Vec::new();
    reader
        .take((MAX_MANIFEST_BYTES + 1) as u64)
        .read_to_end(&mut bytes)?;
    if bytes.len() > MAX_MANIFEST_BYTES {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "manifest too large",
        ));
    }
    Ok(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_small_and_exact_limit_bodies() {
        for size in [0, 2, MAX_MANIFEST_BYTES] {
            let body = vec![b' '; size];
            assert_eq!(read_manifest(body.as_slice()).unwrap(), body);
        }
    }

    #[test]
    fn rejects_oversize_without_consuming_the_rest() {
        let body = vec![b' '; MAX_MANIFEST_BYTES * 4];
        let mut cursor = io::Cursor::new(body);
        assert_eq!(
            read_manifest(&mut cursor).unwrap_err().kind(),
            io::ErrorKind::InvalidData
        );
        assert_eq!(cursor.position(), (MAX_MANIFEST_BYTES + 1) as u64);
    }

    #[test]
    fn propagates_transport_failure_instead_of_parsing_partial_json() {
        struct Broken;
        impl Read for Broken {
            fn read(&mut self, _: &mut [u8]) -> io::Result<usize> {
                Err(io::Error::from(io::ErrorKind::TimedOut))
            }
        }
        assert_eq!(
            read_manifest(Broken).unwrap_err().kind(),
            io::ErrorKind::TimedOut
        );
    }
}
