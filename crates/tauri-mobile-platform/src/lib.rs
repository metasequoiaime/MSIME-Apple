use serde::{Deserialize, Serialize};
#[cfg(any(target_os = "ios", test))]
use serde_json::json;
use serde_json::Value;
use tauri::plugin::{Builder, TauriPlugin};
use tauri::Runtime;

#[cfg(target_os = "ios")]
use tauri::plugin::PluginHandle;
#[cfg(target_os = "ios")]
use tauri::Manager;

#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_plugin_msime_mobile_platform);

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AppIconInfo {
    pub supported: bool,
    pub selected: String,
}

const MAX_IOS_CUSTOM_KEYBOARD_SKIN_BYTES: usize = 800_000;
#[cfg(any(target_os = "ios", test))]
const MAX_IOS_CLIPBOARD_TEXT_UTF16_UNITS: usize = 4_000;

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
#[derive(Serialize)]
struct AccountSessionRequest<'a> {
    value: &'a str,
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
}

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("msime-mobile-platform")
        .setup(|app, api| {
            #[cfg(target_os = "ios")]
            {
                let handle = api.register_ios_plugin(init_plugin_msime_mobile_platform)?;
                app.manage(MobilePlatform(handle));
            }
            #[cfg(not(target_os = "ios"))]
            let _ = (app, api);
            Ok(())
        })
        .build()
}

#[cfg(test)]
mod tests {
    use super::{
        is_supported_app_icon_style, is_valid_account_session_payload, is_valid_ios_clipboard_text,
        migrated_account_session_payload, IosKeyboardPreferences, MAX_ACCOUNT_SESSION_BYTES,
        MAX_IOS_CLIPBOARD_TEXT_UTF16_UNITS,
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
