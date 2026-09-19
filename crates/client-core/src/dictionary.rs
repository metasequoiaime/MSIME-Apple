//! Local dictionary storage, import and access policy.
//!
//! The account-synchronised side lives under [`crate::cloud::dictionary`]: the
//! split follows where the data lives, because the two have different failure
//! modes and different validation.

pub mod access;
pub mod import;
pub mod personal;
