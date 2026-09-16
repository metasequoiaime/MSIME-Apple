use msime_client_core::account::{
    AccountChallenge, AccountChatModels, AccountPreferenceSchema, AccountProfile, AccountUser,
};
use serde::Serialize;
use std::collections::BTreeMap;

#[cfg(target_os = "ios")]
use serde_json::Value;

#[path = "ios_account_preferences.rs"]
mod account_preferences;

#[cfg(target_os = "ios")]
use msime_client_core::account::{
    merge_account_preferences, AccountCandidateQuery, AccountChatMessage, AccountError,
    AccountPreferences, AccountSessionStorage, BackendAccountClient, BackendAccountSession,
    SavedAccountSession,
};
#[cfg(target_os = "ios")]
use msime_client_core::ai_skin::{AiSkinError, AiSkinProposal, BackendAiSkinService};
#[cfg(target_os = "ios")]
use msime_client_core::cloud_dictionary::DictionaryKind;
#[cfg(target_os = "ios")]
use msime_client_core::community_resource::{
    BackendCommunityResourceService, CommunityResource, CommunityResourceApplication,
    CommunityResourceContent, CommunityResourceKind, CommunityResourcePage,
    CommunityResourcePublication, CommunityResourceScope,
};
#[cfg(target_os = "ios")]
use msime_client_core::community_resource_library::{
    CommunityResourceLibraryError, CommunityResourceLibraryStore,
};
#[cfg(target_os = "ios")]
use msime_client_core::community_skin::{
    BackendCommunitySkinService, CommunitySkin, CommunitySkinPage,
};
#[cfg(target_os = "ios")]
use msime_client_core::custom_skin_library::{
    CustomSkinLibraryError, CustomSkinLibraryStore, SavedTouchKeyboardSkin,
};
#[cfg(target_os = "ios")]
use msime_client_core::keyboard_skin_trial::{
    KeyboardSkinTrial, KeyboardSkinTrialError, KeyboardSkinTrialStore,
};
#[cfg(target_os = "ios")]
use msime_client_core::preferences::PreferencesStore;
#[cfg(target_os = "ios")]
use msime_tauri_mobile_platform::{IosKeyboardPreferences, MobilePlatform};
#[cfg(target_os = "ios")]
use std::sync::atomic::{AtomicBool, Ordering};
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

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatModelResponse {
    id: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatModelsResponse {
    data: Vec<ChatModelResponse>,
    default_model: String,
}

impl From<AccountChatModels> for ChatModelsResponse {
    fn from(models: AccountChatModels) -> Self {
        Self {
            data: models
                .data
                .into_iter()
                .map(|model| ChatModelResponse { id: model.id })
                .collect(),
            default_model: models.default_model,
        }
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatResponse {
    content: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PreferenceSchemaResponse {
    fields: BTreeMap<String, msime_client_core::account::AccountPreferenceField>,
    maximum_bytes: usize,
    update_mode: String,
    revision_required: bool,
}

impl From<AccountPreferenceSchema> for PreferenceSchemaResponse {
    fn from(schema: AccountPreferenceSchema) -> Self {
        Self {
            fields: schema.fields,
            maximum_bytes: schema.maximum_bytes,
            update_mode: schema.update_mode,
            revision_required: schema.revision_required,
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
type CommunityService = BackendCommunitySkinService<BackendAccountClient, IosAccountStorage<Wry>>;
#[cfg(target_os = "ios")]
type CommunityResourceService =
    BackendCommunityResourceService<BackendAccountClient, IosAccountStorage<Wry>>;
#[cfg(target_os = "ios")]
type AiSkinService = BackendAiSkinService<BackendAccountClient, IosAccountStorage<Wry>>;

#[cfg(target_os = "ios")]
pub struct AccountState {
    session: Arc<Session>,
    platform: MobilePlatform<Wry>,
    community: Arc<CommunityService>,
    resources: Arc<CommunityResourceService>,
    ai_skin: Arc<AiSkinService>,
    ai_skin_requests: Arc<std::sync::Mutex<std::collections::HashMap<String, Arc<AtomicBool>>>>,
}

#[cfg(target_os = "ios")]
pub fn setup(app: &AppHandle<Wry>) -> Result<(), AccountError> {
    let platform = app
        .try_state::<MobilePlatform<Wry>>()
        .ok_or(AccountError::Storage)?
        .inner()
        .clone();
    let client = BackendAccountClient::new()?;
    let session = Arc::new(BackendAccountSession::new(
        client.clone(),
        IosAccountStorage(platform.clone()),
    ));
    let community = Arc::new(BackendCommunitySkinService::new(
        client,
        Arc::clone(&session),
    ));
    let resources = Arc::new(BackendCommunityResourceService::new(
        BackendAccountClient::new()?,
        Arc::clone(&session),
    ));
    let ai_skin = Arc::new(BackendAiSkinService::new(
        BackendAccountClient::new()?,
        Arc::clone(&session),
    ));
    app.manage(AccountState {
        session,
        platform,
        community,
        resources,
        ai_skin,
        ai_skin_requests: Arc::new(std::sync::Mutex::new(std::collections::HashMap::new())),
    });
    Ok(())
}

#[cfg(target_os = "ios")]
fn ai_command_error(
    operation: &'static str,
    error: crate::mobile_ai::Error,
) -> super::CommandError {
    super::CommandError {
        code: match (operation, error) {
            ("models", crate::mobile_ai::Error::Invalid) => "ai_models_invalid",
            ("models", crate::mobile_ai::Error::Unavailable) => "ai_models_unavailable",
            ("test", crate::mobile_ai::Error::Invalid) => "ai_test_invalid",
            ("test", crate::mobile_ai::Error::Unavailable) => "ai_test_unavailable",
            _ => "ai_unavailable",
        },
    }
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn ai_models(
    endpoint: String,
    token: String,
) -> Result<Vec<String>, super::CommandError> {
    tauri::async_runtime::spawn_blocking(move || {
        crate::mobile_ai::fetch_models(&endpoint, &token)
            .map_err(|error| ai_command_error("models", error))
    })
    .await
    .map_err(|_| super::CommandError {
        code: "ai_models_unavailable",
    })?
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn ai_test(
    endpoint: String,
    model: String,
    prompt: String,
    token: String,
    text: String,
) -> Result<String, super::CommandError> {
    tauri::async_runtime::spawn_blocking(move || {
        crate::mobile_ai::polish(&endpoint, &model, &prompt, &token, &text)
            .map_err(|error| ai_command_error("test", error))
    })
    .await
    .map_err(|_| super::CommandError {
        code: "ai_test_unavailable",
    })?
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
pub async fn account_apple_login(
    state: State<'_, AccountState>,
) -> Result<StatusResponse, super::CommandError> {
    let session = Arc::clone(&state.session);
    let challenge = tauri::async_runtime::spawn_blocking(move || session.request_code("apple", ""))
        .await
        .map_err(|_| super::CommandError {
            code: "account_unavailable",
        })?
        .map_err(|error| super::CommandError { code: error.code() })?;
    let nonce = challenge.nonce.ok_or(super::CommandError {
        code: "apple_sign_in",
    })?;
    let credential = state
        .platform
        .sign_in_with_apple(&challenge.challenge_id, &nonce)
        .await
        .map_err(|_| super::CommandError {
            code: "apple_sign_in",
        })?;
    call(state, move |session| {
        session
            .sign_in_apple(&challenge.challenge_id, &credential)
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
pub async fn account_chat_models(
    state: State<'_, AccountState>,
) -> Result<ChatModelsResponse, super::CommandError> {
    call(state, |session| session.chat_models().map(Into::into)).await
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn account_chat(
    state: State<'_, AccountState>,
    messages: Vec<AccountChatMessage>,
    model: String,
) -> Result<ChatResponse, super::CommandError> {
    call(state, move |session| {
        session
            .chat(&messages, &model)
            .map(|content| ChatResponse { content })
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

#[cfg(target_os = "ios")]
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

#[cfg(target_os = "ios")]
fn ai_skin_error(error: AiSkinError) -> super::CommandError {
    let code = match error {
        AiSkinError::Cancelled => "ai_skin_cancelled",
        AiSkinError::InvalidResponse => "ai_skin_invalid",
        AiSkinError::Account(error) => error.code(),
    };
    super::CommandError { code }
}

#[cfg(target_os = "ios")]
fn valid_ai_skin_request_id(value: &str) -> bool {
    (1..=96).contains(&value.len())
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
}

#[cfg(target_os = "ios")]
#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct AiSkinProgress {
    request_id: String,
    completed: usize,
}

#[cfg(target_os = "ios")]
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
            let _ = tauri::Emitter::emit(
                &progress_app,
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

#[cfg(target_os = "ios")]
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

#[cfg(target_os = "ios")]
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

#[cfg(target_os = "ios")]
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

#[cfg(target_os = "ios")]
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

#[cfg(target_os = "ios")]
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

#[cfg(target_os = "ios")]
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CommunitySkinDownloadResponse {
    skin: SavedTouchKeyboardSkin,
    trial: KeyboardSkinTrial,
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn community_skin_list(
    state: State<'_, AccountState>,
    offset: usize,
    search: String,
) -> Result<CommunitySkinPage, super::CommandError> {
    community_call(state, move |service| service.list(offset, &search)).await
}

#[cfg(target_os = "ios")]
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

#[cfg(target_os = "ios")]
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

#[cfg(target_os = "ios")]
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

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn community_skin_publish(
    state: State<'_, AccountState>,
    id: String,
    name: String,
    description: String,
    design: msime_client_core::preferences::TouchKeyboardSkinDesign,
) -> Result<(), super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError {
        code: "community_invalid",
    })?;
    community_call(state, move |service| {
        service.publish(id, &name, &description, &design)
    })
    .await
}

#[cfg(target_os = "ios")]
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

#[cfg(target_os = "ios")]
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

#[cfg(target_os = "ios")]
fn resource_scope(value: &str) -> Result<CommunityResourceScope, super::CommandError> {
    match value {
        "" => Ok(CommunityResourceScope::All),
        "mine" => Ok(CommunityResourceScope::Mine),
        "saved" => Ok(CommunityResourceScope::Saved),
        _ => Err(super::CommandError {
            code: "community_invalid",
        }),
    }
}

#[cfg(target_os = "ios")]
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
        .map_err(|_| super::CommandError {
            code: "community_unavailable",
        })?
        .map_err(community_error)
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn community_resource_list(
    state: State<'_, AccountState>,
    kind: CommunityResourceKind,
    scope: String,
    search: String,
    offset: usize,
) -> Result<CommunityResourcePage, super::CommandError> {
    let scope = resource_scope(&scope)?;
    resource_call(state, move |service| {
        service.list(kind, scope, &search, offset)
    })
    .await
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn community_resource_detail(
    state: State<'_, AccountState>,
    id: String,
) -> Result<CommunityResource, super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError {
        code: "community_invalid",
    })?;
    resource_call(state, move |service| service.detail(id)).await
}

#[cfg(target_os = "ios")]
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
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError {
        code: "community_invalid",
    })?;
    resource_call(state, move |service| {
        service.publish(id, kind, &name, &description, &content, revision)
    })
    .await
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn community_resource_apply(
    state: State<'_, AccountState>,
    id: String,
    resource_revision: u32,
) -> Result<CommunityResourceApplication, super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError {
        code: "community_invalid",
    })?;
    resource_call(state, move |service| service.apply(id, resource_revision)).await
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn community_resource_save(
    state: State<'_, AccountState>,
    id: String,
    saved: bool,
) -> Result<(), super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError {
        code: "community_invalid",
    })?;
    resource_call(state, move |service| service.save(id, saved)).await
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn community_resource_rate(
    state: State<'_, AccountState>,
    id: String,
    stars: u8,
) -> Result<(), super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError {
        code: "community_invalid",
    })?;
    resource_call(state, move |service| service.rate(id, stars)).await
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn community_resource_unpublish(
    state: State<'_, AccountState>,
    id: String,
) -> Result<(), super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError {
        code: "community_invalid",
    })?;
    resource_call(state, move |service| service.delete(id)).await
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn community_resource_store_reply(
    library: State<'_, CommunityResourceLibraryStore>,
    item: CommunityResource,
) -> Result<(), super::CommandError> {
    let library = library.inner().clone();
    tauri::async_runtime::spawn_blocking(move || library.save_reply(item))
        .await
        .map_err(|_| super::CommandError {
            code: "community_storage",
        })?
        .map_err(resource_library_error)
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn community_resource_remove_reply(
    library: State<'_, CommunityResourceLibraryStore>,
    id: String,
) -> Result<(), super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError {
        code: "community_invalid",
    })?;
    let library = library.inner().clone();
    tauri::async_runtime::spawn_blocking(move || library.remove(id))
        .await
        .map_err(|_| super::CommandError {
            code: "community_storage",
        })?
        .map_err(resource_library_error)
}

#[cfg(target_os = "ios")]
pub async fn cloud_clipboard_request(
    state: State<'_, AccountState>,
    action: Value,
) -> Result<Value, super::CommandError> {
    let operation = action
        .get("operation")
        .and_then(Value::as_str)
        .ok_or(super::CommandError {
            code: "invalid_cloud_clipboard",
        })?;
    match operation {
        "list" => {
            let search = action
                .get("search")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_owned();
            call(state, move |session| {
                session.clipboard(&search).and_then(|page| {
                    serde_json::to_value(page).map_err(|_| AccountError::Unavailable)
                })
            })
            .await
        }
        "set_enabled" => {
            let enabled =
                action
                    .get("enabled")
                    .and_then(Value::as_bool)
                    .ok_or(super::CommandError {
                        code: "invalid_cloud_clipboard",
                    })?;
            call(state, move |session| {
                session
                    .set_clipboard_enabled(enabled)
                    .map(|()| serde_json::json!({ "enabled": enabled }))
            })
            .await
        }
        "add" => {
            let text = action
                .get("text")
                .and_then(Value::as_str)
                .ok_or(super::CommandError {
                    code: "invalid_cloud_clipboard",
                })?
                .to_owned();
            call(state, move |session| {
                session.add_clipboard(&text).and_then(|item| {
                    serde_json::to_value(item).map_err(|_| AccountError::Unavailable)
                })
            })
            .await
        }
        "delete" => {
            let id = action
                .get("id")
                .and_then(Value::as_str)
                .ok_or(super::CommandError {
                    code: "invalid_cloud_clipboard",
                })?
                .to_owned();
            call(state, move |session| {
                session
                    .delete_clipboard(Some(&id))
                    .map(|()| serde_json::json!({}))
            })
            .await
        }
        _ => Err(super::CommandError {
            code: "invalid_cloud_clipboard",
        }),
    }
}

#[cfg(target_os = "ios")]
fn dictionary_kind(value: &str) -> Result<DictionaryKind, super::CommandError> {
    match value {
        "pinyin" => Ok(DictionaryKind::Pinyin),
        "wubi" => Ok(DictionaryKind::Wubi),
        "quick" => Ok(DictionaryKind::Quick),
        "english" => Ok(DictionaryKind::English),
        _ => Err(super::CommandError {
            code: "invalid_cloud_dictionary",
        }),
    }
}

#[cfg(target_os = "ios")]
pub async fn cloud_dictionary_request(
    state: State<'_, AccountState>,
    action: Value,
) -> Result<Value, super::CommandError> {
    use msime_host_api::cloud_dictionary::CloudDictionaryRequest;
    let request: CloudDictionaryRequest =
        serde_json::from_value(action).map_err(|_| super::CommandError {
            code: "invalid_cloud_dictionary",
        })?;
    match request {
        CloudDictionaryRequest::List {
            kind,
            offset,
            search,
        } => {
            let kind = dictionary_kind(&kind)?;
            call(state, move |session| {
                session.dictionary(kind, &search, offset).and_then(|page| {
                    serde_json::to_value(page).map_err(|_| AccountError::Unavailable)
                })
            })
            .await
        }
        CloudDictionaryRequest::Catalog {
            kind,
            code,
            offset,
            scheme,
            profile,
        } => {
            let kind = dictionary_kind(&kind)?;
            call(state, move |session| {
                session
                    .dictionary_catalog(kind, &code, offset, &scheme, &profile)
                    .and_then(|page| {
                        serde_json::to_value(serde_json::json!({
                "catalog_entries": page.entries, "has_more": page.has_more, "offset": page.offset,
                "revision": page.revision, "normalized": page.normalized,
            })).map_err(|_| AccountError::Unavailable)
                    })
            })
            .await
        }
        CloudDictionaryRequest::Changes { after, limit } => {
            call(state, move |session| {
                session.dictionary_changes(after, limit).and_then(|page| {
                    serde_json::to_value(page).map_err(|_| AccountError::Unavailable)
                })
            })
            .await
        }
        CloudDictionaryRequest::Add {
            kind,
            code,
            word,
            weight,
        } => {
            let kind = dictionary_kind(&kind)?;
            call(state, move |session| {
                session
                    .add_dictionary(kind, &code, &word, weight)
                    .and_then(|change| {
                        serde_json::to_value(change).map_err(|_| AccountError::Unavailable)
                    })
            })
            .await
        }
        CloudDictionaryRequest::Update {
            kind,
            id,
            code,
            word,
            weight,
            revision,
        } => {
            let kind = dictionary_kind(&kind)?;
            call(state, move |session| {
                session
                    .update_dictionary(kind, &id, &code, &word, weight, revision)
                    .and_then(|change| {
                        serde_json::to_value(change).map_err(|_| AccountError::Unavailable)
                    })
            })
            .await
        }
        CloudDictionaryRequest::EditCatalog {
            kind,
            code,
            word,
            revision,
            replacement,
        } => {
            let kind = dictionary_kind(&kind)?;
            let replacement = replacement.map(|value| (value.code, value.word, value.weight));
            call(state, move |session| {
                let replacement = replacement
                    .as_ref()
                    .map(|(code, word, weight)| (code.as_str(), word.as_str(), *weight));
                session
                    .edit_dictionary_catalog(kind, &code, &word, revision, replacement)
                    .and_then(|change| {
                        serde_json::to_value(change).map_err(|_| AccountError::Unavailable)
                    })
            })
            .await
        }
        CloudDictionaryRequest::Candidates {
            text,
            kind,
            scheme,
            profile,
            limit,
        } => {
            let query = AccountCandidateQuery {
                text,
                kind,
                scheme,
                profile,
                limit,
            };
            call(state, move |session| {
                session.personal_candidates(&query).and_then(|result| {
                    serde_json::to_value(result).map_err(|_| AccountError::Unavailable)
                })
            })
            .await
        }
        CloudDictionaryRequest::Rank {
            text,
            kind,
            scheme,
            profile,
            limit,
            code,
            word,
            revision,
            mode,
            linear_step,
            trigger_count,
            force_top,
        } => {
            let query = AccountCandidateQuery {
                text,
                kind,
                scheme,
                profile,
                limit,
            };
            call(state, move |session| session.rank_candidate(&query, &code, &word, revision, &mode, linear_step, trigger_count, force_top).map(|result| serde_json::json!({
                "revision": result.revision, "changed": result.changed, "selection_count": result.selection.count,
            }))).await
        }
        CloudDictionaryRequest::RemoveCandidate {
            text,
            kind,
            scheme,
            profile,
            limit,
            code,
            word,
            revision,
        } => {
            let query = AccountCandidateQuery {
                text,
                kind,
                scheme,
                profile,
                limit,
            };
            call(state, move |session| {
                session
                    .remove_candidate(&query, &code, &word, revision)
                    .and_then(|result| {
                        serde_json::to_value(result).map_err(|_| AccountError::Unavailable)
                    })
            })
            .await
        }
        CloudDictionaryRequest::FixedPositions { context, offset } => {
            call(state, move |session| {
                session
                    .fixed_positions(&context, offset)
                    .and_then(|result| {
                        serde_json::to_value(result).map_err(|_| AccountError::Unavailable)
                    })
            })
            .await
        }
        CloudDictionaryRequest::SetFixedPosition {
            context,
            code,
            word,
            position,
            revision,
        } => {
            call(state, move |session| {
                session
                    .set_fixed_position(&context, &code, &word, position, revision)
                    .and_then(|result| {
                        serde_json::to_value(result).map_err(|_| AccountError::Unavailable)
                    })
            })
            .await
        }
        CloudDictionaryRequest::Delete { kind, id, revision } => {
            let kind = dictionary_kind(&kind)?;
            call(state, move |session| {
                session
                    .delete_dictionary(kind, &id, revision)
                    .and_then(|change| {
                        serde_json::to_value(change).map_err(|_| AccountError::Unavailable)
                    })
            })
            .await
        }
        CloudDictionaryRequest::Import { kind, format, text } => {
            let kind = dictionary_kind(&kind)?;
            call(state, move |session| {
                session
                    .import_dictionary(kind, &format, &text)
                    .and_then(|result| {
                        serde_json::to_value(result).map_err(|_| AccountError::Unavailable)
                    })
            })
            .await
        }
        CloudDictionaryRequest::Export { kind, format } => {
            let kind = dictionary_kind(&kind)?;
            call(state, move |session| session.export_dictionary(kind, &format).map(|result| serde_json::json!({ "text": result.text, "filename": result.filename }))).await
        }
        CloudDictionaryRequest::SnapshotPreview
        | CloudDictionaryRequest::SnapshotExport
        | CloudDictionaryRequest::SnapshotRestorePreview { .. }
        | CloudDictionaryRequest::SnapshotRestore { .. }
        | CloudDictionaryRequest::SnapshotRestoreNative { .. }
        | CloudDictionaryRequest::SnapshotEnqueue { .. }
        | CloudDictionaryRequest::SnapshotStatus
        | CloudDictionaryRequest::SnapshotCancel => Err(super::CommandError {
            code: "invalid_cloud_dictionary",
        }),
    }
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn account_preferences_schema(
    state: State<'_, AccountState>,
) -> Result<PreferenceSchemaResponse, super::CommandError> {
    call(state, |session| session.preference_schema().map(Into::into)).await
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn account_preferences_load(
    state: State<'_, AccountState>,
) -> Result<AccountPreferences, super::CommandError> {
    call(state, |session| session.preferences()).await
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn account_preferences_upload(
    state: State<'_, AccountState>,
    store: State<'_, Arc<PreferencesStore>>,
) -> Result<AccountPreferences, super::CommandError> {
    let session = Arc::clone(&state.session);
    let platform = state.platform.clone();
    let store = store.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        let schema = session.preference_schema()?;
        let cloud = session.preferences()?;
        let native = platform
            .load_keyboard_preferences()
            .map_err(|_| AccountError::Storage)?;
        let local = store.load().map_err(|_| AccountError::Storage)?;
        let values = account_preferences::local_account_preferences(
            &native,
            &local.preferences.custom_touch_keyboard_skin,
        )?
        .into_iter()
        .filter(|(key, _)| schema.fields.contains_key(key))
        .collect::<BTreeMap<_, _>>();
        if values.is_empty() {
            return Err(AccountError::Unavailable);
        }
        let merged = merge_account_preferences(&cloud, &values, &schema)?;
        session.put_preferences(&merged)
    })
    .await
    .map_err(|_| super::CommandError {
        code: "account_unavailable",
    })?
    .map_err(|error| super::CommandError { code: error.code() })
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn account_preferences_apply(
    state: State<'_, AccountState>,
    store: State<'_, Arc<PreferencesStore>>,
    user_id: String,
    preferences: AccountPreferences,
) -> Result<(), super::CommandError> {
    let session = Arc::clone(&state.session);
    let platform = state.platform.clone();
    let store = store.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        session.credentials(None, Some(&user_id))?;
        let plan = account_preferences::IosPreferencePlan::from_cloud(&preferences)?;
        let local = store.load().map_err(|_| AccountError::Storage)?;
        let previous_native = platform
            .load_keyboard_preferences()
            .map_err(|_| AccountError::Storage)?;
        let requested = plan.requested_native(&previous_native)?;
        let saved_native = platform
            .save_keyboard_preferences(&requested)
            .map_err(|_| AccountError::Storage)?;
        let mut next = local.preferences.clone();
        if let Err(error) = plan.apply_shared(&saved_native, &mut next) {
            let _ = platform.save_keyboard_preferences(&previous_native);
            return Err(error);
        }
        if store.save(local.revision, next).is_err() {
            let _ = platform.save_keyboard_preferences(&previous_native);
            return Err(AccountError::Storage);
        }
        Ok::<(), AccountError>(())
    })
    .await
    .map_err(|_| super::CommandError {
        code: "account_unavailable",
    })?
    .map_err(|error| super::CommandError { code: error.code() })
}

#[cfg(target_os = "ios")]
#[derive(serde::Deserialize, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MobileKeyboardFeedback {
    pub sound_enabled: bool,
    pub haptics_enabled: bool,
    pub haptic_strength: String,
}

#[cfg(target_os = "ios")]
#[derive(serde::Deserialize)]
pub struct MobileKeyboardFeedbackRequest {
    pub settings: MobileKeyboardFeedback,
}

#[cfg(target_os = "ios")]
#[derive(serde::Deserialize)]
pub struct MobileKeyboardFeedbackPreviewRequest {
    pub strength: String,
}

#[cfg(target_os = "ios")]
fn keyboard_feedback(native: &IosKeyboardPreferences) -> MobileKeyboardFeedback {
    MobileKeyboardFeedback {
        sound_enabled: native.sound_enabled,
        haptics_enabled: native.haptics_enabled,
        haptic_strength: native.haptic_strength.clone(),
    }
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn mobile_keyboard_feedback_load(
    state: State<'_, AccountState>,
) -> Result<MobileKeyboardFeedback, super::CommandError> {
    let platform = state.platform.clone();
    tauri::async_runtime::spawn_blocking(move || {
        let native = platform
            .load_keyboard_preferences()
            .map_err(|_| super::CommandError {
                code: "feedback_storage",
            })?;
        Ok(keyboard_feedback(&native))
    })
    .await
    .map_err(|_| super::CommandError {
        code: "feedback_storage",
    })?
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn mobile_keyboard_feedback_save(
    state: State<'_, AccountState>,
    request: MobileKeyboardFeedbackRequest,
) -> Result<MobileKeyboardFeedback, super::CommandError> {
    if !matches!(
        request.settings.haptic_strength.as_str(),
        "light" | "medium" | "strong"
    ) {
        return Err(super::CommandError {
            code: "invalid_feedback",
        });
    }
    let platform = state.platform.clone();
    tauri::async_runtime::spawn_blocking(move || {
        let mut native = platform
            .load_keyboard_preferences()
            .map_err(|_| super::CommandError {
                code: "feedback_storage",
            })?;
        native.sound_enabled = request.settings.sound_enabled;
        native.haptics_enabled = request.settings.haptics_enabled;
        native.haptic_strength = request.settings.haptic_strength.clone();
        let saved =
            platform
                .save_keyboard_preferences(&native)
                .map_err(|_| super::CommandError {
                    code: "feedback_storage",
                })?;
        Ok(keyboard_feedback(&saved))
    })
    .await
    .map_err(|_| super::CommandError {
        code: "feedback_storage",
    })?
}

#[cfg(target_os = "ios")]
#[tauri::command]
pub async fn mobile_keyboard_feedback_preview(
    state: State<'_, AccountState>,
    request: MobileKeyboardFeedbackPreviewRequest,
) -> Result<(), super::CommandError> {
    if !matches!(request.strength.as_str(), "light" | "medium" | "strong") {
        return Err(super::CommandError {
            code: "invalid_feedback",
        });
    }
    state
        .platform
        .preview_keyboard_haptics(&request.strength)
        .map_err(|_| super::CommandError {
            code: "feedback_preview",
        })
}

#[cfg(test)]
mod tests {
    use super::{
        providers_response, ChallengeResponse, ChatModelsResponse, ChatResponse,
        PreferenceSchemaResponse, ProfileResponse, StatusResponse,
    };
    use msime_client_core::account::{
        AccountChallenge, AccountChatModel, AccountChatModels, AccountPreferenceField,
        AccountPreferenceSchema, AccountProfile, AccountProfileIdentity, AccountUser,
    };
    use serde_json::json;
    use std::collections::{BTreeMap, HashMap};

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

    #[test]
    fn chat_responses_match_the_shared_webview_contract() {
        let models = ChatModelsResponse::from(AccountChatModels {
            data: vec![AccountChatModel {
                id: "synthetic-model".into(),
            }],
            default_model: "synthetic-model".into(),
        });
        assert_eq!(
            serde_json::to_value(models).unwrap(),
            json!({"data":[{"id":"synthetic-model"}],"defaultModel":"synthetic-model"})
        );

        let response = ChatResponse {
            content: "synthetic-response".into(),
        };
        assert_eq!(
            serde_json::to_value(response).unwrap(),
            json!({"content":"synthetic-response"})
        );
    }

    #[test]
    fn preference_schema_response_matches_the_shared_webview_contract() {
        let response = PreferenceSchemaResponse::from(AccountPreferenceSchema {
            fields: BTreeMap::from([(
                "platform.ios.nine_key".into(),
                AccountPreferenceField {
                    value_type: "boolean".into(),
                },
            )]),
            maximum_bytes: 65_536,
            update_mode: "replace".into(),
            revision_required: true,
        });
        assert_eq!(
            serde_json::to_value(response).unwrap(),
            json!({
                "fields":{"platform.ios.nine_key":{"type":"boolean"}},
                "maximumBytes":65536,
                "updateMode":"replace",
                "revisionRequired":true
            })
        );
    }
}
