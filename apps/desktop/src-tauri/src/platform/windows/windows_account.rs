//! Windows desktop account commands.
//!
//! Session tokens stay in the per-user Windows Credential Manager. The React
//! surface only receives the same redacted DTOs as the mobile hosts.

use crate::shared::account_dto::{
    providers_response, ChallengeResponse, ProfileResponse, ProvidersResponse, StatusResponse,
};
use msime_client_core::account::{
    AccountError, AccountSessionStorage, BackendAccountClient, BackendAccountSession,
    SavedAccountSession,
};
use std::sync::Arc;
use tauri::Manager;

#[derive(Clone, Copy)]
struct WindowsAccountStorage;

impl AccountSessionStorage for WindowsAccountStorage {
    fn load(&self) -> Result<Option<SavedAccountSession>, AccountError> {
        msime_host_windows::load_account_session()
            .map_err(|_| AccountError::Storage)?
            .map(|value| serde_json::from_str(&value).map_err(|_| AccountError::Storage))
            .transpose()
    }

    fn save(&self, session: &SavedAccountSession) -> Result<(), AccountError> {
        let value = serde_json::to_string(session).map_err(|_| AccountError::Storage)?;
        msime_host_windows::save_account_session(Some(&value)).map_err(|_| AccountError::Storage)
    }

    fn clear(&self) -> Result<(), AccountError> {
        msime_host_windows::save_account_session(None).map_err(|_| AccountError::Storage)
    }
}

type Session = BackendAccountSession<BackendAccountClient, WindowsAccountStorage>;

pub struct AccountState {
    pub(crate) session: Arc<Session>,
}

pub fn setup(app: &tauri::AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let client = BackendAccountClient::new()?;
    let session = Arc::new(BackendAccountSession::new(client, WindowsAccountStorage));
    app.manage(AccountState { session });
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
