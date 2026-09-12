use msime_client_core::account::{
    AccountChallenge, AccountError, AccountProfile, AccountSessionStorage, AccountUser,
    BackendAccountClient, BackendAccountSession, SavedAccountSession,
};
use msime_client_core::community_skin::{
    BackendCommunitySkinService, CommunitySkin, CommunitySkinPage,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tauri::plugin::{Builder, PluginHandle, TauriPlugin};
use tauri::{Manager, Runtime, State, Wry};

const MAX_SECURE_SESSION_BYTES: usize = 16 * 1024;

#[derive(Deserialize)]
struct LoadResponse {
    value: Option<String>,
}

#[derive(Serialize)]
struct SaveRequest<'a> {
    value: &'a str,
}

#[derive(Clone)]
struct AndroidAccountStorage<R: Runtime>(PluginHandle<R>);

impl<R: Runtime> AccountSessionStorage for AndroidAccountStorage<R> {
    fn load(&self) -> Result<Option<SavedAccountSession>, AccountError> {
        let response = self
            .0
            .run_mobile_plugin::<LoadResponse>("loadSession", ())
            .map_err(|_| AccountError::Storage)?;
        response
            .value
            .map(|value| {
                if value.is_empty() || value.len() > MAX_SECURE_SESSION_BYTES {
                    return Err(AccountError::Storage);
                }
                serde_json::from_str(&value).map_err(|_| AccountError::Storage)
            })
            .transpose()
    }

    fn save(&self, session: &SavedAccountSession) -> Result<(), AccountError> {
        let value = serde_json::to_string(session).map_err(|_| AccountError::Storage)?;
        if value.is_empty() || value.len() > MAX_SECURE_SESSION_BYTES {
            return Err(AccountError::Storage);
        }
        self.0
            .run_mobile_plugin::<()>("saveSession", SaveRequest { value: &value })
            .map_err(|_| AccountError::Storage)
    }

    fn clear(&self) -> Result<(), AccountError> {
        self.0
            .run_mobile_plugin::<()>("clearSession", ())
            .map_err(|_| AccountError::Storage)
    }
}

type Session = BackendAccountSession<BackendAccountClient, AndroidAccountStorage<Wry>>;
type CommunityService =
    BackendCommunitySkinService<BackendAccountClient, AndroidAccountStorage<Wry>>;

pub struct AccountState {
    session: Arc<Session>,
    community: Arc<CommunityService>,
}

pub fn init() -> TauriPlugin<Wry> {
    Builder::new("account-storage")
        .setup(|app, api| {
            let handle = api.register_android_plugin("app.msime.client", "AccountPlugin")?;
            let client = BackendAccountClient::new()?;
            let session = Arc::new(BackendAccountSession::new(
                client.clone(),
                AndroidAccountStorage(handle),
            ));
            let community = Arc::new(BackendCommunitySkinService::new(
                client,
                Arc::clone(&session),
            ));
            app.manage(AccountState { session, community });
            Ok(())
        })
        .build()
}

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

fn community_error(error: AccountError) -> super::CommandError {
    super::CommandError {
        code: match error {
            AccountError::Invalid => "community_invalid",
            AccountError::Unauthorized | AccountError::Forbidden => "community_unauthorized",
            AccountError::NotFound => "community_not_found",
            AccountError::RateLimited => "community_rate_limited",
            AccountError::Cancelled => "community_cancelled",
            AccountError::Storage => "community_storage",
            AccountError::Conflict | AccountError::Unavailable => "community_unavailable",
        },
    }
}

async fn community_call<T, F>(
    state: State<'_, AccountState>,
    operation: F,
) -> Result<T, super::CommandError>
where
    T: Send + 'static,
    F: FnOnce(&CommunityService) -> Result<T, AccountError> + Send + 'static,
{
    let service = Arc::clone(&state.community);
    tauri::async_runtime::spawn_blocking(move || operation(&service))
        .await
        .map_err(|_| super::CommandError {
            code: "community_unavailable",
        })?
        .map_err(community_error)
}

#[tauri::command]
pub async fn community_skin_list(
    state: State<'_, AccountState>,
    offset: usize,
    search: String,
) -> Result<CommunitySkinPage, super::CommandError> {
    community_call(state, move |service| service.list(offset, &search)).await
}

#[tauri::command]
pub async fn community_skin_detail(
    state: State<'_, AccountState>,
    id: String,
) -> Result<CommunitySkin, super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError {
        code: "community_invalid",
    })?;
    community_call(state, move |service| service.detail(id)).await
}

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

#[tauri::command]
pub async fn account_providers(
    state: State<'_, AccountState>,
) -> Result<ProvidersResponse, super::CommandError> {
    call(state, |session| {
        session.providers().map(|providers| ProvidersResponse {
            email: providers.get("email") == Some(&true),
            phone: providers.get("phone") == Some(&true) || providers.get("sms") == Some(&true),
        })
    })
    .await
}

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

#[tauri::command]
pub async fn account_profile(
    state: State<'_, AccountState>,
) -> Result<ProfileResponse, super::CommandError> {
    call(state, |session| {
        session.profile().map(ProfileResponse::from)
    })
    .await
}

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

#[tauri::command]
pub async fn account_logout(
    state: State<'_, AccountState>,
    all: bool,
) -> Result<(), super::CommandError> {
    call(state, move |session| session.logout(all)).await
}

#[tauri::command]
pub async fn account_delete(state: State<'_, AccountState>) -> Result<(), super::CommandError> {
    call(state, |session| session.delete_account()).await
}

#[tauri::command]
pub async fn account_forget(state: State<'_, AccountState>) -> Result<(), super::CommandError> {
    call(state, |session| session.forget()).await
}
