//! Bounded transfers through the Linux session's clipboard tools.

use rustix::fs::{fcntl_getfl, fcntl_setfl, OFlags};
use std::io::{ErrorKind, Write};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

const MAX_TEXT_BYTES: usize = 4096;

pub fn read_text(program: &str, arguments: &[&str]) -> Option<String> {
    crate::linux_process::read_text(program, arguments, MAX_TEXT_BYTES, Duration::from_secs(1))
}

pub fn write_text(program: &str, arguments: &[&str], text: &str) -> bool {
    let Ok(mut child) = Command::new(program)
        .args(arguments)
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    else {
        return false;
    };
    let result = (|| {
        let mut input = child.stdin.take()?;
        let flags = fcntl_getfl(&input).ok()?;
        fcntl_setfl(&input, flags | OFlags::NONBLOCK).ok()?;
        let deadline = Instant::now() + Duration::from_secs(2);
        let mut remaining = text.as_bytes();
        while !remaining.is_empty() {
            if Instant::now() >= deadline {
                return None;
            }
            match input.write(remaining) {
                Ok(0) => return None,
                Ok(count) => remaining = &remaining[count..],
                Err(error) if error.kind() == ErrorKind::WouldBlock => {
                    std::thread::sleep(Duration::from_millis(10));
                }
                Err(error) if error.kind() == ErrorKind::Interrupted => {}
                Err(_) => return None,
            }
        }
        // EOF lets the tool publish the selection and detach its owner process.
        drop(input);
        loop {
            if let Some(status) = child.try_wait().ok()? {
                return status.success().then_some(());
            }
            if Instant::now() >= deadline {
                return None;
            }
            std::thread::sleep(Duration::from_millis(10));
        }
    })();
    if result.is_none() {
        let _ = child.kill();
    }
    let _ = child.wait();
    result.is_some()
}
