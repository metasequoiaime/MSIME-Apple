use msime_client_core::account::{
    merge_account_preferences, validate_account_preferences, AccountChallenge, AccountError,
    AccountPreferenceSchema, AccountPreferenceValue, AccountPreferences, AccountProfile,
    AccountSessionStorage, AccountUser, BackendAccountClient, BackendAccountSession,
    SavedAccountSession,
};
use msime_client_core::ai_skin::{AiSkinError, AiSkinProposal, BackendAiSkinService};
use msime_client_core::cloud_dictionary::DictionaryKind;
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
use msime_client_core::preferences::{
    InputScheme, Preferences, PreferencesSnapshot, PreferencesStore, ShuangpinProfile, ThemeMode,
    TouchKeyboardLayout, TouchKeyboardSkin, TouchKeyboardSkinDesign,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{BTreeMap, HashMap};
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

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct FeedbackSettings {
    sound_enabled: bool,
    haptics_enabled: bool,
    haptic_strength: String,
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
    pub(crate) platform: PluginHandle<Wry>,
    feedback: PluginHandle<Wry>,
    community: Arc<CommunityService>,
    resources: Arc<CommunityResourceService>,
    ai_skin: Arc<AiSkinService>,
    ai_skin_requests: Arc<Mutex<HashMap<String, Arc<AtomicBool>>>>,
}

pub fn init() -> TauriPlugin<Wry> {
    Builder::new("account-storage")
        .setup(|app, api| {
            let handle = api.register_android_plugin("app.msime.client", "AccountPlugin")?;
            let platform = handle.clone();
            let feedback = handle.clone();
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
                platform,
                feedback,
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

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppIconResponse {
    pub supported: bool,
    pub selected: String,
}

#[derive(Serialize)]
struct AppIconRequest<'a> {
    style: &'a str,
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

#[derive(Clone, Serialize)]
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
            let enabled = action
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
            call(state, move |session| {
                session.export_dictionary(kind, &format).map(|result| {
                    serde_json::json!({
                        "text": result.text,
                        "filename": result.filename,
                    })
                })
            })
            .await
        }
        CloudDictionaryRequest::Changes { .. } => Err(super::CommandError {
            code: "cloud_dictionary_unavailable",
        }),
    }
}

#[tauri::command]
pub async fn app_icon_info(
    state: State<'_, AccountState>,
) -> Result<AppIconResponse, super::CommandError> {
    let plugin = state.platform.clone();
    tauri::async_runtime::spawn_blocking(move || {
        plugin
            .run_mobile_plugin::<AppIconResponse>("appIconInfo", ())
            .map_err(|_| super::CommandError { code: "app_icon" })
    })
    .await
    .map_err(|_| super::CommandError { code: "app_icon" })?
}

#[tauri::command]
pub async fn app_icon_set(
    state: State<'_, AccountState>,
    style: String,
) -> Result<AppIconResponse, super::CommandError> {
    if !matches!(style.as_str(), "classic" | "forest" | "sky" | "dusk" | "vermilion") {
        return Err(super::CommandError {
            code: "invalid_app_icon",
        });
    }
    let plugin = state.platform.clone();
    tauri::async_runtime::spawn_blocking(move || {
        plugin
            .run_mobile_plugin::<AppIconResponse>("setAppIcon", AppIconRequest { style: &style })
            .map_err(|_| super::CommandError { code: "app_icon" })
    })
    .await
    .map_err(|_| super::CommandError { code: "app_icon" })?
}

fn insert_string(settings: &mut BTreeMap<String, AccountPreferenceValue>, key: &str, value: &str) {
    settings.insert(
        key.to_owned(),
        AccountPreferenceValue::String(value.to_owned()),
    );
}

fn insert_bool(settings: &mut BTreeMap<String, AccountPreferenceValue>, key: &str, value: bool) {
    settings.insert(key.to_owned(), AccountPreferenceValue::Boolean(value));
}

fn insert_integer(settings: &mut BTreeMap<String, AccountPreferenceValue>, key: &str, value: i64) {
    settings.insert(key.to_owned(), AccountPreferenceValue::Integer(value));
}

fn local_account_preferences(
    snapshot: &PreferencesSnapshot,
    feedback: &PluginHandle<Wry>,
) -> Result<BTreeMap<String, AccountPreferenceValue>, AccountError> {
    let preferences = &snapshot.preferences;
    let mut settings = BTreeMap::new();
    insert_string(
        &mut settings,
        "input.schema",
        match preferences.scheme {
            InputScheme::Quanpin => "quanpin",
            InputScheme::Shuangpin => "shuangpin",
            InputScheme::Wubi => "wubi",
            InputScheme::Japanese => "japanese",
        },
    );
    insert_string(
        &mut settings,
        "input.character_set",
        if preferences.traditional_chinese_output {
            "traditional"
        } else {
            "simplified"
        },
    );
    insert_string(
        &mut settings,
        "input.shuangpin_schema",
        match preferences.shuangpin_profile {
            ShuangpinProfile::Xiaohe => "xiaohe",
            ShuangpinProfile::Ziranma => "ziranma",
            ShuangpinProfile::Shoudao => "shoudao",
            ShuangpinProfile::Microsoft => "microsoft",
        },
    );
    insert_bool(&mut settings, "input.learning", preferences.learning);
    insert_bool(
        &mut settings,
        "input.chinese_punctuation",
        preferences.chinese_punctuation,
    );
    insert_bool(
        &mut settings,
        "input.smart_punctuation",
        preferences.smart_punctuation,
    );
    insert_bool(
        &mut settings,
        "input.paired_punctuation",
        preferences.paired_punctuation,
    );
    insert_bool(
        &mut settings,
        "input.wubi_code_hint",
        preferences.wubi_code_hint.unwrap_or(true),
    );
    insert_string(
        &mut settings,
        "platform.android.keyboard_layout",
        match preferences.touch_keyboard_layout {
            TouchKeyboardLayout::TwentySixKey => "twenty_six_key",
            TouchKeyboardLayout::NineKey => "nine_key",
            TouchKeyboardLayout::Handwriting => "handwriting",
        },
    );
    insert_string(
        &mut settings,
        "platform.android.keyboard_skin",
        match preferences.touch_keyboard_skin {
            TouchKeyboardSkin::Forest => "forest",
            TouchKeyboardSkin::Ocean => "ocean",
            TouchKeyboardSkin::Rose => "rose",
            TouchKeyboardSkin::Porcelain => "porcelain",
            TouchKeyboardSkin::Typewriter => "typewriter",
            TouchKeyboardSkin::Candy => "candy",
            TouchKeyboardSkin::Midnight => "midnight",
            TouchKeyboardSkin::Blueprint => "blueprint",
            TouchKeyboardSkin::Custom => "custom",
        },
    );
    let custom_skin = serde_json::to_string(&preferences.custom_touch_keyboard_skin)
        .map_err(|_| AccountError::Invalid)?;
    insert_string(
        &mut settings,
        "platform.android.custom_keyboard_skin",
        &custom_skin,
    );
    insert_string(
        &mut settings,
        "platform.android.theme",
        match preferences.theme {
            ThemeMode::Dark => "dark",
            ThemeMode::Light => "light",
            ThemeMode::System => "system",
        },
    );
    insert_string(
        &mut settings,
        "platform.android.candidate_skin",
        &preferences.candidate_skin,
    );
    insert_integer(
        &mut settings,
        "platform.android.touch_key_spacing_tenths",
        i64::from(preferences.touch_key_spacing_tenths),
    );
    insert_integer(
        &mut settings,
        "platform.android.touch_row_spacing_tenths",
        i64::from(preferences.touch_row_spacing_tenths),
    );
    insert_integer(
        &mut settings,
        "platform.android.keyboard_height_adjustment",
        i64::from(preferences.touch_keyboard_height_adjustment),
    );
    insert_bool(
        &mut settings,
        "platform.android.voice_shortcut",
        preferences.touch_voice_shortcut,
    );

    let feedback = feedback
        .run_mobile_plugin::<FeedbackSettings>("loadFeedback", ())
        .map_err(|_| AccountError::Storage)?;
    insert_bool(
        &mut settings,
        "platform.android.sound_enabled",
        feedback.sound_enabled,
    );
    insert_bool(
        &mut settings,
        "platform.android.haptics_enabled",
        feedback.haptics_enabled,
    );
    insert_string(
        &mut settings,
        "platform.android.haptic_strength",
        &feedback.haptic_strength,
    );
    Ok(settings)
}

fn string_setting(
    settings: &BTreeMap<String, AccountPreferenceValue>,
    key: &str,
) -> Result<Option<String>, AccountError> {
    match settings.get(key) {
        None => Ok(None),
        Some(AccountPreferenceValue::String(value)) => Ok(Some(value.clone())),
        Some(_) => Ok(None),
    }
}

fn bool_setting(
    settings: &BTreeMap<String, AccountPreferenceValue>,
    key: &str,
) -> Result<Option<bool>, AccountError> {
    match settings.get(key) {
        None => Ok(None),
        Some(AccountPreferenceValue::Boolean(value)) => Ok(Some(*value)),
        Some(_) => Ok(None),
    }
}

fn integer_setting(
    settings: &BTreeMap<String, AccountPreferenceValue>,
    key: &str,
) -> Result<Option<i64>, AccountError> {
    match settings.get(key) {
        None => Ok(None),
        Some(AccountPreferenceValue::Integer(value)) => Ok(Some(*value)),
        Some(AccountPreferenceValue::Number(value)) if value.is_finite() => {
            if value.fract() == 0.0 {
                Ok(Some(*value as i64))
            } else {
                Err(AccountError::Invalid)
            }
        }
        Some(_) => Ok(None),
    }
}

fn apply_local_account_preferences(
    snapshot: &PreferencesSnapshot,
    cloud: &AccountPreferences,
    schema: &AccountPreferenceSchema,
    feedback: &PluginHandle<Wry>,
) -> Result<Preferences, AccountError> {
    validate_account_preferences(cloud)?;
    for (key, value) in &cloud.settings {
        if let Some(field) = schema.fields.get(key) {
            if field.value_type != value.kind()
                && !(field.value_type == "number" && value.kind() == "integer")
            {
                return Err(AccountError::Invalid);
            }
        }
    }
    let mut preferences = snapshot.preferences.clone();
    let values = &cloud.settings;
    let supports = |key: &str, expected: &str| -> Result<bool, AccountError> {
        match schema.fields.get(key) {
            None => Ok(false),
            Some(field)
                if field.value_type == expected
                    || ((expected == "number" || expected == "integer")
                        && matches!(field.value_type.as_str(), "integer" | "number")) =>
            {
                Ok(true)
            }
            Some(_) => Err(AccountError::Invalid),
        }
    };
    if let Some(value) = string_setting(values, "input.schema")? {
        if supports("input.schema", "string")? {
            preferences.scheme = match value.as_str() {
                "quanpin" => InputScheme::Quanpin,
                "shuangpin" => InputScheme::Shuangpin,
                "wubi" => InputScheme::Wubi,
                "japanese" => InputScheme::Japanese,
                _ => return Err(AccountError::Invalid),
            };
        }
    }
    if let Some(value) = string_setting(values, "input.character_set")? {
        if supports("input.character_set", "string")? {
            preferences.traditional_chinese_output = match value.as_str() {
                "traditional" => true,
                "simplified" => false,
                _ => return Err(AccountError::Invalid),
            };
        }
    }
    if let Some(value) = string_setting(values, "input.shuangpin_schema")? {
        if supports("input.shuangpin_schema", "string")? {
            preferences.shuangpin_profile = match value.as_str() {
                "xiaohe" => ShuangpinProfile::Xiaohe,
                "ziranma" => ShuangpinProfile::Ziranma,
                "shoudao" => ShuangpinProfile::Shoudao,
                "microsoft" => ShuangpinProfile::Microsoft,
                _ => return Err(AccountError::Invalid),
            };
        }
    }
    if let Some(value) = bool_setting(values, "input.learning")? {
        if supports("input.learning", "boolean")? {
            preferences.learning = value;
        }
    }
    if let Some(value) = bool_setting(values, "input.chinese_punctuation")? {
        if supports("input.chinese_punctuation", "boolean")? {
            preferences.chinese_punctuation = value;
        }
    }
    if let Some(value) = bool_setting(values, "input.smart_punctuation")? {
        if supports("input.smart_punctuation", "boolean")? {
            preferences.smart_punctuation = value;
        }
    }
    if let Some(value) = bool_setting(values, "input.paired_punctuation")? {
        if supports("input.paired_punctuation", "boolean")? {
            preferences.paired_punctuation = value;
        }
    }
    if let Some(value) = bool_setting(values, "input.wubi_code_hint")? {
        if supports("input.wubi_code_hint", "boolean")? {
            preferences.wubi_code_hint = Some(value);
        }
    }
    if let Some(value) = string_setting(values, "platform.android.keyboard_layout")? {
        if supports("platform.android.keyboard_layout", "string")? {
            preferences.touch_keyboard_layout = match value.as_str() {
                "twenty_six_key" => TouchKeyboardLayout::TwentySixKey,
                "nine_key" => TouchKeyboardLayout::NineKey,
                "handwriting" => TouchKeyboardLayout::Handwriting,
                _ => return Err(AccountError::Invalid),
            };
        }
    }
    if let Some(value) = string_setting(values, "platform.android.keyboard_skin")? {
        if supports("platform.android.keyboard_skin", "string")? {
            preferences.touch_keyboard_skin = match value.as_str() {
                "forest" => TouchKeyboardSkin::Forest,
                "ocean" => TouchKeyboardSkin::Ocean,
                "rose" => TouchKeyboardSkin::Rose,
                "porcelain" => TouchKeyboardSkin::Porcelain,
                "typewriter" => TouchKeyboardSkin::Typewriter,
                "candy" => TouchKeyboardSkin::Candy,
                "midnight" => TouchKeyboardSkin::Midnight,
                "blueprint" => TouchKeyboardSkin::Blueprint,
                "custom" => TouchKeyboardSkin::Custom,
                _ => return Err(AccountError::Invalid),
            };
        }
    }
    if let Some(value) = string_setting(values, "platform.android.custom_keyboard_skin")? {
        if supports("platform.android.custom_keyboard_skin", "string")? {
            preferences.custom_touch_keyboard_skin =
                serde_json::from_str(&value).map_err(|_| AccountError::Invalid)?;
        }
    }
    if let Some(value) = string_setting(values, "platform.android.theme")? {
        if supports("platform.android.theme", "string")? {
            preferences.theme = match value.as_str() {
                "dark" => ThemeMode::Dark,
                "light" => ThemeMode::Light,
                "system" => ThemeMode::System,
                _ => return Err(AccountError::Invalid),
            };
        }
    }
    if let Some(value) = string_setting(values, "platform.android.candidate_skin")? {
        if supports("platform.android.candidate_skin", "string")? {
            if value.is_empty() || value.len() > 128 || value.chars().any(char::is_control) {
                return Err(AccountError::Invalid);
            }
            preferences.candidate_skin = value;
        }
    }
    if let Some(value) = integer_setting(values, "platform.android.touch_key_spacing_tenths")? {
        if supports("platform.android.touch_key_spacing_tenths", "integer")? {
            preferences.touch_key_spacing_tenths =
                u8::try_from(value).map_err(|_| AccountError::Invalid)?;
        }
    }
    if let Some(value) = integer_setting(values, "platform.android.touch_row_spacing_tenths")? {
        if supports("platform.android.touch_row_spacing_tenths", "integer")? {
            preferences.touch_row_spacing_tenths =
                u8::try_from(value).map_err(|_| AccountError::Invalid)?;
        }
    }
    if let Some(value) = integer_setting(values, "platform.android.keyboard_height_adjustment")? {
        if supports("platform.android.keyboard_height_adjustment", "integer")? {
            preferences.touch_keyboard_height_adjustment =
                i8::try_from(value).map_err(|_| AccountError::Invalid)?;
        }
    }
    if let Some(value) = bool_setting(values, "platform.android.voice_shortcut")? {
        if supports("platform.android.voice_shortcut", "boolean")? {
            preferences.touch_voice_shortcut = value;
        }
    }

    let feedback_keys = [
        "platform.android.sound_enabled",
        "platform.android.haptics_enabled",
        "platform.android.haptic_strength",
    ];
    let mut feedback_values = if feedback_keys
        .iter()
        .any(|key| schema.fields.contains_key(*key) && values.contains_key(*key))
    {
        Some(
            feedback
                .run_mobile_plugin::<FeedbackSettings>("loadFeedback", ())
                .map_err(|_| AccountError::Storage)?,
        )
    } else {
        None
    };
    if let Some(value) = bool_setting(values, "platform.android.sound_enabled")? {
        if supports("platform.android.sound_enabled", "boolean")? {
            feedback_values
                .as_mut()
                .ok_or(AccountError::Storage)?
                .sound_enabled = value;
        }
    }
    if let Some(value) = bool_setting(values, "platform.android.haptics_enabled")? {
        if supports("platform.android.haptics_enabled", "boolean")? {
            feedback_values
                .as_mut()
                .ok_or(AccountError::Storage)?
                .haptics_enabled = value;
        }
    }
    if let Some(value) = string_setting(values, "platform.android.haptic_strength")? {
        if supports("platform.android.haptic_strength", "string")? {
            if !matches!(value.as_str(), "light" | "medium" | "strong") {
                return Err(AccountError::Invalid);
            }
            feedback_values
                .as_mut()
                .ok_or(AccountError::Storage)?
                .haptic_strength = value;
        }
    }
    if let Some(feedback_values) = feedback_values {
        let request = serde_json::json!({
            "soundEnabled": feedback_values.sound_enabled,
            "hapticsEnabled": feedback_values.haptics_enabled,
            "hapticStrength": feedback_values.haptic_strength,
        });
        feedback
            .run_mobile_plugin::<()>("saveFeedback", request)
            .map_err(|_| AccountError::Storage)?;
    }
    preferences.validate().map_err(|_| AccountError::Invalid)?;
    Ok(preferences)
}

#[tauri::command]
pub async fn account_preferences_schema(
    state: State<'_, AccountState>,
) -> Result<PreferenceSchemaResponse, super::CommandError> {
    call(state, |session| session.preference_schema().map(Into::into)).await
}

#[tauri::command]
pub async fn account_preferences_load(
    state: State<'_, AccountState>,
) -> Result<AccountPreferences, super::CommandError> {
    call(state, |session| session.preferences()).await
}

#[tauri::command]
pub async fn account_preferences_upload(
    state: State<'_, AccountState>,
    store: State<'_, Arc<PreferencesStore>>,
) -> Result<AccountPreferences, super::CommandError> {
    let session = Arc::clone(&state.session);
    let feedback = state.feedback.clone();
    let store = store.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        let schema = session.preference_schema()?;
        let cloud = session.preferences()?;
        let local = store.load().map_err(|_| AccountError::Storage)?;
        let values = local_account_preferences(&local, &feedback)?
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
    .map_err(|_| super::CommandError { code: "account_unavailable" })?
    .map_err(|error| super::CommandError { code: error.code() })
}

#[tauri::command]
pub async fn account_preferences_apply(
    state: State<'_, AccountState>,
    store: State<'_, Arc<PreferencesStore>>,
    user_id: String,
    preferences: AccountPreferences,
) -> Result<(), super::CommandError> {
    let session = Arc::clone(&state.session);
    let feedback = state.feedback.clone();
    let store = store.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        session.credentials(None, Some(&user_id))?;
        let schema = session.preference_schema()?;
        let local = store.load().map_err(|_| AccountError::Storage)?;
        let next = apply_local_account_preferences(&local, &preferences, &schema, &feedback)?;
        store
            .save(local.revision, next)
            .map_err(|_| AccountError::Storage)?;
        Ok::<(), AccountError>(())
    })
    .await
    .map_err(|_| super::CommandError { code: "account_unavailable" })?
    .map_err(|error| super::CommandError { code: error.code() })
}
