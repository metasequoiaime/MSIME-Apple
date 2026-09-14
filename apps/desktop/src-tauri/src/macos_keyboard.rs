use msime_client_core::host_surface::{PanelSurface, SurfaceRoute};
use tauri::utils::config::WindowConfig;
#[cfg(target_os = "macos")]
use tauri::Manager;

#[cfg(target_os = "macos")]
tauri_nspanel::tauri_panel! {
    panel!(MSIMEKeyboardPanel {
        config: {
            can_become_key_window: false,
            can_become_main_window: false,
            is_floating_panel: true
        }
    })
}

#[cfg(target_os = "macos")]
pub(crate) fn show(window: &tauri::WebviewWindow) -> tauri::Result<()> {
    prepare(window)?.order_front_regardless();
    Ok(())
}

#[cfg(target_os = "macos")]
pub(crate) fn prepare(
    window: &tauri::WebviewWindow,
) -> tauri::Result<tauri_nspanel::PanelHandle<tauri::Wry>> {
    use tauri_nspanel::{ManagerExt, WebviewWindowExt};
    let content = if window.get_webview_panel(window.label()).is_err() {
        Some(
            msime_host_macos::detach_window_content(window.ns_window()? as usize).ok_or_else(
                || tauri::Error::Io(std::io::Error::other("Cannot prepare keyboard view")),
            )?,
        )
    } else {
        None
    };
    let panel = match window.get_webview_panel(window.label()) {
        Ok(panel) => panel,
        Err(_) => window.to_panel::<MSIMEKeyboardPanel>()?,
    };
    panel.set_style_mask(tauri_nspanel::panel::NSWindowStyleMask::NonactivatingPanel);
    panel.set_hides_on_deactivate(false);
    panel.set_becomes_key_only_if_needed(true);
    drop(content);
    Ok(panel)
}

#[cfg(target_os = "macos")]
pub(crate) fn restore(window: &tauri::WebviewWindow) -> tauri::Result<()> {
    use tauri_nspanel::ManagerExt;
    if let Ok(panel) = window.get_webview_panel(window.label()) {
        let content = msime_host_macos::detach_window_content(window.ns_window()? as usize)
            .ok_or_else(|| {
                tauri::Error::Io(std::io::Error::other("Cannot restore keyboard view"))
            })?;
        let restored = panel.to_window();
        drop(content);
        if restored.is_none() {
            return Err(tauri::Error::Io(std::io::Error::other(
                "Cannot restore keyboard window",
            )));
        }
    }
    Ok(())
}

#[cfg(target_os = "macos")]
pub(crate) fn close(window: &tauri::WebviewWindow) -> tauri::Result<()> {
    restore(window)?;
    // Conversion clears the native delegate. Destroy through Tauri so its
    // window manager is notified and the same label can be opened again.
    window.destroy()
}

/// Enable routes as their native input/service bridges are migrated. The
/// keyboard can use live foreground targeting without retaining an IMK client.
pub(crate) fn startup_panel(route: Option<SurfaceRoute>) -> Option<PanelSurface> {
    route
        .filter(|route| *route == SurfaceRoute::Keyboard)?
        .panel()
}

/// Runs before Tauri constructs any windows, so the hidden settings window
/// cannot steal the editor's focus during a keyboard-only launch.
pub(crate) fn prepare_windows(windows: &mut [WindowConfig], route: Option<SurfaceRoute>) {
    if startup_panel(route).is_some() {
        for window in windows.iter_mut().filter(|window| window.label == "main") {
            window.visible = false;
            window.focus = false;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keyboard_launch_hides_settings_before_creation_and_uses_shared_surface() {
        let mut windows = vec![WindowConfig::default()];
        windows[0].label = "main".into();
        windows[0].visible = true;
        windows[0].focus = true;
        prepare_windows(&mut windows, Some(SurfaceRoute::Keyboard));
        assert!(!windows[0].visible && !windows[0].focus);
        let panel = startup_panel(Some(SurfaceRoute::Keyboard)).unwrap();
        assert_eq!(panel.label, "keyboard-panel");
        assert_eq!(panel.query, "keyboard");
        assert!(!super::super::panel_accepts_focus(panel.label));
    }

    #[test]
    fn ordinary_settings_launch_keeps_its_existing_visibility() {
        for route in [None, SurfaceRoute::parse("settings:appearance").ok()] {
            let mut windows = vec![WindowConfig::default()];
            windows[0].label = "main".into();
            windows[0].visible = true;
            windows[0].focus = true;
            prepare_windows(&mut windows, route);
            assert!(windows[0].visible && windows[0].focus);
            assert!(startup_panel(route).is_none());
        }
    }
}
