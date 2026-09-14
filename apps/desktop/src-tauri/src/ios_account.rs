use msime_client_core::account::{AccountChallenge, AccountProfile, AccountUser};
use serde::Serialize;

#[cfg(target_os = "ios")]
use msime_client_core::account::{
    AccountError, AccountSessionStorage, BackendAccountClient, BackendAccountSession,
    SavedAccountSession,
};
#[cfg(target_os = "ios")]
use msime_tauri_mobile_platform::MobilePlatform;
#[cfg(target_os = "ios")]
use std::sync::Arc;
#[cfg(target_os = "ios")]
use tauri::{AppHandle, Manager, Runtime, State, Wry};

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
}

fn providers_response(providers: std::collections::HashMap<String, bool>) -> ProvidersResponse {
    ProvidersResponse {
        email: providers.get("email") == Some(&true),
        phone: providers.get("phone") == Some(&true) || providers.get("sms") == Some(&true),
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChallengeResponse {
    challenge_id: String,
    expires_in: u64,
}

impl From<AccountChallenge> for ChallengeResponse {
    fn from(challenge: AccountChallenge) -> Self {
        Self {
            challenge_id: challenge.challenge_id,
            expires_in: challenge.expires_in,
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

#[cfg(target_os = "ios")]
#[derive(Clone)]
struct IosAccountStorage<R: Runtime>(MobilePlatform<R>);

#[cfg(target_os = "ios")]
impl<R: Runtime> AccountSessionStorage for IosAccountStorage<R> {
    fn load(&self) -> Result<Option<SavedAccountSession>, AccountError> {
        self.0
            .load_account_session()
            .map_err(|_| AccountError::Storage)?
            .map(|value| serde_json::from_str(&value).map_err(|_| AccountError::Storage))
            .transpose()
    }

    fn save(&self, session: &SavedAccountSession) -> Result<(), AccountError> {
        let value = serde_json::to_string(session).map_err(|_| AccountError::Storage)?;
        self.0
            .save_account_session(&value)
            .map_err(|_| AccountError::Storage)
    }

    fn clear(&self) -> Result<(), AccountError> {
        self.0
            .clear_account_session()
            .map_err(|_| AccountError::Storage)
    }
}

#[cfg(target_os = "ios")]
type Session = BackendAccountSession<BackendAccountClient, IosAccountStorage<Wry>>;

#[cfg(target_os = "ios")]
pub struct AccountState {
    session: Arc<Session>,
}

#[cfg(target_os = "ios")]
pub fn setup(app: &AppHandle<Wry>) -> Result<(), AccountError> {
    let platform = app
        .try_state::<MobilePlatform<Wry>>()
        .ok_or(AccountError::Storage)?
        .inner()
        .clone();
    let client = BackendAccountClient::new()?;
    app.manage(AccountState {
        session: Arc::new(BackendAccountSession::new(
            client,
            IosAccountStorage(platform),
        )),
    });
    Ok(())
}

#[cfg(target_os = "ios")]
async fn call<T, F>(state: State<'_, AccountState>, operation: F) -> Result<T, super::CommandError>
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

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn account_status(
    state: State<'_, AccountState>,
) -> Result<StatusResponse, super::CommandError> {
    call(state, |session| {
        session.status().map(|user| StatusResponse {
            user: user.map(Into::into),
        })
    })
    .await
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn account_providers(
    state: State<'_, AccountState>,
) -> Result<ProvidersResponse, super::CommandError> {
    call(state, |session| session.providers().map(providers_response)).await
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn account_request_code(
    state: State<'_, AccountState>,
    provider: String,
    target: String,
) -> Result<ChallengeResponse, super::CommandError> {
    call(state, move |session| {
        session
            .request_code(&provider, &target)
            .map(ChallengeResponse::from)
    })
    .await
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn account_login(
    state: State<'_, AccountState>,
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

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn account_profile(
    state: State<'_, AccountState>,
) -> Result<ProfileResponse, super::CommandError> {
    call(state, |session| {
        session.profile().map(ProfileResponse::from)
    })
    .await
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn account_rename(
    state: State<'_, AccountState>,
    display_name: String,
) -> Result<ProfileResponse, super::CommandError> {
    call(state, move |session| {
        session.rename(&display_name).map(ProfileResponse::from)
    })
    .await
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn account_logout(
    state: State<'_, AccountState>,
    all: bool,
) -> Result<(), super::CommandError> {
    call(state, move |session| session.logout(all)).await
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn account_delete(state: State<'_, AccountState>) -> Result<(), super::CommandError> {
    call(state, |session| session.delete_account()).await
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn account_forget(state: State<'_, AccountState>) -> Result<(), super::CommandError> {
    call(state, |session| session.forget()).await
}

#[cfg(test)]
mod tests {
    use super::{providers_response, ChallengeResponse, ProfileResponse, StatusResponse};
    use msime_client_core::account::{
        AccountChallenge, AccountProfile, AccountProfileIdentity, AccountUser,
    };
    use serde_json::json;
    use std::collections::HashMap;

    fn user() -> AccountUser {
        AccountUser {
            id: "synthetic-user".into(),
            display_name: "测试账号".into(),
            created_at: "2026-01-01T00:00:00Z".into(),
        }
    }

    #[test]
    fn account_responses_match_the_shared_webview_contract() {
        let status = serde_json::to_value(StatusResponse {
            user: Some(user().into()),
        })
        .unwrap();
        assert_eq!(status["user"]["displayName"], "测试账号");
        assert_eq!(status["user"]["createdAt"], "2026-01-01T00:00:00Z");

        let challenge = serde_json::to_value(ChallengeResponse::from(AccountChallenge {
            challenge_id: "synthetic-challenge".into(),
            expires_in: 300,
            nonce: Some("not-exposed".into()),
            authorization_url: Some("https://invalid.example".into()),
        }))
        .unwrap();
        assert_eq!(
            challenge,
            json!({"challengeId":"synthetic-challenge","expiresIn":300})
        );
    }

    #[test]
    fn provider_and_profile_responses_normalize_backend_names() {
        let providers = providers_response(HashMap::from([
            ("email".into(), true),
            ("sms".into(), true),
        ]));
        assert_eq!(
            serde_json::to_value(providers).unwrap(),
            json!({"email":true,"phone":true})
        );

        let profile = ProfileResponse::from(AccountProfile {
            user: user(),
            identities: vec![
                AccountProfileIdentity {
                    provider: "email".into(),
                    subject: "synthetic-one".into(),
                },
                AccountProfileIdentity {
                    provider: "email".into(),
                    subject: "synthetic-two".into(),
                },
                AccountProfileIdentity {
                    provider: "phone".into(),
                    subject: "synthetic-three".into(),
                },
            ],
        });
        assert_eq!(
            serde_json::to_value(profile).unwrap()["providers"],
            json!(["email", "phone"])
        );
    }
}
