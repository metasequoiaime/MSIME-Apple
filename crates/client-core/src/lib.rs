//! Shared client business logic. Independent of UI frameworks and IME hosts.
//!
//! Modules that serve one domain are grouped under it. A flat list of
//! thirty-four modules gave no hint which of `cloud_dictionary`,
//! `dictionary_access` and `personal_dictionary` belonged together, and the
//! shared prefixes were doing the grouping work that the module tree should do.

pub mod account;
pub mod ai;
pub mod clipboard;
pub mod cloud;
pub mod community;
pub mod credential;
pub mod dictionary;
mod file_lock;
pub mod host_surface;
pub mod panels;
pub mod preferences;
pub mod punctuation;
pub mod resources;
pub mod skin;
pub mod translation;
pub mod typing_statistics;
pub mod voice;
