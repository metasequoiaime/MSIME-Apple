//! Cloud clipboard requests over the account session, written once for iOS and Android.
//!
//! Both targets used to carry an identical copy of this body next to their account commands. It lives apart from [`super::mobile_community`] because it reads nothing from the community services: it talks to the account session itself, which each target's account state exposes through `AccountState::session`.

use msime_client_core::account::AccountError;
use serde_json::Value;
use std::sync::Arc;

use super::MobileSession;

/// Runs a blocking session operation off the async runtime, with the same error mapping as each target's account `call`.
async fn call<T, F>(session: &Arc<MobileSession>, operation: F) -> Result<T, crate::CommandError>
where
    T: Send + 'static,
    F: FnOnce(&MobileSession) -> Result<T, AccountError> + Send + 'static,
{
    let session = Arc::clone(session);
    tauri::async_runtime::spawn_blocking(move || operation(&session))
        .await
        .map_err(|_| crate::CommandError {
            code: "account_unavailable",
        })?
        .map_err(|error| crate::CommandError { code: error.code() })
}

pub(crate) async fn cloud_clipboard_request(
    session: &Arc<MobileSession>,
    action: Value,
) -> Result<Value, crate::CommandError> {
    let operation = action
        .get("operation")
        .and_then(Value::as_str)
        .ok_or(crate::CommandError {
            code: "invalid_cloud_clipboard",
        })?;
    match operation {
        "list" => {
            let search = action
                .get("search")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_owned();
            call(session, move |session| {
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
                    .ok_or(crate::CommandError {
                        code: "invalid_cloud_clipboard",
                    })?;
            call(session, move |session| {
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
                .ok_or(crate::CommandError {
                    code: "invalid_cloud_clipboard",
                })?
                .to_owned();
            call(session, move |session| {
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
                .ok_or(crate::CommandError {
                    code: "invalid_cloud_clipboard",
                })?
                .to_owned();
            call(session, move |session| {
                session
                    .delete_clipboard(Some(&id))
                    .map(|()| serde_json::json!({}))
            })
            .await
        }
        _ => Err(crate::CommandError {
            code: "invalid_cloud_clipboard",
        }),
    }
}
