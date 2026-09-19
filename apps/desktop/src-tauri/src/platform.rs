//! Host integrations that exist on one target only.
//!
//! Each child mirrors a directory under `src/platform/` and is gated on the
//! target it speaks to, so the crate root can name a module without repeating
//! the platform condition at every use site.

#[cfg(target_os = "android")]
pub(crate) mod android;
#[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos", test))]
pub(crate) mod desktop;
#[cfg(any(target_os = "ios", test))]
pub(crate) mod ios;
#[cfg(target_os = "linux")]
pub(crate) mod linux;
#[cfg(any(target_os = "macos", test))]
pub(crate) mod macos;
#[cfg(windows)]
pub(crate) mod windows;
