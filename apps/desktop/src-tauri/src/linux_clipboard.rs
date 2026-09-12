//! Bounded reads from the Linux session's clipboard tools.

use rustix::fs::{fcntl_getfl, fcntl_setfl, OFlags};
use std::io::{ErrorKind, Read};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

const MAX_TEXT_BYTES: usize = 4096;

pub fn read_text(program: &str, arguments: &[&str]) -> Option<String> {
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
        let deadline = Instant::now() + Duration::from_secs(1);
        let mut bytes = Vec::with_capacity(MAX_TEXT_BYTES + 1);
        let mut buffer = [0; MAX_TEXT_BYTES + 1];
        let mut eof = false;
        loop {
            if Instant::now() >= deadline {
                return None;
            }
            if !eof {
                let remaining = MAX_TEXT_BYTES + 1 - bytes.len();
                match output.read(&mut buffer[..remaining]) {
                    Ok(0) => eof = true,
                    Ok(count) => {
                        bytes.extend_from_slice(&buffer[..count]);
                        if bytes.len() > MAX_TEXT_BYTES {
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
    if result.is_none() {
        let _ = child.kill();
    }
    let _ = child.wait();
    result
}
