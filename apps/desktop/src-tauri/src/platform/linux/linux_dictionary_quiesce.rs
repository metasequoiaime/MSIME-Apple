//! Dictionary maintenance with the Linux input hosts' sessions released.
//!
//! Importing, editing or clearing learned data needs the Engine's exclusive dictionary lock, and every open IBus or Fcitx5 session holds it shared. Windows asks its server to drop the sessions over a window message; the Linux hosts are other processes with no channel back from here, so this writes a lease beside the lock instead. Both hosts check it on their preference timers (Fcitx5 every 250 ms, IBus every second), finish the composition, close their sessions and open no new ones while it is live. The lease holds its own expiry, so a settings window that dies mid-import cannot leave input off for longer than that. Moving the data directory uses the same lease, held for the whole copy together with the exclusive lock (`hold_hosts_off`). The file name and the 30 second bound are shared with `platforms/linux/src/core/DictionaryQuiesceLease.h`.

use msime_client_core::dictionary::access::DictionaryAccess;
use std::ffi::OsStr;
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
        let lease = Self(user_data.join(LEASE_NAME));
        lease.publish()?;
        Ok(lease)
    }

    /// Write the lease with an expiry `LEASE_DURATION` from now, replacing any earlier one in a single rename so a host never reads a partial file.
    fn publish(&self) -> std::io::Result<()> {
        let expiry = SystemTime::now()
            .checked_add(LEASE_DURATION)
            .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
            .ok_or_else(|| std::io::Error::other("clock before the epoch"))?
            .as_millis();
        let staged = self
            .0
            .with_file_name(format!("{LEASE_NAME}.{}", std::process::id()));
        std::fs::write(&staged, format!("{expiry}\n"))?;
        if let Err(error) = std::fs::rename(&staged, &self.0) {
            let _ = std::fs::remove_file(&staged);
            return Err(error);
        }
        Ok(())
    }
}

impl Drop for Lease {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

/// The lease itself, or one still being staged under `<lease>.<pid>`. Copying either along with the user directory would keep input off in the copy until it expired.
pub(crate) fn is_lease_file(name: &OsStr) -> bool {
    name.to_str().is_some_and(|name| {
        name.strip_prefix(LEASE_NAME)
            .is_some_and(|rest| rest.is_empty() || rest.starts_with('.'))
    })
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum HoldError {
    /// A session still held the dictionaries when the budget ran out.
    Busy,
    /// The lease could not be written or the lock files could not be opened.
    Unavailable,
}

/// Both hosts kept off the user directory: the lease that asked them to close their sessions, and the exclusive dictionary lock that proves they did and keeps any session from opening while it is held, even after the lease has expired. Dropping it releases the lock first and then removes the lease.
pub(crate) struct HostsHeldOff<Access = DictionaryAccess> {
    _access: Access,
    _lease: Lease,
}

/// Keep both hosts off `user_data` for as long as the returned guard lives, for work that replaces the directory rather than editing through the Engine, such as moving the data root. Unlike `QuiescedHosts` the lease goes up first and stays up until the guard is dropped. A host that is not running holds no lock, so it cannot keep this busy. `Ok(None)` when `user_data` does not exist: no session can be open on it.
pub(crate) fn hold_hosts_off(
    user_data: &Path,
    dictionaries: &Path,
) -> Result<Option<HostsHeldOff>, HoldError> {
    hold_with(user_data, RETRY_BUDGET, || {
        DictionaryAccess::try_maintenance(user_data, dictionaries)
    })
}

fn hold_with<Access>(
    user_data: &Path,
    budget: Duration,
    mut try_exclusive: impl FnMut() -> std::io::Result<Option<Access>>,
) -> Result<Option<HostsHeldOff<Access>>, HoldError> {
    if !user_data.is_absolute() {
        return Err(HoldError::Unavailable);
    }
    match std::fs::symlink_metadata(user_data) {
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(_) => return Err(HoldError::Unavailable),
        Ok(_) => {}
    }
    let lease = Lease::acquire(user_data).map_err(|_| HoldError::Unavailable)?;
    let deadline = Instant::now() + budget;
    loop {
        match try_exclusive() {
            Ok(Some(access)) => {
                return Ok(Some(HostsHeldOff {
                    _access: access,
                    _lease: lease,
                }))
            }
            Ok(None) if Instant::now() < deadline => std::thread::sleep(RETRY_INTERVAL),
            Ok(None) => return Err(HoldError::Busy),
            Err(_) => return Err(HoldError::Unavailable),
        }
    }
}

/// The hosts asked to let go of `user_data` for one settings-page action, which may be several requests: an import larger than one host request is sent in batches. The lease goes up the first time a request finds the dictionaries busy and stays up for every request after it, so the hosts close their sessions once rather than once per batch, and it is renewed before each later request so a long import does not outlive its expiry. Dropping this removes it.
pub(crate) struct QuiescedHosts<'a> {
    user_data: Option<&'a Path>,
    lease: Option<Lease>,
}

impl<'a> QuiescedHosts<'a> {
    pub(crate) fn new(user_data: Option<&'a str>) -> Self {
        Self {
            user_data: user_data.map(Path::new).filter(|path| path.is_absolute()),
            lease: None,
        }
    }

    /// Run `attempt`; when it fails only because an input session holds the dictionaries, ask the hosts to let go and retry until it gets through or the budget runs out. Any other failure is about the request itself and is returned as it is. A completed write is never replayed, because only the lock failure is retried.
    pub(crate) fn run<T>(
        &mut self,
        attempt: impl FnMut() -> Result<T, String>,
    ) -> Result<T, String> {
        self.run_within(RETRY_BUDGET, attempt)
    }

    fn run_within<T>(
        &mut self,
        budget: Duration,
        mut attempt: impl FnMut() -> Result<T, String>,
    ) -> Result<T, String> {
        if let Some(lease) = &self.lease {
            // A lease that cannot be renewed still holds until its expiry, and a host that reopens a session after that makes the attempt below busy, which is retried like any other.
            let _ = lease.publish();
        }
        let mut result = attempt();
        if !matches!(&result, Err(reason) if reason == BUSY) {
            return result;
        }
        let Some(user_data) = self.user_data else {
            return result;
        };
        if self.lease.is_none() {
            let Ok(lease) = Lease::acquire(user_data) else {
                return result;
            };
            self.lease = Some(lease);
        }
        let deadline = Instant::now() + budget;
        while matches!(&result, Err(reason) if reason == BUSY) && Instant::now() < deadline {
            std::thread::sleep(RETRY_INTERVAL);
            result = attempt();
        }
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;

    /// One action of one request, with the hosts released again as soon as it is done.
    fn quiesce_with<T>(
        user_data: Option<&str>,
        budget: Duration,
        attempt: impl FnMut() -> Result<T, String>,
    ) -> Result<T, String> {
        QuiescedHosts::new(user_data).run_within(budget, attempt)
    }

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
    fn one_lease_covers_every_request_of_an_action_and_is_renewed_between_them() {
        let directory = tempfile::tempdir().unwrap();
        let user_data = directory.path().to_str().unwrap().to_owned();
        let mut hosts = QuiescedHosts::new(Some(&user_data));
        let calls = Cell::new(0);
        let first = hosts.run_within(Duration::from_secs(2), || {
            calls.set(calls.get() + 1);
            if calls.get() == 1 {
                Err(BUSY.to_owned())
            } else {
                Ok(1)
            }
        });
        assert_eq!(first, Ok(1));
        let expiry = lease_expiry(directory.path()).unwrap();
        std::thread::sleep(Duration::from_millis(20));
        // The next batch of the same import finds the hosts still released, under a lease pushed forward rather than one about to lapse.
        let second = hosts.run_within(Duration::from_secs(2), || {
            assert!(lease_expiry(directory.path()).unwrap() > expiry);
            Ok(2)
        });
        assert_eq!(second, Ok(2));
        drop(hosts);
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
    fn a_hold_waits_for_the_session_to_close_and_keeps_the_lease_until_dropped() {
        let directory = tempfile::tempdir().unwrap();
        let user = directory.path().to_path_buf();
        // A host with a session open on the directory, releasing it once it sees the lease, as both hosts do on their timers.
        let session = DictionaryAccess::try_session(&user, &user)
            .unwrap()
            .unwrap();
        let host = {
            let user = user.clone();
            std::thread::spawn(move || {
                let deadline = Instant::now() + Duration::from_secs(2);
                while !user.join(LEASE_NAME).exists() {
                    assert!(Instant::now() < deadline, "the lease never appeared");
                    std::thread::sleep(Duration::from_millis(5));
                }
                drop(session);
            })
        };
        let held = hold_with(&user, Duration::from_secs(2), || {
            DictionaryAccess::try_maintenance(&user, &user)
        })
        .unwrap()
        .unwrap();
        host.join().unwrap();
        // While held, the lease is up and no session can open, whether or not a host still honours the lease.
        assert!(lease_expiry(&user).is_some());
        assert!(DictionaryAccess::try_session(&user, &user)
            .unwrap()
            .is_none());
        drop(held);
        assert!(!user.join(LEASE_NAME).exists());
        let deadline = Instant::now() + Duration::from_secs(2);
        while DictionaryAccess::try_session(&user, &user)
            .unwrap()
            .is_none()
        {
            assert!(Instant::now() < deadline, "the lock stayed held");
            std::thread::sleep(Duration::from_millis(1));
        }
    }

    #[test]
    fn a_session_that_never_closes_makes_the_hold_busy_and_takes_the_lease_down() {
        let directory = tempfile::tempdir().unwrap();
        let _session = DictionaryAccess::try_session(directory.path(), directory.path())
            .unwrap()
            .unwrap();
        let result = hold_with(directory.path(), Duration::from_millis(120), || {
            DictionaryAccess::try_maintenance(directory.path(), directory.path())
        });
        assert_eq!(result.err(), Some(HoldError::Busy));
        assert!(!directory.path().join(LEASE_NAME).exists());
    }

    #[test]
    fn a_missing_user_directory_needs_no_hold_and_a_relative_one_is_refused() {
        let directory = tempfile::tempdir().unwrap();
        let missing = directory.path().join("user");
        let result = hold_with(
            &missing,
            Duration::from_secs(2),
            || -> std::io::Result<Option<()>> { unreachable!("nothing to lock") },
        );
        assert!(matches!(result, Ok(None)));
        assert!(!missing.exists());
        let relative = hold_with(Path::new("relative/user"), Duration::from_secs(2), || {
            Ok(Some(()))
        });
        assert_eq!(relative.err(), Some(HoldError::Unavailable));
    }

    #[test]
    fn lease_files_include_a_lease_being_staged() {
        assert!(is_lease_file(OsStr::new(LEASE_NAME)));
        assert!(is_lease_file(OsStr::new(".msime-dictionary-quiesce.4242")));
        assert!(!is_lease_file(OsStr::new(".msime-dictionary-quiesced")));
        assert!(!is_lease_file(OsStr::new(".msime-dictionary-access.lock")));
        assert!(!is_lease_file(OsStr::new("msime_user.db")));
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
