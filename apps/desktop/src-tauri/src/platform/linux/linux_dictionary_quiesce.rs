//! Dictionary maintenance with the Linux input hosts' sessions released.
//!
//! Importing, editing or clearing learned data needs the Engine's exclusive dictionary lock, and every open IBus or Fcitx5 session holds it shared. Windows asks its server to drop the sessions over a window message; the Linux hosts are other processes with no channel back from here, so this writes a lease beside the lock instead. Both hosts check it on their preference timers (Fcitx5 every 250 ms, IBus every second), finish the composition, close their sessions and open no new ones while it is live. The lease holds its own expiry, so a settings window that dies mid-import cannot leave input off for longer than that. The file name and the 30 second bound are shared with `platforms/linux/src/core/DictionaryQuiesceLease.h`.

use std::path::{Path, PathBuf};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const LEASE_NAME: &str = ".msime-dictionary-quiesce";
const LEASE_DURATION: Duration = Duration::from_secs(30);
/// Long enough for the IBus host's one-second timer to come round twice.
const RETRY_BUDGET: Duration = Duration::from_millis(2500);
const RETRY_INTERVAL: Duration = Duration::from_millis(50);
const BUSY: &str = "dictionary maintenance busy";

struct Lease(PathBuf);

impl Lease {
    fn acquire(user_data: &Path) -> std::io::Result<Self> {
        let expiry = SystemTime::now()
            .checked_add(LEASE_DURATION)
            .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
            .ok_or_else(|| std::io::Error::other("clock before the epoch"))?
            .as_millis();
        let path = user_data.join(LEASE_NAME);
        let staged = user_data.join(format!("{LEASE_NAME}.{}", std::process::id()));
        std::fs::write(&staged, format!("{expiry}\n"))?;
        if let Err(error) = std::fs::rename(&staged, &path) {
            let _ = std::fs::remove_file(&staged);
            return Err(error);
        }
        Ok(Self(path))
    }
}

impl Drop for Lease {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

/// Run `attempt`; when it fails only because an input session holds the dictionaries, ask the hosts to let go and retry until it gets through or the budget runs out. Any other failure is about the request itself and is returned as it is. A completed write is never replayed, because only the lock failure is retried.
pub(crate) fn with_quiesced_hosts<T>(
    user_data: Option<&str>,
    attempt: impl FnMut() -> Result<T, String>,
) -> Result<T, String> {
    quiesce_with(user_data, RETRY_BUDGET, attempt)
}

fn quiesce_with<T>(
    user_data: Option<&str>,
    budget: Duration,
    mut attempt: impl FnMut() -> Result<T, String>,
) -> Result<T, String> {
    let mut result = attempt();
    if !matches!(&result, Err(reason) if reason == BUSY) {
        return result;
    }
    let Some(user_data) = user_data.map(Path::new).filter(|path| path.is_absolute()) else {
        return result;
    };
    let Ok(_lease) = Lease::acquire(user_data) else {
        return result;
    };
    let deadline = Instant::now() + budget;
    while matches!(&result, Err(reason) if reason == BUSY) && Instant::now() < deadline {
        std::thread::sleep(RETRY_INTERVAL);
        result = attempt();
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;

    fn lease_expiry(directory: &Path) -> Option<u128> {
        std::fs::read_to_string(directory.join(LEASE_NAME))
            .ok()
            .and_then(|text| text.trim_end().parse().ok())
    }

    #[test]
    fn busy_is_retried_under_a_lease_that_is_removed_afterwards() {
        let directory = tempfile::tempdir().unwrap();
        let user_data = directory.path().to_str().unwrap().to_owned();
        let calls = Cell::new(0);
        let result = quiesce_with(Some(&user_data), Duration::from_secs(2), || {
            calls.set(calls.get() + 1);
            if calls.get() < 3 {
                // The hosts see the lease while the request is still being retried, with an expiry inside the bound they accept.
                if calls.get() == 2 {
                    let now = SystemTime::now()
                        .duration_since(UNIX_EPOCH)
                        .unwrap()
                        .as_millis();
                    let expiry = lease_expiry(directory.path()).unwrap();
                    assert!(expiry > now && expiry - now <= 30_000);
                }
                Err(BUSY.to_owned())
            } else {
                Ok("imported")
            }
        });
        assert_eq!(result, Ok("imported"));
        assert_eq!(calls.get(), 3);
        assert!(!directory.path().join(LEASE_NAME).exists());
        assert_eq!(std::fs::read_dir(directory.path()).unwrap().count(), 0);
    }

    #[test]
    fn other_failures_and_success_take_no_lease() {
        let directory = tempfile::tempdir().unwrap();
        let user_data = directory.path().to_str().unwrap().to_owned();
        let calls = Cell::new(0);
        let rejected: Result<(), String> =
            quiesce_with(Some(&user_data), Duration::from_secs(2), || {
                calls.set(calls.get() + 1);
                assert!(!directory.path().join(LEASE_NAME).exists());
                Err("dictionary import rejected".to_owned())
            });
        assert_eq!(rejected, Err("dictionary import rejected".to_owned()));
        assert_eq!(calls.get(), 1);
        let done = quiesce_with(Some(&user_data), Duration::from_secs(2), || Ok(1));
        assert_eq!(done, Ok(1));
    }

    #[test]
    fn busy_stays_busy_once_the_budget_runs_out_and_the_lease_goes() {
        let directory = tempfile::tempdir().unwrap();
        let user_data = directory.path().to_str().unwrap().to_owned();
        let result: Result<(), String> =
            quiesce_with(Some(&user_data), Duration::from_millis(120), || {
                Err(BUSY.to_owned())
            });
        assert_eq!(result, Err(BUSY.to_owned()));
        assert!(!directory.path().join(LEASE_NAME).exists());
    }

    #[test]
    fn without_an_absolute_user_directory_busy_is_returned_once() {
        for user_data in [None, Some("relative/user")] {
            let calls = Cell::new(0);
            let result: Result<(), String> =
                quiesce_with(user_data, Duration::from_secs(2), || {
                    calls.set(calls.get() + 1);
                    Err(BUSY.to_owned())
                });
            assert_eq!(result, Err(BUSY.to_owned()));
            assert_eq!(calls.get(), 1);
        }
    }
}
