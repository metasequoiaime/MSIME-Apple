//! macOS host integration.
//!
//! The four modules gated on `test` as well as the target hold logic the host
//! tests exercise on any machine; the rest link against AppKit and only build
//! for macOS.

#[cfg(target_os = "macos")]
pub(crate) mod macos_account;
#[cfg(target_os = "macos")]
pub(crate) mod macos_cloud_clipboard;
#[cfg(target_os = "macos")]
pub(crate) mod macos_cloud_dictionary;
#[cfg(any(target_os = "macos", test))]
pub(crate) mod macos_data_directory;
#[cfg(any(target_os = "macos", test))]
pub(crate) mod macos_handwriting;
#[cfg(any(target_os = "macos", test))]
pub(crate) mod macos_input_source;
#[cfg(any(target_os = "macos", test))]
pub(crate) mod macos_keyboard;
#[cfg(any(target_os = "macos", test))]
pub(crate) mod macos_launch;
#[cfg(target_os = "macos")]
pub(crate) mod macos_panel_session;
