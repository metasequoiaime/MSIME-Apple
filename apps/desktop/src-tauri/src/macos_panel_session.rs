use super::HostActionError;
use msime_client_core::host_surface::{PanelSurface, SurfaceRoute};
use msime_host_macos::panel_session::{PanelSession, SessionError};
use std::sync::{
    atomic::{AtomicU8, Ordering},
    Arc,
};
use tauri::Manager;

pub(crate) struct PanelState {
    session: Option<Arc<PanelSession>>,
    // Serialize input and close so a hidden/closing view cannot submit later.
    lifecycle: Arc<AtomicU8>,
}

impl PanelState {
    pub(crate) fn from_environment() -> Result<Self, &'static str> {
        let value = std::env::var("MSIME_CLIENT_PANEL_SESSION");
        let session = match value {
            Ok(value) => Some(Arc::new(
                PanelSession::parse(&value).map_err(|_| "Invalid native panel session")?,
            )),
            Err(std::env::VarError::NotPresent) => None,
            Err(_) => return Err("Invalid native panel session"),
        };
        Ok(Self {
            session,
            lifecycle: Arc::new(AtomicU8::new(0)),
        })
    }
}

pub(crate) fn startup_panel(route: Option<SurfaceRoute>) -> Option<PanelSurface> {
    route.filter(|route| *route == SurfaceRoute::Emoji)?.panel()
}

pub(crate) fn prepare_windows(
    windows: &mut [tauri::utils::config::WindowConfig],
    route: Option<SurfaceRoute>,
) {
    if startup_panel(route).is_some() {
        for window in windows.iter_mut().filter(|window| window.label == "main") {
            window.visible = false;
            window.focus = false;
        }
    }
}

struct SubmissionGuard(Arc<AtomicU8>);
impl Drop for SubmissionGuard {
    fn drop(&mut self) {
        self.0.store(0, Ordering::Release);
    }
}

pub(crate) async fn submit(
    app: tauri::AppHandle,
    window: tauri::WebviewWindow,
    text: String,
) -> Result<(), HostActionError> {
    if window.label() != "emoji-panel" {
        return Err(error(SessionError::Unavailable));
    }
    msime_client_core::panels::validate_candidate(&text)
        .map_err(|_| error(SessionError::Invalid))?;
    let state = app.state::<PanelState>();
    let session = state
        .session
        .clone()
        .ok_or_else(|| error(SessionError::Unavailable))?;
    if session.is_used()
        || state
            .lifecycle
            .compare_exchange(0, 1, Ordering::AcqRel, Ordering::Acquire)
            .is_err()
    {
        return Err(error(SessionError::Rejected));
    }
    let _guard = SubmissionGuard(Arc::clone(&state.lifecycle));
    let (send, received) = std::sync::mpsc::sync_channel(1);
    let target = Arc::clone(&session);
    let panel = window.clone();
    app.run_on_main_thread(move || {
        // Do not hide the UI when the user has already chosen a third app.
        let activated = target.activate_target();
        let hidden = activated && panel.hide().is_ok();
        let _ = send.send(hidden);
    })
    .map_err(|_| error(SessionError::Unavailable))?;
    let result = tauri::async_runtime::spawn_blocking(move || {
        if !received.recv().unwrap_or(false) {
            return (false, Err(SessionError::Unavailable));
        }
        (true, session.submit(&text))
    })
    .await
    .map_err(|_| error(SessionError::Unavailable))?;
    match result.1 {
        Ok(()) => window
            .destroy()
            .map_err(|_| error(SessionError::Unavailable)),
        Err(failure) => {
            if result.0 {
                let _ = window.show();
            }
            Err(error(failure))
        }
    }
}

pub(crate) fn close(
    app: &tauri::AppHandle,
    window: tauri::WebviewWindow,
) -> Result<(), HostActionError> {
    let state = app.state::<PanelState>();
    if state
        .lifecycle
        .compare_exchange(0, 2, Ordering::AcqRel, Ordering::Acquire)
        .is_err()
    {
        return Err(error(SessionError::Rejected));
    }
    let session = state.session.clone();
    let lifecycle = Arc::clone(&state.lifecycle);
    tauri::async_runtime::spawn_blocking(move || {
        let _guard = SubmissionGuard(lifecycle);
        if let Some(session) = session {
            session.cancel();
        }
        let _ = window.destroy();
    });
    Ok(())
}

fn error(error: SessionError) -> HostActionError {
    HostActionError {
        code: match error {
            SessionError::Invalid => "invalid_text",
            SessionError::Unavailable => "unavailable",
            SessionError::Rejected => "input_session_expired",
            SessionError::OutcomeUnknown => "input_outcome_unknown",
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn emoji_startup_uses_shared_route_and_hides_only_settings() {
        let route = SurfaceRoute::parse("emoji").ok();
        let mut windows = vec![tauri::utils::config::WindowConfig {
            label: "main".into(),
            visible: true,
            ..Default::default()
        }];
        prepare_windows(&mut windows, route);
        assert!(!windows[0].visible);
        assert_eq!(startup_panel(route).unwrap().label, "emoji-panel");
        assert!(startup_panel(Some(SurfaceRoute::Keyboard)).is_none());
        assert!(startup_panel(SurfaceRoute::parse("settings:input").ok()).is_none());
    }
    #[test]
    fn close_and_submit_have_an_exclusive_lifecycle() {
        let state = Arc::new(AtomicU8::new(0));
        assert!(state
            .compare_exchange(0, 1, Ordering::AcqRel, Ordering::Acquire)
            .is_ok());
        assert!(state
            .compare_exchange(0, 2, Ordering::AcqRel, Ordering::Acquire)
            .is_err());
        drop(SubmissionGuard(Arc::clone(&state)));
        assert!(state
            .compare_exchange(0, 2, Ordering::AcqRel, Ordering::Acquire)
            .is_ok());
        assert!(state
            .compare_exchange(0, 1, Ordering::AcqRel, Ordering::Acquire)
            .is_err());
    }
}
