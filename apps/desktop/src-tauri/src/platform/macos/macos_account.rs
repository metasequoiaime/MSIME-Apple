//! macOS desktop account commands backed by the Swift backend's Keychain item.

use crate::shared::account_dto::{
    providers_response, ChallengeResponse, ProfileResponse, ProvidersResponse, StatusResponse,
};
use msime_client_core::account::{
    AccountError, AccountSessionStorage, AccountTokens, BackendAccountClient,
    BackendAccountSession, SavedAccountSession,
};
use serde::Deserialize;
use serde_json::Value;
use std::sync::Arc;
use tauri::Manager;

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
) -> Result<T, crate::CommandError>
where
    T: Send + 'static,
    F: FnOnce(&Session) -> Result<T, AccountError> + Send + 'static,
{
    let session = Arc::clone(&state.session);
    tauri::async_runtime::spawn_blocking(move || operation(&session))
        .await
        .map_err(|_| crate::CommandError {
            code: "account_unavailable",
        })?
        .map_err(|error| crate::CommandError { code: error.code() })
}

#[tauri::command]
pub async fn account_status(
    state: tauri::State<'_, AccountState>,
) -> Result<StatusResponse, crate::CommandError> {
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
) -> Result<ProvidersResponse, crate::CommandError> {
    call(state, |session| session.providers().map(providers_response)).await
}

#[tauri::command]
pub async fn account_request_code(
    state: tauri::State<'_, AccountState>,
    provider: String,
    target: String,
) -> Result<ChallengeResponse, crate::CommandError> {
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
) -> Result<StatusResponse, crate::CommandError> {
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
) -> Result<ProfileResponse, crate::CommandError> {
    call(state, |session| session.profile().map(Into::into)).await
}

#[tauri::command]
pub async fn account_rename(
    state: tauri::State<'_, AccountState>,
    display_name: String,
) -> Result<ProfileResponse, crate::CommandError> {
    call(state, move |session| {
        session.rename(&display_name).map(Into::into)
    })
    .await
}

#[tauri::command]
pub async fn account_logout(
    state: tauri::State<'_, AccountState>,
    all: bool,
) -> Result<(), crate::CommandError> {
    call(state, move |session| session.logout(all)).await
}

#[tauri::command]
pub async fn account_delete(
    state: tauri::State<'_, AccountState>,
) -> Result<(), crate::CommandError> {
    call(state, |session| session.delete_account()).await
}

#[tauri::command]
pub async fn account_forget(
    state: tauri::State<'_, AccountState>,
) -> Result<(), crate::CommandError> {
    call(state, |session| session.forget()).await
}
