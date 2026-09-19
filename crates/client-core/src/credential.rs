//! Validation and probing for the third-party service credentials the user
//! supplies. Nothing here stores or logs a secret; the probes report only
//! whether a credential was accepted.

pub mod asr;
pub mod doubao;
pub mod doubao_auth;
pub mod probe;
pub mod translation;
