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
use msime_client_core::cloud_dictionary::DictionaryKind;
#[cfg(target_os = "ios")]
use msime_client_core::preferences::PreferencesStore;
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
pub struct AccountState {
    session: Arc<Session>,
    platform: MobilePlatform<Wry>,
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
            IosAccountStorage(platform.clone()),
        )),
        platform,
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
