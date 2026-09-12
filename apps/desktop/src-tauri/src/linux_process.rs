//! Bounded, silent output capture for Linux session tools.
use rustix::fs::{fcntl_getfl, fcntl_setfl, OFlags};
use std::io::{ErrorKind, Read};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

pub fn read_text(program: &str, arguments: &[&str], max_bytes: usize, timeout: Duration) -> Option<String> {
    read_text_bounded(program, arguments, max_bytes, timeout, false)
}

pub fn read_text_prefix(program: &str, arguments: &[&str], max_bytes: usize, timeout: Duration) -> Option<String> {
    read_text_bounded(program, arguments, max_bytes, timeout, true)
}

fn read_text_bounded(program: &str, arguments: &[&str], max_bytes: usize, timeout: Duration, prefix: bool) -> Option<String> {
    let mut child = Command::new(program)
        .args(arguments)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;
    let result = (|| {
        let mut output = child.stdout.take()?;
        let flags = fcntl_getfl(&output).ok()?;
        fcntl_setfl(&output, flags | OFlags::NONBLOCK).ok()?;
        let deadline = Instant::now() + timeout;
        let mut bytes = Vec::with_capacity(max_bytes + 1);
        let mut buffer = [0; 8192];
        let mut eof = false;
        loop {
            if Instant::now() >= deadline {
                return None;
            }
            if !eof {
                let remaining = (max_bytes + 1 - bytes.len()).min(buffer.len());
                match output.read(&mut buffer[..remaining]) {
                    Ok(0) => eof = true,
                    Ok(count) => {
                        bytes.extend_from_slice(&buffer[..count]);
                        if prefix && bytes.len() >= max_bytes {
                            bytes.truncate(max_bytes);
                            let end = match std::str::from_utf8(&bytes) {
                                Ok(_) => bytes.len(),
                                Err(error) if error.error_len().is_none() => error.valid_up_to(),
                                Err(_) => return None,
                            };
                            bytes.truncate(end);
                            let text = String::from_utf8(bytes).ok()?;
                            return (!text.contains('\0')).then_some(text);
                        }
                        if bytes.len() > max_bytes {
                            return None;
                        }
                        continue;
                    }
                    Err(error) if error.kind() == ErrorKind::WouldBlock => {}
                    Err(error) if error.kind() == ErrorKind::Interrupted => continue,
                    Err(_) => return None,
                }
            }
            if eof {
                if let Some(status) = child.try_wait().ok()? {
                    if !status.success() {
                        return None;
                    }
                    let text = String::from_utf8(bytes).ok()?;
                    return (!text.contains('\0')).then_some(text);
                }
            }
            std::thread::sleep(Duration::from_millis(10));
        }
    })();
    // Reap the process on every path, including a full pipe, failed decoding or
    // timeout. Nonblocking reads also cover descendants holding stdout open.
    if result.is_none() || prefix {
        let _ = child.kill();
    }
    let _ = child.wait();
    result
}

