//! macOS desktop account commands backed by the Swift backend's Keychain item.

use msime_client_core::account::{
    AccountChallenge, AccountError, AccountProfile, AccountSessionStorage, AccountTokens,
    AccountUser, BackendAccountClient, BackendAccountSession, SavedAccountSession,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::sync::Arc;
use tauri::Manager;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StatusResponse {
    user: Option<UserResponse>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct UserResponse {
    id: String,
    display_name: String,
    created_at: String,
}

impl From<AccountUser> for UserResponse {
    fn from(user: AccountUser) -> Self {
        Self {
            id: user.id,
            display_name: user.display_name,
            created_at: user.created_at,
        }
    }
}

#[derive(Serialize)]
pub struct ProvidersResponse {
    email: bool,
    phone: bool,
    apple: bool,
}

fn providers_response(providers: std::collections::HashMap<String, bool>) -> ProvidersResponse {
    ProvidersResponse {
        email: providers.get("email") == Some(&true),
        phone: providers.get("phone") == Some(&true) || providers.get("sms") == Some(&true),
        apple: providers.get("apple") == Some(&true),
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChallengeResponse {
    challenge_id: String,
    expires_in: u64,
}

impl From<AccountChallenge> for ChallengeResponse {
    fn from(value: AccountChallenge) -> Self {
        Self {
            challenge_id: value.challenge_id,
            expires_in: value.expires_in,
        }
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProfileResponse {
    user: UserResponse,
    providers: Vec<String>,
}

impl From<AccountProfile> for ProfileResponse {
    fn from(profile: AccountProfile) -> Self {
        let mut providers = Vec::new();
        for identity in profile.identities {
            if !providers.contains(&identity.provider) {
                providers.push(identity.provider);
            }
        }
        Self {
            user: profile.user.into(),
            providers,
        }
    }
}

#[derive(Deserialize)]
struct SwiftSavedSession {
    tokens: AccountTokens,
    #[serde(rename = "expiresAt")]
    expires_at: f64,
}

#[derive(Clone, Copy)]
struct MacosAccountStorage;

impl AccountSessionStorage for MacosAccountStorage {
    fn load(&self) -> Result<Option<SavedAccountSession>, AccountError> {
        let Some(bytes) = msime_host_macos::account_load().map_err(|_| AccountError::Storage)?
        else {
            return Ok(None);
        };
        let value: Value = serde_json::from_slice(&bytes).map_err(|_| AccountError::Storage)?;
        if value.get("expiresAt").is_some() {
            let saved: SwiftSavedSession =
                serde_json::from_value(value).map_err(|_| AccountError::Storage)?;
            let expires_at_unix_ms = (saved.expires_at + 978_307_200.0) * 1000.0;
            if !expires_at_unix_ms.is_finite() || expires_at_unix_ms < 0.0 {
                return Err(AccountError::Storage);
            }
            return Ok(Some(SavedAccountSession {
                tokens: saved.tokens,
                expires_at_unix_ms: expires_at_unix_ms.round() as u64,
            }));
        }
        serde_json::from_value(value)
            .map(Some)
            .map_err(|_| AccountError::Storage)
    }

    fn save(&self, session: &SavedAccountSession) -> Result<(), AccountError> {
        let expires_at = session.expires_at_unix_ms as f64 / 1000.0 - 978_307_200.0;
        let value = serde_json::json!({ "tokens": session.tokens, "expiresAt": expires_at });
        let bytes = serde_json::to_vec(&value).map_err(|_| AccountError::Storage)?;
        msime_host_macos::account_save(&bytes).map_err(|_| AccountError::Storage)
    }

    fn clear(&self) -> Result<(), AccountError> {
        msime_host_macos::account_clear().map_err(|_| AccountError::Storage)
    }
}

type Session = BackendAccountSession<BackendAccountClient, MacosAccountStorage>;
pub struct AccountState {
    pub(crate) session: Arc<Session>,
}

pub fn setup(app: &tauri::AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let client = BackendAccountClient::new()?;
    app.manage(AccountState {
        session: Arc::new(BackendAccountSession::new(client, MacosAccountStorage)),
    });
    Ok(())
}

async fn call<T, F>(
    state: tauri::State<'_, AccountState>,
    operation: F,
) -> Result<T, super::CommandError>
where
    T: Send + 'static,
    F: FnOnce(&Session) -> Result<T, AccountError> + Send + 'static,
{
    let session = Arc::clone(&state.session);
    tauri::async_runtime::spawn_blocking(move || operation(&session))
        .await
        .map_err(|_| super::CommandError {
            code: "account_unavailable",
        })?
        .map_err(|error| super::CommandError { code: error.code() })
}

#[tauri::command]
pub async fn account_status(
    state: tauri::State<'_, AccountState>,
) -> Result<StatusResponse, super::CommandError> {
    call(state, |session| {
        session.status().map(|user| StatusResponse {
            user: user.map(Into::into),
        })
    })
    .await
}

#[tauri::command]
pub async fn account_providers(
    state: tauri::State<'_, AccountState>,
) -> Result<ProvidersResponse, super::CommandError> {
    call(state, |session| session.providers().map(providers_response)).await
}

#[tauri::command]
pub async fn account_request_code(
    state: tauri::State<'_, AccountState>,
    provider: String,
    target: String,
) -> Result<ChallengeResponse, super::CommandError> {
    call(state, move |session| {
        session.request_code(&provider, &target).map(Into::into)
    })
    .await
}

#[tauri::command]
pub async fn account_login(
    state: tauri::State<'_, AccountState>,
    challenge_id: String,
    code: String,
) -> Result<StatusResponse, super::CommandError> {
    call(state, move |session| {
        session
            .sign_in(&challenge_id, &code)
            .map(|user| StatusResponse {
                user: Some(user.into()),
            })
    })
    .await
}

#[tauri::command]
pub async fn account_profile(
    state: tauri::State<'_, AccountState>,
) -> Result<ProfileResponse, super::CommandError> {
    call(state, |session| session.profile().map(Into::into)).await
}

#[tauri::command]
pub async fn account_rename(
    state: tauri::State<'_, AccountState>,
    display_name: String,
) -> Result<ProfileResponse, super::CommandError> {
    call(state, move |session| {
        session.rename(&display_name).map(Into::into)
    })
    .await
}

#[tauri::command]
pub async fn account_logout(
    state: tauri::State<'_, AccountState>,
    all: bool,
) -> Result<(), super::CommandError> {
    call(state, move |session| session.logout(all)).await
}

#[tauri::command]
pub async fn account_delete(
    state: tauri::State<'_, AccountState>,
) -> Result<(), super::CommandError> {
    call(state, |session| session.delete_account()).await
}

#[tauri::command]
pub async fn account_forget(
    state: tauri::State<'_, AccountState>,
) -> Result<(), super::CommandError> {
    call(state, |session| session.forget()).await
}
