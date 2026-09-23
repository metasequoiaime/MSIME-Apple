//! Dictionary maintenance with the input hosts' sessions released, on Linux and macOS.
//!
//! Importing, editing or clearing learned data needs the Engine's exclusive dictionary lock, and every open input session holds it shared. Windows asks its server to drop the sessions over a window message. The Linux hosts (IBus, Fcitx5) and the macOS input method are other processes, so this writes a lease beside the lock instead. The hosts check it on their preference timers (Fcitx5 every 250 ms, IBus and macOS every second), finish the composition, close their sessions and open no new ones while it is live; macOS is also told at once over a distributed notification, so it lets go without waiting for its timer. The lease holds its own expiry, so a settings window that dies mid-import cannot leave input off for longer than that. The file name and the 30 second bound are shared with `platforms/common/DictionaryQuiesceLease.h`. Moving the data directory on Linux holds the same lease for the whole copy (`platform::linux::linux_dictionary_quiesce`).

#[cfg(target_os = "linux")]
use std::ffi::OsStr;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

pub(crate) const LEASE_NAME: &str = ".msime-dictionary-quiesce";
const LEASE_DURATION: Duration = Duration::from_secs(30);
/// Long enough for the IBus host's one-second timer to come round twice.
pub(crate) const RETRY_BUDGET: Duration = Duration::from_millis(2500);
pub(crate) const RETRY_INTERVAL: Duration = Duration::from_millis(50);
const BUSY: &str = "dictionary maintenance busy";

pub(crate) struct Lease(PathBuf);

impl Lease {
    pub(crate) fn acquire(user_data: &Path) -> std::io::Result<Self> {
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

/// The lease itself, or one still being staged under `<lease>.<pid>`. Copying either along with the user directory would keep input off in the copy until it expired. Only the Linux data-directory move copies the user directory.
#[cfg(target_os = "linux")]
pub(crate) fn is_lease_file(name: &OsStr) -> bool {
    name.to_str().is_some_and(|name| {
        name.strip_prefix(LEASE_NAME)
            .is_some_and(|rest| rest.is_empty() || rest.starts_with('.'))
    })
}

/// The hosts asked to let go of `user_data` for one settings-page action, which may be several requests: an import larger than one host request is sent in batches. The lease goes up the first time a request finds the dictionaries busy and stays up for every request after it, so the hosts close their sessions once rather than once per batch, and it is renewed before each later request so a long import does not outlive its expiry. `announce` runs once, right after the lease first goes up, so a host that can be told directly (the macOS input method) lets go at once instead of on its timer. Dropping this removes the lease, which is the resume.
pub(crate) struct QuiescedHosts<'a, Announce: FnMut()> {
    user_data: Option<&'a Path>,
    announce: Announce,
    lease: Option<Lease>,
}

impl<'a, Announce: FnMut()> QuiescedHosts<'a, Announce> {
    pub(crate) fn new(user_data: Option<&'a str>, announce: Announce) -> Self {
        Self {
            user_data: user_data.map(Path::new).filter(|path| path.is_absolute()),
            announce,
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
            (self.announce)();
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
        announce: impl FnMut(),
        attempt: impl FnMut() -> Result<T, String>,
    ) -> Result<T, String> {
        QuiescedHosts::new(user_data, announce).run_within(budget, attempt)
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
        let result = quiesce_with(
            Some(&user_data),
            Duration::from_secs(2),
            || {},
            || {
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
            },
        );
        assert_eq!(result, Ok("imported"));
        assert_eq!(calls.get(), 3);
        assert!(!directory.path().join(LEASE_NAME).exists());
        assert_eq!(std::fs::read_dir(directory.path()).unwrap().count(), 0);
    }

    #[test]
    fn one_lease_covers_every_request_of_an_action_and_is_renewed_between_them() {
        let directory = tempfile::tempdir().unwrap();
        let user_data = directory.path().to_str().unwrap().to_owned();
        let announced = Cell::new(0);
        let mut hosts = QuiescedHosts::new(Some(&user_data), || announced.set(announced.get() + 1));
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
        // A later batch that finds the dictionaries busy again is retried under the same lease, and the hosts are not told a second time.
        let calls = Cell::new(0);
        let third = hosts.run_within(Duration::from_secs(2), || {
            calls.set(calls.get() + 1);
            if calls.get() == 1 {
                Err(BUSY.to_owned())
            } else {
                Ok(3)
            }
        });
        assert_eq!(third, Ok(3));
        drop(hosts);
        assert_eq!(announced.get(), 1);
        assert!(!directory.path().join(LEASE_NAME).exists());
        assert_eq!(std::fs::read_dir(directory.path()).unwrap().count(), 0);
    }

    #[test]
    fn other_failures_and_success_take_no_lease() {
        let directory = tempfile::tempdir().unwrap();
        let user_data = directory.path().to_str().unwrap().to_owned();
        let calls = Cell::new(0);
        let rejected: Result<(), String> = quiesce_with(
            Some(&user_data),
            Duration::from_secs(2),
            || {},
            || {
                calls.set(calls.get() + 1);
                assert!(!directory.path().join(LEASE_NAME).exists());
                Err("dictionary import rejected".to_owned())
            },
        );
        assert_eq!(rejected, Err("dictionary import rejected".to_owned()));
        assert_eq!(calls.get(), 1);
        let done = quiesce_with(Some(&user_data), Duration::from_secs(2), || {}, || Ok(1));
        assert_eq!(done, Ok(1));
    }

    #[test]
    fn busy_stays_busy_once_the_budget_runs_out_and_the_lease_goes() {
        let directory = tempfile::tempdir().unwrap();
        let user_data = directory.path().to_str().unwrap().to_owned();
        let result: Result<(), String> = quiesce_with(
            Some(&user_data),
            Duration::from_millis(120),
            || {},
            || Err(BUSY.to_owned()),
        );
        assert_eq!(result, Err(BUSY.to_owned()));
        assert!(!directory.path().join(LEASE_NAME).exists());
    }

    #[test]
    fn hosts_are_told_once_and_only_while_the_lease_is_live() {
        let directory = tempfile::tempdir().unwrap();
        let user_data = directory.path().to_str().unwrap().to_owned();
        let calls = Cell::new(0);
        let announced = Cell::new(0);
        let result = quiesce_with(
            Some(&user_data),
            Duration::from_secs(2),
            || {
                assert!(lease_expiry(directory.path()).is_some());
                announced.set(announced.get() + 1);
            },
            || {
                calls.set(calls.get() + 1);
                if calls.get() < 4 {
                    Err(BUSY.to_owned())
                } else {
                    Ok(())
                }
            },
        );
        assert_eq!(result, Ok(()));
        assert_eq!(announced.get(), 1);

        // Nothing to release: the request went through, failed for its own reasons, or had nowhere to put a lease.
        let silent = Cell::new(0);
        let _ = quiesce_with(
            Some(&user_data),
            Duration::from_secs(2),
            || silent.set(silent.get() + 1),
            || Ok(()),
        );
        let _: Result<(), String> = quiesce_with(
            Some(&user_data),
            Duration::from_secs(2),
            || silent.set(silent.get() + 1),
            || Err("dictionary import rejected".to_owned()),
        );
        let _: Result<(), String> = quiesce_with(
            Some("relative/user"),
            Duration::from_millis(100),
            || silent.set(silent.get() + 1),
            || Err(BUSY.to_owned()),
        );
        assert_eq!(silent.get(), 0);
    }

    #[cfg(target_os = "linux")]
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
            let result: Result<(), String> = quiesce_with(
                user_data,
                Duration::from_secs(2),
                || {},
                || {
                    calls.set(calls.get() + 1);
                    Err(BUSY.to_owned())
                },
            );
            assert_eq!(result, Err(BUSY.to_owned()));
            assert_eq!(calls.get(), 1);
        }
    }
}
