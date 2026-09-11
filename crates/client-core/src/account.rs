//! Platform-injected account authorization boundary.
//! Implementations own credential storage and network interaction.

use std::future::Future;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AccountIdentity {
    pub user_id: String,
}

pub trait AccountSession {
    type Error;
    fn identity(&self) -> impl Future<Output = Result<AccountIdentity, Self::Error>> + Send;
    fn bearer_token(&self) -> impl Future<Output = Result<String, Self::Error>> + Send;
    /// Refreshes the access token and returns the replacement bearer token.
    fn refresh(&self) -> impl Future<Output = Result<String, Self::Error>> + Send;
}

pub fn validate_identity(identity: &AccountIdentity) -> Result<(), &'static str> {
    if identity.user_id.is_empty()
        || identity.user_id.len() > 256
        || identity.user_id.chars().any(char::is_control)
    {
        return Err("invalid account identity");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_unsafe_identity() {
        assert!(validate_identity(&AccountIdentity {
            user_id: "user-1".into()
        })
        .is_ok());
        assert!(validate_identity(&AccountIdentity {
            user_id: "bad\n".into()
        })
        .is_err());
    }
}
