use msime_client_core::account::{
    AccountChallenge, AccountError, AccountProfile, AccountSessionStorage, AccountUser,
    BackendAccountClient, BackendAccountSession, SavedAccountSession,
};
use msime_client_core::ai_skin::{AiSkinError, AiSkinProposal, BackendAiSkinService};
use msime_client_core::community_resource::{
    BackendCommunityResourceService, CommunityResource, CommunityResourceApplication,
    CommunityResourceContent, CommunityResourceKind, CommunityResourcePage,
    CommunityResourcePublication, CommunityResourceScope,
};
use msime_client_core::community_resource_library::{
    CommunityResourceLibraryError, CommunityResourceLibraryStore,
};
use msime_client_core::community_skin::{
    BackendCommunitySkinService, CommunitySkin, CommunitySkinPage,
};
use msime_client_core::custom_skin_library::{
    CustomSkinLibraryError, CustomSkinLibraryStore, SavedTouchKeyboardSkin,
};
use msime_client_core::keyboard_skin_trial::{
    KeyboardSkinTrial, KeyboardSkinTrialError, KeyboardSkinTrialStore,
};
use msime_client_core::preferences::TouchKeyboardSkinDesign;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use tauri::plugin::{Builder, PluginHandle, TauriPlugin};
use tauri::{Emitter, Manager, Runtime, State, Wry};

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
type CommunityResourceService =
    BackendCommunityResourceService<BackendAccountClient, AndroidAccountStorage<Wry>>;
type AiSkinService = BackendAiSkinService<BackendAccountClient, AndroidAccountStorage<Wry>>;

pub struct AccountState {
    session: Arc<Session>,
    community: Arc<CommunityService>,
    resources: Arc<CommunityResourceService>,
    ai_skin: Arc<AiSkinService>,
    ai_skin_requests: Arc<Mutex<HashMap<String, Arc<AtomicBool>>>>,
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
            let resource_client = BackendAccountClient::new()?;
            let resources = Arc::new(BackendCommunityResourceService::new(
                resource_client,
                Arc::clone(&session),
            ));
            let ai_skin = Arc::new(BackendAiSkinService::new(
                BackendAccountClient::new()?,
                Arc::clone(&session),
            ));
            app.manage(AccountState {
                session,
                community,
                resources,
                ai_skin,
                ai_skin_requests: Arc::new(Mutex::new(HashMap::new())),
            });
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
            AccountError::Unauthorized => "community_unauthorized",
            AccountError::Forbidden => "community_forbidden",
            AccountError::NotFound => "community_not_found",
            AccountError::RateLimited => "community_rate_limited",
            AccountError::Cancelled => "community_cancelled",
            AccountError::Storage => "community_storage",
            AccountError::Conflict => "community_conflict",
            AccountError::Unavailable => "community_unavailable",
        },
    }
}

fn ai_skin_error(error: AiSkinError) -> super::CommandError {
    let code = match error {
        AiSkinError::Cancelled => "ai_skin_cancelled",
        AiSkinError::InvalidResponse => "ai_skin_invalid",
        AiSkinError::Account(error) => error.code(),
    };
    super::CommandError { code }
}

fn valid_ai_skin_request_id(value: &str) -> bool {
    (1..=96).contains(&value.len())
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct AiSkinProgress {
    request_id: String,
    completed: usize,
}

#[tauri::command]
pub async fn ai_skin_generate(
    app: tauri::AppHandle<Wry>,
    state: State<'_, AccountState>,
    request_id: String,
    prompt: String,
) -> Result<Vec<AiSkinProposal>, super::CommandError> {
    if !valid_ai_skin_request_id(&request_id) {
        return Err(super::CommandError {
            code: "ai_skin_invalid",
        });
    }
    let cancelled = Arc::new(AtomicBool::new(false));
    {
        let mut requests = state
            .ai_skin_requests
            .lock()
            .map_err(|_| super::CommandError {
                code: "ai_skin_unavailable",
            })?;
        if requests
            .insert(request_id.clone(), Arc::clone(&cancelled))
            .is_some()
        {
            return Err(super::CommandError {
                code: "ai_skin_busy",
            });
        }
    }
    let service = Arc::clone(&state.ai_skin);
    let progress_app = app.clone();
    let progress_request_id = request_id.clone();
    let result = tauri::async_runtime::spawn_blocking(move || {
        service.generate(&prompt, &cancelled, move |completed| {
            let _ = progress_app.emit(
                "ai-skin-progress",
                AiSkinProgress {
                    request_id: progress_request_id.clone(),
                    completed,
                },
            );
        })
    })
    .await
    .map_err(|_| super::CommandError {
        code: "ai_skin_unavailable",
    })?
    .map_err(ai_skin_error);
    if let Ok(mut requests) = state.ai_skin_requests.lock() {
        requests.remove(&request_id);
    }
    result
}

#[tauri::command]
pub async fn ai_skin_cancel(
    state: State<'_, AccountState>,
    request_id: String,
) -> Result<(), super::CommandError> {
    if !valid_ai_skin_request_id(&request_id) {
        return Err(super::CommandError {
            code: "ai_skin_invalid",
        });
    }
    let requests = state
        .ai_skin_requests
        .lock()
        .map_err(|_| super::CommandError {
            code: "ai_skin_unavailable",
        })?;
    if let Some(cancelled) = requests.get(&request_id) {
        cancelled.store(true, Ordering::Release);
    }
    Ok(())
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

fn custom_skin_error(error: CustomSkinLibraryError) -> super::CommandError {
    super::CommandError {
        code: match error {
            CustomSkinLibraryError::Full => "community_skin_library_full",
            CustomSkinLibraryError::InvalidName => "community_skin_invalid_name",
            CustomSkinLibraryError::DuplicateName => "community_skin_duplicate_name",
            CustomSkinLibraryError::NotFound => "community_skin_not_found",
            CustomSkinLibraryError::Json(_) | CustomSkinLibraryError::Invalid => {
                "community_skin_library_format"
            }
            CustomSkinLibraryError::Io(_) => "community_storage",
        },
    }
}

fn trial_error(error: KeyboardSkinTrialError) -> super::CommandError {
    super::CommandError {
        code: match error {
            KeyboardSkinTrialError::Io(_) | KeyboardSkinTrialError::Preferences(_) => {
                "community_storage"
            }
            KeyboardSkinTrialError::Json(_) | KeyboardSkinTrialError::Invalid => {
                "community_trial_format"
            }
        },
    }
}

fn resource_library_error(error: CommunityResourceLibraryError) -> super::CommandError {
    super::CommandError {
        code: match error {
            CommunityResourceLibraryError::Io(_) => "community_storage",
            CommunityResourceLibraryError::Json(_) | CommunityResourceLibraryError::Invalid => {
                "community_resource_library_format"
            }
        },
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CommunitySkinDownloadResponse {
    skin: SavedTouchKeyboardSkin,
    trial: KeyboardSkinTrial,
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
pub async fn community_skin_download(
    state: State<'_, AccountState>,
    library: State<'_, CustomSkinLibraryStore>,
    trials: State<'_, KeyboardSkinTrialStore>,
    id: String,
    name: String,
) -> Result<CommunitySkinDownloadResponse, super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError {
        code: "community_invalid",
    })?;
    let service = Arc::clone(&state.community);
    let library = library.inner().clone();
    let trials = trials.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        let design = service.download(id).map_err(community_error)?;
        let (trial, _) = trials.begin(&name, design.clone()).map_err(trial_error)?;
        let skin = match library.import_download(id, &name, design) {
            Ok(skin) => skin,
            Err(error) => {
                let _ = trials.finish(trial.id, false);
                return Err(custom_skin_error(error));
            }
        };
        Ok(CommunitySkinDownloadResponse { skin, trial })
    })
    .await
    .map_err(|_| super::CommandError {
        code: "community_unavailable",
    })?
}

#[tauri::command]
pub async fn community_skin_rate(
    state: State<'_, AccountState>,
    id: String,
    stars: u8,
) -> Result<(), super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError {
        code: "community_invalid",
    })?;
    community_call(state, move |service| service.rate(id, stars)).await
}

#[tauri::command]
pub async fn community_skin_publish(
    state: State<'_, AccountState>,
    id: String,
    name: String,
    description: String,
    design: TouchKeyboardSkinDesign,
) -> Result<(), super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError {
        code: "community_invalid",
    })?;
    community_call(state, move |service| {
        service.publish(id, &name, &description, &design)
    })
    .await
}

#[tauri::command]
pub async fn community_skin_unpublish(
    state: State<'_, AccountState>,
    id: String,
) -> Result<(), super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError {
        code: "community_invalid",
    })?;
    community_call(state, move |service| service.unpublish(id)).await
}

#[tauri::command]
pub async fn community_skin_finish_trial(
    trials: State<'_, KeyboardSkinTrialStore>,
    id: String,
    keep: bool,
) -> Result<(), super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError {
        code: "community_invalid",
    })?;
    let trials = trials.inner().clone();
    tauri::async_runtime::spawn_blocking(move || trials.finish(id, keep).map(|_| ()))
        .await
        .map_err(|_| super::CommandError {
            code: "community_storage",
        })?
        .map_err(trial_error)
}

fn resource_scope(value: &str) -> Result<CommunityResourceScope, super::CommandError> {
    match value {
        "" => Ok(CommunityResourceScope::All),
        "mine" => Ok(CommunityResourceScope::Mine),
        "saved" => Ok(CommunityResourceScope::Saved),
        _ => Err(super::CommandError { code: "community_invalid" }),
    }
}

async fn resource_call<T, F>(
    state: State<'_, AccountState>,
    operation: F,
) -> Result<T, super::CommandError>
where
    T: Send + 'static,
    F: FnOnce(&CommunityResourceService) -> Result<T, AccountError> + Send + 'static,
{
    let service = Arc::clone(&state.resources);
    tauri::async_runtime::spawn_blocking(move || operation(&service))
        .await
        .map_err(|_| super::CommandError { code: "community_unavailable" })?
        .map_err(community_error)
}

#[tauri::command]
pub async fn community_resource_list(
    state: State<'_, AccountState>,
    kind: CommunityResourceKind,
    scope: String,
    search: String,
    offset: usize,
) -> Result<CommunityResourcePage, super::CommandError> {
    let scope = resource_scope(&scope)?;
    resource_call(state, move |service| service.list(kind, scope, &search, offset)).await
}

#[tauri::command]
pub async fn community_resource_detail(
    state: State<'_, AccountState>,
    id: String,
) -> Result<CommunityResource, super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError { code: "community_invalid" })?;
    resource_call(state, move |service| service.detail(id)).await
}

#[tauri::command]
pub async fn community_resource_publish(
    state: State<'_, AccountState>,
    id: String,
    kind: CommunityResourceKind,
    name: String,
    description: String,
    content: CommunityResourceContent,
    revision: u32,
) -> Result<CommunityResourcePublication, super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError { code: "community_invalid" })?;
    resource_call(state, move |service| service.publish(id, kind, &name, &description, &content, revision)).await
}

#[tauri::command]
pub async fn community_resource_apply(
    state: State<'_, AccountState>,
    id: String,
    resource_revision: u32,
) -> Result<CommunityResourceApplication, super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError { code: "community_invalid" })?;
    resource_call(state, move |service| service.apply(id, resource_revision)).await
}

#[tauri::command]
pub async fn community_resource_save(
    state: State<'_, AccountState>,
    id: String,
    saved: bool,
) -> Result<(), super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError { code: "community_invalid" })?;
    resource_call(state, move |service| service.save(id, saved)).await
}

#[tauri::command]
pub async fn community_resource_rate(
    state: State<'_, AccountState>,
    id: String,
    stars: u8,
) -> Result<(), super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError { code: "community_invalid" })?;
    resource_call(state, move |service| service.rate(id, stars)).await
}

#[tauri::command]
pub async fn community_resource_unpublish(
    state: State<'_, AccountState>,
    id: String,
) -> Result<(), super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError { code: "community_invalid" })?;
    resource_call(state, move |service| service.delete(id)).await
}

#[tauri::command]
pub async fn community_resource_store_reply(
    library: State<'_, CommunityResourceLibraryStore>,
    item: CommunityResource,
) -> Result<(), super::CommandError> {
    let library = library.inner().clone();
    tauri::async_runtime::spawn_blocking(move || library.save_reply(item))
        .await
        .map_err(|_| super::CommandError { code: "community_storage" })?
        .map_err(resource_library_error)
}

#[tauri::command]
pub async fn community_resource_remove_reply(
    library: State<'_, CommunityResourceLibraryStore>,
    id: String,
) -> Result<(), super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError { code: "community_invalid" })?;
    let library = library.inner().clone();
    tauri::async_runtime::spawn_blocking(move || library.remove(id))
        .await
        .map_err(|_| super::CommandError { code: "community_storage" })?
        .map_err(resource_library_error)
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
