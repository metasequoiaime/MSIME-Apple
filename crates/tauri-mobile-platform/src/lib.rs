use serde::{Deserialize, Serialize};
#[cfg(any(target_os = "ios", test))]
use serde_json::json;
use serde_json::Value;
use tauri::plugin::{Builder, TauriPlugin};
use tauri::Runtime;

#[cfg(any(target_os = "ios", target_os = "android"))]
use tauri::plugin::PluginHandle;
#[cfg(any(target_os = "ios", target_os = "android"))]
use tauri::Manager;

#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_plugin_msime_mobile_platform);

#[cfg(target_os = "android")]
#[derive(Clone)]
pub struct AndroidVoicePlatform<R: Runtime>(PluginHandle<R>);

#[cfg(target_os = "android")]
#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct AndroidVoiceRequest<'a> {
    request_id: &'a str,
    language: &'a str,
}

#[cfg(target_os = "android")]
#[derive(Clone, Debug, Deserialize)]
struct AndroidVoiceResponse {
    text: String,
}

#[cfg(any(target_os = "android", test))]
fn valid_android_voice_request(request_id: &str, language: &str) -> bool {
    !request_id.is_empty()
        && request_id.len() <= 64
        && request_id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-')
        && !language.is_empty()
        && language.len() <= 64
        && !language.chars().any(char::is_control)
}

#[cfg(target_os = "android")]
impl<R: Runtime> AndroidVoicePlatform<R> {
    pub async fn recognize_voice(&self, request_id: &str, language: &str) -> Result<String, ()> {
        if !valid_android_voice_request(request_id, language) {
            return Err(());
        }
        let response = self
            .0
            .run_mobile_plugin_async::<AndroidVoiceResponse>(
                "recognizeVoice",
                AndroidVoiceRequest {
                    request_id,
                    language,
                },
            )
            .await
            .map_err(|_| ())?;
        if response.text.chars().count() > 10_000 || response.text.contains('\0') {
            return Err(());
        }
        Ok(response.text)
    }

    pub fn stop_voice(&self, request_id: &str) -> Result<(), ()> {
        if !valid_android_voice_request(request_id, "und") {
            return Err(());
        }
        self.0
            .run_mobile_plugin("stopVoice", serde_json::json!({ "requestId": request_id }))
            .map_err(|_| ())
    }

    pub fn cancel_voice(&self, request_id: Option<&str>) -> Result<(), ()> {
        if request_id.is_some_and(|value| !valid_android_voice_request(value, "und")) {
            return Err(());
        }
        self.0
            .run_mobile_plugin(
                "cancelVoice",
                serde_json::json!({ "requestId": request_id }),
            )
            .map_err(|_| ())
    }

    pub fn save_voice_text(&self, text: &str) -> Result<(), ()> {
        if text.trim().is_empty() || text.chars().count() > 10_000 || text.contains('\0') {
            return Err(());
        }
        self.0
            .run_mobile_plugin("saveVoiceText", serde_json::json!({ "text": text }))
            .map_err(|_| ())
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AppIconInfo {
    pub supported: bool,
    pub selected: String,
}

const MAX_IOS_CUSTOM_KEYBOARD_SKIN_BYTES: usize = 800_000;
#[cfg(any(target_os = "ios", test))]
const MAX_IOS_CLIPBOARD_TEXT_UTF16_UNITS: usize = 4_000;
#[cfg(any(target_os = "ios", test))]
const MAX_IOS_VOICE_ENDPOINT_BYTES: usize = 2_048;
#[cfg(any(target_os = "ios", test))]
const MAX_IOS_VOICE_MODEL_BYTES: usize = 512;
#[cfg(any(target_os = "ios", test))]
const MAX_IOS_VOICE_TOKEN_BYTES: usize = 16 * 1024;
#[cfg(any(target_os = "ios", test))]
const MAX_IOS_VOICE_TEXT_CHARS: usize = 10_000;
#[cfg(any(target_os = "ios", test))]
const MAX_IOS_VOICE_HEADER_BYTES: usize = 8_192;
#[cfg(any(target_os = "ios", test))]
const MAX_IOS_VOICE_BOOSTING_TABLE_BYTES: usize = 4_096;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct IosKeyboardPreferences {
    pub input_scheme: String,
    pub traditional_chinese_output: bool,
    pub sound_enabled: bool,
    pub haptics_enabled: bool,
    pub haptic_strength: String,
    pub dictionary_learning: bool,
    pub keyboard_skin: String,
    pub custom_keyboard_skin: Option<String>,
}

/// The small, native-facing AI configuration shared by the Tauri settings app
/// and the keyboard extension. The extension deliberately receives only the
/// already-resolved token for the configured endpoint; the complete Rust
/// preferences document never crosses the plugin boundary.
#[cfg(any(target_os = "ios", test))]
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct IosKeyboardAiPreferences {
    pub enabled: bool,
    pub provider: String,
    pub endpoint: String,
    pub model: String,
    pub prompt: String,
    pub token: String,
}

#[cfg(any(target_os = "ios", test))]
impl IosKeyboardAiPreferences {
    pub fn is_valid(&self) -> bool {
        let bounded = |value: &str, limit: usize| {
            value.len() <= limit && !value.chars().any(char::is_control)
        };
        bounded(&self.provider, 64)
            && bounded(&self.endpoint, 2_048)
            && bounded(&self.model, 512)
            && bounded(&self.prompt, 16 * 1_024)
            && bounded(&self.token, 16 * 1_024)
            && (!self.enabled
                || (!self.provider.is_empty()
                    && !self.endpoint.trim().is_empty()
                    && !self.model.trim().is_empty()
                    && !self.prompt.trim().is_empty()
                    && !self.token.trim().is_empty()))
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct IosVoiceRequestHeader {
    pub name: String,
    pub value: String,
}

#[cfg(any(target_os = "ios", test))]
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct IosVoiceTranscriptionRequest {
    pub request_id: String,
    pub provider: String,
    pub endpoint: String,
    pub model: String,
    pub token: String,
    pub headers: Vec<IosVoiceRequestHeader>,
    pub enable_itn: bool,
    pub enable_punctuation: bool,
    pub enable_ddc: bool,
    pub boosting_table_id: String,
}

#[cfg(any(target_os = "ios", test))]
impl IosVoiceTranscriptionRequest {
    pub fn is_valid(&self) -> bool {
        let common = !self.request_id.is_empty()
            && self.request_id.len() <= 64
            && self
                .request_id
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-')
            && self.endpoint.len() <= MAX_IOS_VOICE_ENDPOINT_BYTES
            && !self.endpoint.chars().any(char::is_control)
            && self.model.len() <= MAX_IOS_VOICE_MODEL_BYTES
            && !self.model.chars().any(char::is_control)
            && self.token.len() <= MAX_IOS_VOICE_TOKEN_BYTES
            && !self.token.chars().any(char::is_control)
            && self.boosting_table_id.len() <= MAX_IOS_VOICE_BOOSTING_TABLE_BYTES
            && !self.boosting_table_id.chars().any(char::is_control);
        if !common {
            return false;
        }
        if matches!(self.provider.as_str(), "openai" | "siliconflow" | "groq") {
            return self.endpoint.starts_with("https://")
                && !self.model.trim().is_empty()
                && self.headers.is_empty()
                && self.boosting_table_id.is_empty();
        }
        self.provider == "doubao"
            && self.endpoint.starts_with("wss://")
            && self.model.is_empty()
            && self.token.is_empty()
            && valid_doubao_headers(&self.headers)
    }
}

#[cfg(any(target_os = "ios", test))]
fn valid_doubao_headers(headers: &[IosVoiceRequestHeader]) -> bool {
    if !(3..=4).contains(&headers.len())
        || headers.iter().any(|header| {
            !matches!(
                header.name.as_str(),
                "x-api-key"
                    | "x-api-app-key"
                    | "x-api-access-key"
                    | "x-api-resource-id"
                    | "x-api-request-id"
            ) || header.value.is_empty()
                || header.value.len() > MAX_IOS_VOICE_HEADER_BYTES
                || header.value.chars().any(char::is_control)
        })
    {
        return false;
    }
    let count = |name: &str| headers.iter().filter(|header| header.name == name).count();
    let shared = count("x-api-resource-id") == 1 && count("x-api-request-id") == 1;
    let api_key =
        count("x-api-key") == 1 && count("x-api-app-key") == 0 && count("x-api-access-key") == 0;
    let legacy =
        count("x-api-key") == 0 && count("x-api-app-key") == 1 && count("x-api-access-key") == 1;
    shared && (api_key || legacy)
}

#[cfg(any(target_os = "ios", test))]
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct IosVoiceTranscriptionResponse {
    pub text: String,
}

#[cfg(any(target_os = "ios", test))]
impl IosVoiceTranscriptionResponse {
    fn is_valid(&self) -> bool {
        self.text.chars().count() <= MAX_IOS_VOICE_TEXT_CHARS && !self.text.contains('\0')
    }
}

impl IosKeyboardPreferences {
    pub fn is_valid(&self) -> bool {
        matches!(
            self.input_scheme.as_str(),
            "quanpin"
                | "nineKey"
                | "shuangpin"
                | "ziranma"
                | "microsoft"
                | "shoudao"
                | "wubi"
                | "japaneseNineKey"
                | "japanese"
                | "handwriting"
                | "thoughtfulReply"
        ) && matches!(self.haptic_strength.as_str(), "light" | "medium" | "strong")
            && matches!(
                self.keyboard_skin.as_str(),
                "forest"
                    | "ocean"
                    | "rose"
                    | "porcelain"
                    | "typewriter"
                    | "candy"
                    | "midnight"
                    | "blueprint"
                    | "custom"
            )
            && self.custom_keyboard_skin.as_ref().is_none_or(|value| {
                value.len() <= MAX_IOS_CUSTOM_KEYBOARD_SKIN_BYTES
                    && serde_json::from_str::<Value>(value)
                        .is_ok_and(|document| document.is_object())
            })
    }
}

#[cfg(any(target_os = "ios", test))]
fn is_valid_ios_clipboard_text(value: &str) -> bool {
    !value.is_empty()
        && value.encode_utf16().count() <= MAX_IOS_CLIPBOARD_TEXT_UTF16_UNITS
        && !value.contains('\0')
}

#[cfg(target_os = "ios")]
#[derive(Serialize)]
struct AppIconRequest<'a> {
    style: &'a str,
}

#[cfg(target_os = "ios")]
#[derive(Deserialize)]
struct AccountSessionResponse {
    value: Option<String>,
}

#[cfg(target_os = "ios")]
#[derive(Deserialize)]
struct IosOnboardingStatusResponse {
    completed: bool,
}

#[cfg(target_os = "ios")]
#[derive(Serialize)]
struct AccountSessionRequest<'a> {
    value: &'a str,
}

#[cfg(target_os = "ios")]
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct AppleSignInRequest<'a> {
    challenge_id: &'a str,
    nonce: &'a str,
}

#[cfg(target_os = "ios")]
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct AppleSignInResponse {
    credential: String,
}

#[cfg(target_os = "ios")]
#[derive(Serialize)]
struct CopyTextRequest<'a> {
    text: &'a str,
}

#[cfg(target_os = "ios")]
#[derive(Serialize)]
struct SaveVoiceTextRequest<'a> {
    text: &'a str,
}

#[cfg(target_os = "ios")]
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct VoiceControlRequest<'a> {
    request_id: Option<&'a str>,
}

#[cfg(any(target_os = "ios", test))]
#[derive(Deserialize)]
struct LegacyAppleAccountSession {
    tokens: Value,
    #[serde(rename = "expiresAt")]
    expires_at: f64,
}

#[cfg(any(target_os = "ios", test))]
#[derive(Deserialize)]
struct LegacyAppleCommunitySession {
    access_token: String,
    refresh_token: String,
    user: Value,
    saved_at: Option<f64>,
    expires_in: Option<i64>,
}

#[cfg(any(target_os = "ios", test))]
const MAX_ACCOUNT_SESSION_BYTES: usize = 16 * 1024;
#[cfg(any(target_os = "ios", test))]
const APPLE_REFERENCE_DATE_UNIX_OFFSET_SECONDS: f64 = 978_307_200.0;

pub fn is_supported_app_icon_style(style: &str) -> bool {
    matches!(style, "classic" | "forest" | "sky" | "dusk" | "vermilion")
}

#[cfg(any(target_os = "ios", test))]
fn is_valid_account_session_payload(value: &str) -> bool {
    !value.is_empty() && value.len() <= MAX_ACCOUNT_SESSION_BYTES
}

#[cfg(any(target_os = "ios", test))]
fn apple_date_to_unix_millis(seconds: f64) -> Option<u64> {
    let milliseconds = (seconds + APPLE_REFERENCE_DATE_UNIX_OFFSET_SECONDS) * 1000.0;
    if !milliseconds.is_finite() || milliseconds < 0.0 || milliseconds > u64::MAX as f64 {
        return None;
    }
    Some(milliseconds.round() as u64)
}

#[cfg(any(target_os = "ios", test))]
fn migrated_account_session_payload(value: &str) -> Option<String> {
    let document: Value = serde_json::from_str(value).ok()?;
    if document.get("expires_at_unix_ms").is_some() {
        return None;
    }

    if document.get("expiresAt").is_some() {
        let legacy: LegacyAppleAccountSession = serde_json::from_value(document).ok()?;
        let expires_at_unix_ms = apple_date_to_unix_millis(legacy.expires_at)?;
        return serde_json::to_string(&json!({
            "tokens": legacy.tokens,
            "expires_at_unix_ms": expires_at_unix_ms,
        }))
        .ok();
    }

    if document.get("access_token").is_some() {
        let legacy: LegacyAppleCommunitySession = serde_json::from_value(document).ok()?;
        let expires_in = legacy.expires_in.unwrap_or(900);
        let expires_in = u64::try_from(expires_in).ok()?;
        let expires_at_unix_ms = match legacy.saved_at {
            Some(saved_at) => {
                apple_date_to_unix_millis(saved_at)?.checked_add(expires_in.checked_mul(1000)?)?
            }
            None => 0,
        };
        return serde_json::to_string(&json!({
            "tokens": {
                "access_token": legacy.access_token,
                "refresh_token": legacy.refresh_token,
                "token_type": "Bearer",
                "expires_in": expires_in,
                "user": legacy.user,
            },
            "expires_at_unix_ms": expires_at_unix_ms,
        }))
        .ok();
    }

    None
}

#[cfg(target_os = "ios")]
pub struct MobilePlatform<R: Runtime>(PluginHandle<R>);

#[cfg(target_os = "ios")]
impl<R: Runtime> Clone for MobilePlatform<R> {
    fn clone(&self) -> Self {
        Self(self.0.clone())
    }
}

#[cfg(target_os = "ios")]
impl<R: Runtime> MobilePlatform<R> {
    pub fn open_system_keyboard_settings(&self) -> Result<(), ()> {
        self.0
            .run_mobile_plugin("openSystemKeyboardSettings", ())
            .map_err(|_| ())
    }

    pub fn onboarding_completed(&self) -> Result<bool, ()> {
        self.0
            .run_mobile_plugin::<IosOnboardingStatusResponse>("onboardingStatus", ())
            .map(|response| response.completed)
            .map_err(|_| ())
    }

    pub fn complete_onboarding(&self) -> Result<(), ()> {
        self.0
            .run_mobile_plugin("completeOnboarding", ())
            .map_err(|_| ())
    }

    pub fn app_icon_info(&self) -> Result<AppIconInfo, ()> {
        self.0.run_mobile_plugin("appIconInfo", ()).map_err(|_| ())
    }

    pub fn set_app_icon(&self, style: &str) -> Result<AppIconInfo, ()> {
        self.0
            .run_mobile_plugin("setAppIcon", AppIconRequest { style })
            .map_err(|_| ())
    }

    pub fn load_account_session(&self) -> Result<Option<String>, ()> {
        let response = self
            .0
            .run_mobile_plugin::<AccountSessionResponse>("loadSession", ())
            .map_err(|_| ())?;
        response
            .value
            .map(|value| {
                if !is_valid_account_session_payload(&value) {
                    return Err(());
                }
                if let Some(migrated) = migrated_account_session_payload(&value) {
                    self.save_account_session(&migrated)?;
                    Ok(migrated)
                } else {
                    Ok(value)
                }
            })
            .transpose()
    }

    pub fn save_account_session(&self, value: &str) -> Result<(), ()> {
        if !is_valid_account_session_payload(value) {
            return Err(());
        }
        self.0
            .run_mobile_plugin("saveSession", AccountSessionRequest { value })
            .map_err(|_| ())
    }

    pub fn clear_account_session(&self) -> Result<(), ()> {
        self.0.run_mobile_plugin("clearSession", ()).map_err(|_| ())
    }

    pub async fn sign_in_with_apple(&self, challenge_id: &str, nonce: &str) -> Result<String, ()> {
        if challenge_id.is_empty()
            || challenge_id.len() > 256
            || challenge_id.chars().any(char::is_control)
            || nonce.is_empty()
            || nonce.len() > 4096
            || nonce.chars().any(char::is_control)
        {
            return Err(());
        }
        let response = self
            .0
            .run_mobile_plugin_async::<AppleSignInResponse>(
                "signInWithApple",
                AppleSignInRequest {
                    challenge_id,
                    nonce,
                },
            )
            .await
            .map_err(|_| ())?;
        (!response.credential.is_empty()
            && response.credential.len() <= 16 * 1024
            && !response.credential.chars().any(char::is_control))
        .then_some(response.credential)
        .ok_or(())
    }

    pub fn copy_text(&self, text: &str) -> Result<(), ()> {
        if !is_valid_ios_clipboard_text(text) {
            return Err(());
        }
        self.0
            .run_mobile_plugin("copyText", CopyTextRequest { text })
            .map_err(|_| ())
    }

    pub fn save_voice_text(&self, text: &str) -> Result<(), ()> {
        if text.trim().is_empty() || text.chars().count() > 10_000 || text.contains('\0') {
            return Err(());
        }
        self.0
            .run_mobile_plugin("saveVoiceText", SaveVoiceTextRequest { text })
            .map_err(|_| ())
    }

    pub async fn recognize_voice(
        &self,
        request: IosVoiceTranscriptionRequest,
    ) -> Result<IosVoiceTranscriptionResponse, ()> {
        if !request.is_valid() {
            return Err(());
        }
        let response = self
            .0
            .run_mobile_plugin_async::<IosVoiceTranscriptionResponse>("recognizeVoice", request)
            .await
            .map_err(|_| ())?;
        response.is_valid().then_some(response).ok_or(())
    }

    pub fn stop_voice(&self, request_id: &str) -> Result<(), ()> {
        if request_id.is_empty() || request_id.len() > 64 {
            return Err(());
        }
        self.0
            .run_mobile_plugin(
                "stopVoice",
                VoiceControlRequest {
                    request_id: Some(request_id),
                },
            )
            .map_err(|_| ())
    }

    pub fn cancel_voice(&self, request_id: Option<&str>) -> Result<(), ()> {
        if request_id.is_some_and(|value| value.is_empty() || value.len() > 64) {
            return Err(());
        }
        self.0
            .run_mobile_plugin("cancelVoice", VoiceControlRequest { request_id })
            .map_err(|_| ())
    }

    pub fn load_keyboard_preferences(&self) -> Result<IosKeyboardPreferences, ()> {
        let preferences = self
            .0
            .run_mobile_plugin::<IosKeyboardPreferences>("loadKeyboardPreferences", ())
            .map_err(|_| ())?;
        preferences.is_valid().then_some(preferences).ok_or(())
    }

    pub fn save_keyboard_preferences(
        &self,
        preferences: &IosKeyboardPreferences,
    ) -> Result<IosKeyboardPreferences, ()> {
        if !preferences.is_valid() {
            return Err(());
        }
        let saved = self
            .0
            .run_mobile_plugin::<IosKeyboardPreferences>("saveKeyboardPreferences", preferences)
            .map_err(|_| ())?;
        saved.is_valid().then_some(saved).ok_or(())
    }

    pub fn save_keyboard_ai(&self, preferences: &IosKeyboardAiPreferences) -> Result<(), ()> {
        if !preferences.is_valid() {
            return Err(());
        }
        self.0
            .run_mobile_plugin("saveKeyboardAI", preferences)
            .map_err(|_| ())
    }

    pub fn preview_keyboard_haptics(&self, strength: &str) -> Result<(), ()> {
        if !matches!(strength, "light" | "medium" | "strong") {
            return Err(());
        }
        self.0
            .run_mobile_plugin("previewKeyboardHaptics", json!({ "strength": strength }))
            .map_err(|_| ())
    }
}

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("msime-mobile-platform")
        .setup(|app, api| {
            #[cfg(target_os = "ios")]
            {
                let handle = api.register_ios_plugin(init_plugin_msime_mobile_platform)?;
                app.manage(MobilePlatform(handle));
            }
            #[cfg(target_os = "android")]
            {
                let handle = api.register_android_plugin("app.msime.client", "VoicePlugin")?;
                app.manage(AndroidVoicePlatform(handle));
            }
            #[cfg(not(any(target_os = "ios", target_os = "android")))]
            let _ = (app, api);
            Ok(())
        })
        .build()
}

#[cfg(test)]
mod tests {
    use super::{
        is_supported_app_icon_style, is_valid_account_session_payload, is_valid_ios_clipboard_text,
        migrated_account_session_payload, valid_android_voice_request, IosKeyboardAiPreferences,
        IosKeyboardPreferences, IosVoiceRequestHeader, IosVoiceTranscriptionRequest,
        IosVoiceTranscriptionResponse, MAX_ACCOUNT_SESSION_BYTES,
        MAX_IOS_CLIPBOARD_TEXT_UTF16_UNITS, MAX_IOS_VOICE_TEXT_CHARS,
    };
    use serde_json::Value;

    #[test]
    fn app_icon_styles_are_an_explicit_allowlist() {
        for style in ["classic", "forest", "sky", "dusk", "vermilion"] {
            assert!(is_supported_app_icon_style(style));
        }
        for style in ["", "Classic", "unknown", "../AppIcon"] {
            assert!(!is_supported_app_icon_style(style));
        }
    }

    #[test]
    fn ios_keyboard_ai_preferences_require_a_complete_enabled_configuration() {
        let valid = IosKeyboardAiPreferences {
            enabled: true,
            provider: "deepSeek".into(),
            endpoint: "https://api.example.invalid/v1/chat/completions".into(),
            model: "fixture-model".into(),
            prompt: "只返回结果".into(),
            token: "fixture-token".into(),
        };
        assert!(valid.is_valid());
        assert!(!IosKeyboardAiPreferences {
            token: String::new(),
            ..valid.clone()
        }
        .is_valid());
        assert!(IosKeyboardAiPreferences {
            enabled: false,
            endpoint: String::new(),
            model: String::new(),
            prompt: String::new(),
            token: String::new(),
            ..valid
        }
        .is_valid());
    }

    #[test]
    fn android_voice_requests_use_bounded_platform_arguments() {
        assert!(valid_android_voice_request("fixture-1", "zh-CN"));
        let long_value = "x".repeat(65);
        for request_id in ["", "request_id", long_value.as_str()] {
            assert!(!valid_android_voice_request(request_id, "zh-CN"));
        }
        for language in ["", "zh\nCN", long_value.as_str()] {
            assert!(!valid_android_voice_request("fixture-1", language));
        }
    }

    #[test]
    fn ios_voice_requests_accept_only_bounded_batch_providers() {
        let request = IosVoiceTranscriptionRequest {
            request_id: "fixture-request-1".into(),
            provider: "openai".into(),
            endpoint: "https://fixture.invalid/v1/audio/transcriptions".into(),
            model: "fixture-model".into(),
            token: "synthetic-token".into(),
            headers: Vec::new(),
            enable_itn: true,
            enable_punctuation: true,
            enable_ddc: false,
            boosting_table_id: String::new(),
        };
        assert!(request.is_valid());
        for provider in ["openai", "siliconflow", "groq"] {
            assert!(IosVoiceTranscriptionRequest {
                provider: provider.into(),
                ..request.clone()
            }
            .is_valid());
        }
        for provider in ["system", "custom", ""] {
            assert!(!IosVoiceTranscriptionRequest {
                provider: provider.into(),
                ..request.clone()
            }
            .is_valid());
        }
        assert!(!IosVoiceTranscriptionRequest {
            endpoint: "http://fixture.invalid/transcriptions".into(),
            ..request.clone()
        }
        .is_valid());
        assert!(!IosVoiceTranscriptionRequest {
            model: "fixture\nmodel".into(),
            ..request
        }
        .is_valid());
    }

    #[test]
    fn ios_voice_requests_accept_only_provider_bound_doubao_headers() {
        let headers = vec![
            IosVoiceRequestHeader {
                name: "x-api-key".into(),
                value: "synthetic-key".into(),
            },
            IosVoiceRequestHeader {
                name: "x-api-resource-id".into(),
                value: "fixture-resource".into(),
            },
            IosVoiceRequestHeader {
                name: "x-api-request-id".into(),
                value: "00000000-0000-4000-8000-000000000000".into(),
            },
        ];
        let request = IosVoiceTranscriptionRequest {
            request_id: "fixture-request-1".into(),
            provider: "doubao".into(),
            endpoint: "wss://fixture.invalid/asr".into(),
            model: String::new(),
            token: String::new(),
            headers,
            enable_itn: true,
            enable_punctuation: true,
            enable_ddc: false,
            boosting_table_id: "fixture-table".into(),
        };
        assert!(request.is_valid());
        assert!(!IosVoiceTranscriptionRequest {
            endpoint: "https://fixture.invalid/asr".into(),
            ..request.clone()
        }
        .is_valid());
        assert!(!IosVoiceTranscriptionRequest {
            token: "synthetic-duplicate".into(),
            ..request.clone()
        }
        .is_valid());
        assert!(!IosVoiceTranscriptionRequest {
            headers: vec![
                IosVoiceRequestHeader {
                    name: "authorization".into(),
                    value: "synthetic-key".into(),
                },
                IosVoiceRequestHeader {
                    name: "x-api-resource-id".into(),
                    value: "fixture-resource".into(),
                },
                IosVoiceRequestHeader {
                    name: "x-api-request-id".into(),
                    value: "fixture-request".into(),
                },
            ],
            ..request
        }
        .is_valid());
    }

    #[test]
    fn ios_voice_responses_reject_unbounded_or_nul_text() {
        assert!(IosVoiceTranscriptionResponse {
            text: "fixture result".into()
        }
        .is_valid());
        assert!(!IosVoiceTranscriptionResponse {
            text: "x".repeat(MAX_IOS_VOICE_TEXT_CHARS + 1)
        }
        .is_valid());
        assert!(!IosVoiceTranscriptionResponse {
            text: "fixture\0result".into()
        }
        .is_valid());
    }

    #[test]
    fn account_session_payloads_use_utf8_byte_limits() {
        assert!(!is_valid_account_session_payload(""));
        assert!(is_valid_account_session_payload(
            &"x".repeat(MAX_ACCOUNT_SESSION_BYTES)
        ));
        assert!(!is_valid_account_session_payload(
            &"x".repeat(MAX_ACCOUNT_SESSION_BYTES + 1)
        ));
        assert!(!is_valid_account_session_payload(
            &"界".repeat(MAX_ACCOUNT_SESSION_BYTES / 3 + 1)
        ));
    }

    #[test]
    fn current_account_session_payload_is_left_unchanged() {
        let payload = r#"{"tokens":{},"expires_at_unix_ms":123}"#;
        assert_eq!(migrated_account_session_payload(payload), None);
    }

    #[test]
    fn native_apple_account_session_is_migrated_to_unix_milliseconds() {
        let payload = r#"{"tokens":{"access_token":"synthetic"},"expiresAt":0}"#;
        let migrated = migrated_account_session_payload(payload).unwrap();
        let document: Value = serde_json::from_str(&migrated).unwrap();
        assert_eq!(document["tokens"]["access_token"], "synthetic");
        assert_eq!(document["expires_at_unix_ms"], 978_307_200_000_u64);
        assert!(document.get("expiresAt").is_none());
    }

    #[test]
    fn legacy_community_session_is_migrated_without_logging_secrets() {
        let payload = r#"{"access_token":"synthetic-access","refresh_token":"synthetic-refresh","user":{"id":"synthetic-user","display_name":"","created_at":""},"saved_at":0,"expires_in":900}"#;
        let migrated = migrated_account_session_payload(payload).unwrap();
        let document: Value = serde_json::from_str(&migrated).unwrap();
        assert_eq!(document["tokens"]["token_type"], "Bearer");
        assert_eq!(document["tokens"]["expires_in"], 900);
        assert_eq!(document["tokens"]["user"]["id"], "synthetic-user");
        assert_eq!(document["expires_at_unix_ms"], 978_308_100_000_u64);
    }

    fn keyboard_preferences() -> IosKeyboardPreferences {
        IosKeyboardPreferences {
            input_scheme: "japaneseNineKey".into(),
            traditional_chinese_output: true,
            sound_enabled: true,
            haptics_enabled: true,
            haptic_strength: "strong".into(),
            dictionary_learning: false,
            keyboard_skin: "custom".into(),
            custom_keyboard_skin: Some(r#"{"background":15269867}"#.into()),
        }
    }

    #[test]
    fn ios_keyboard_preferences_use_bounded_allowlisted_values() {
        assert!(keyboard_preferences().is_valid());

        let mut invalid = keyboard_preferences();
        invalid.input_scheme = "future".into();
        assert!(!invalid.is_valid());

        let mut invalid = keyboard_preferences();
        invalid.haptic_strength = "maximum".into();
        assert!(!invalid.is_valid());

        let mut invalid = keyboard_preferences();
        invalid.keyboard_skin = "../skin".into();
        assert!(!invalid.is_valid());

        let mut invalid = keyboard_preferences();
        invalid.custom_keyboard_skin = Some("[]".into());
        assert!(!invalid.is_valid());
    }

    #[test]
    fn ios_clipboard_text_uses_the_apple_utf16_boundary() {
        assert!(!is_valid_ios_clipboard_text(""));
        assert!(is_valid_ios_clipboard_text(
            &"a".repeat(MAX_IOS_CLIPBOARD_TEXT_UTF16_UNITS)
        ));
        assert!(!is_valid_ios_clipboard_text(
            &"😀".repeat(MAX_IOS_CLIPBOARD_TEXT_UTF16_UNITS / 2 + 1)
        ));
        assert!(!is_valid_ios_clipboard_text("safe\0hidden"));
    }
}
