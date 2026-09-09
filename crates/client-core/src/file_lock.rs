//! Android std::fs::File::lock is unsupported; use rustix's safe flock on that target.
//! The owning File keeps the lock alive and releases it when closed.
use std::fs::File;
use std::io;

pub(crate) fn exclusive(file: &File) -> io::Result<()> {
    #[cfg(not(target_os = "android"))]
    {
        file.lock()
    }
    #[cfg(target_os = "android")]
    {
        loop {
            match rustix::fs::flock(file, rustix::fs::FlockOperation::LockExclusive) {
                Ok(()) => return Ok(()),
                Err(rustix::io::Errno::INTR) => continue,
                Err(error) => return Err(error.into()),
            }
        }
    }
}
