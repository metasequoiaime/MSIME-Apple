use serde::{Deserialize, Serialize};
#[cfg(any(target_os = "ios", test))]
use serde_json::{json, Value};
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
        is_supported_app_icon_style, is_valid_account_session_payload,
        migrated_account_session_payload, MAX_ACCOUNT_SESSION_BYTES,
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
}
