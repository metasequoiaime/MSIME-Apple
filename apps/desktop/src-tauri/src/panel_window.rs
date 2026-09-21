//! Creating, positioning and closing the floating panel windows.
//!
//! Every panel is a borderless always-on-top webview whose placement follows the
//! caret the host reported. The keyboard panel is the one window that must never
//! take focus, because taking it would end the text client's composition.

#[cfg(target_os = "linux")]
use crate::panel_input::panel_position;
#[cfg(any(target_os = "linux", target_os = "windows"))]
use crate::panel_input::remember_panel_input_target;
#[cfg(any(target_os = "macos", test))]
use crate::platform::macos::macos_keyboard;
#[cfg(target_os = "macos")]
use crate::platform::macos::macos_panel_session;
use crate::voice::cancel_voice;
use crate::{DictionaryHostOptions, HostActionError, PanelInputState};
use tauri::{Manager, WebviewUrl, WebviewWindowBuilder};

pub(crate) fn panel_accepts_focus(label: &str) -> bool {
    label != "keyboard-panel"
}

#[cfg(target_os = "linux")]
pub(crate) fn visible_panel_position(
    window: &tauri::WebviewWindow,
    position: tauri::Position,
    width: f64,
    height: f64,
) -> tauri::Position {
    // X11 geometry is physical. Do not reinterpret Sway's logical coordinates
    // using a monitor scale factor from a different coordinate space.
    let tauri::Position::Physical(point) = position else {
        return position;
    };
    let Ok(monitors) = window.available_monitors() else {
        return position;
    };
    let x = f64::from(point.x);
    let y = f64::from(point.y);
    // panel_position used the logical requested width. Recover the editor's
    // physical center before choosing a monitor and applying its scale.
    let center_x = x + width / 2.0;
    let distance = |monitor: &tauri::Monitor| {
        let area = monitor.work_area();
        let left = f64::from(area.position.x);
        let top = f64::from(area.position.y);
        let dx = center_x - center_x.clamp(left, left + f64::from(area.size.width));
        let dy = y - y.clamp(top, top + f64::from(area.size.height));
        dx * dx + dy * dy
    };
    let Some(monitor) = monitors
        .iter()
        .filter(|monitor| monitor.work_area().size.width > 0 && monitor.work_area().size.height > 0)
        .min_by(|left, right| distance(left).total_cmp(&distance(right)))
    else {
        return position;
    };
    let scale = monitor.scale_factor();
    if !scale.is_finite() || scale <= 0.0 {
        return position;
    }
    let x = center_x - width * scale / 2.0;
    let area = monitor.work_area();
    let left = f64::from(area.position.x);
    let top = f64::from(area.position.y);
    let right = left + (f64::from(area.size.width) - width * scale).max(0.0);
    let bottom = top + (f64::from(area.size.height) - height * scale).max(0.0);
    tauri::Position::Physical(tauri::PhysicalPosition::new(
        x.clamp(left, right).round() as i32,
        y.clamp(top, bottom).round() as i32,
    ))
}

pub(crate) fn open_panel_window(
    app: &tauri::AppHandle,
    label: &'static str,
    route: &'static str,
    title: &'static str,
    width: f64,
    height: f64,
    position: Option<tauri::Position>,
) -> Result<(), HostActionError> {
    #[cfg(mobile)]
    {
        let _ = (app, label, route, title, width, height, position);
        Err(HostActionError {
            code: "unavailable",
        })
    }
    #[cfg(not(mobile))]
    {
        let accepts_focus = panel_accepts_focus(label);
        if let Some(window) = app.get_webview_window(label) {
            #[cfg(target_os = "macos")]
            if label == "keyboard-panel" {
                return macos_keyboard::show(&window).map_err(|_| HostActionError {
                    code: "unavailable",
                });
            }
            #[cfg(any(target_os = "linux", target_os = "windows"))]
            if let Some(position) = position {
                #[cfg(target_os = "linux")]
                let position = visible_panel_position(&window, position, width, height);
                let _ = window.set_position(position);
            }
            window
                .show()
                .and_then(|_| {
                    if accepts_focus {
                        window.set_focus()
                    } else {
                        Ok(())
                    }
                })
                .map_err(|_| HostActionError {
                    code: "unavailable",
                })?;
            return Ok(());
        }
        let builder = WebviewWindowBuilder::new(
            app,
            label,
            WebviewUrl::App(format!("index.html?panel={route}").into()),
        )
        .title(title);
        // A panel is shown as soon as it is positioned, which is well before its page paints. The
        // settings window carries the system theme, so the panel opens in the colour it is about
        // to paint rather than in the platform's white.
        let theme = app
            .get_webview_window("main")
            .and_then(|window| window.theme().ok());
        let window = builder
            .background_color(crate::chrome_background(theme))
            .inner_size(width, height)
            .visible(false)
            .focused(false)
            .focusable(accepts_focus)
            .min_inner_size(width, height)
            .resizable(false)
            .decorations(false)
            .always_on_top(true)
            .skip_taskbar(true)
            .build()
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?;
        if let Some(position) = position {
            #[cfg(target_os = "linux")]
            let position = visible_panel_position(&window, position, width, height);
            let _ = window.set_position(position);
        }
        #[cfg(target_os = "macos")]
        if label == "keyboard-panel" {
            return macos_keyboard::show(&window).map_err(|_| HostActionError {
                code: "unavailable",
            });
        }
        window
            .show()
            .and_then(|_| {
                if accepts_focus {
                    window.set_focus()
                } else {
                    Ok(())
                }
            })
            .map_err(|_| HostActionError {
                code: "unavailable",
            })
    }
}

#[tauri::command]
pub(crate) fn open_keyboard_panel(
    app: tauri::AppHandle,
    state: tauri::State<'_, PanelInputState>,
) -> Result<(), HostActionError> {
    {
        #[cfg(not(any(target_os = "linux", target_os = "windows")))]
        let _ = &state;
        #[cfg(target_os = "linux")]
        let position = {
            let _ = remember_panel_input_target(&state, "keyboard-panel", true);
            panel_position(&state, "keyboard-panel", 1100.0, 400.0)
        };
        // The panel never activates, so the window that owns the caret now is
        // the one synthetic input has to reach later.
        #[cfg(target_os = "windows")]
        let position = {
            let _ = remember_panel_input_target(&state);
            windows_panel_position(1100.0, 400.0)
        };
        #[cfg(not(any(target_os = "linux", target_os = "windows")))]
        let position = None;
        open_panel_window(
            &app,
            "keyboard-panel",
            "keyboard",
            "水杉屏幕键盘",
            1100.0,
            400.0,
            position,
        )
    }
}

#[tauri::command]
pub(crate) fn open_handwriting_panel(
    app: tauri::AppHandle,
    state: tauri::State<'_, PanelInputState>,
) -> Result<(), HostActionError> {
    {
        #[cfg(not(any(target_os = "linux", target_os = "windows")))]
        let _ = &state;
        #[cfg(target_os = "linux")]
        let position = {
            let _ = remember_panel_input_target(&state, "handwriting-panel", true);
            panel_position(&state, "handwriting-panel", 980.0, 650.0)
        };
        // The panel never activates, so the window that owns the caret now is
        // the one synthetic input has to reach later.
        #[cfg(target_os = "windows")]
        let position = {
            let _ = remember_panel_input_target(&state);
            windows_panel_position(980.0, 650.0)
        };
        #[cfg(not(any(target_os = "linux", target_os = "windows")))]
        let position = None;
        open_panel_window(
            &app,
            "handwriting-panel",
            "handwriting",
            "水杉手写识别板",
            980.0,
            650.0,
            position,
        )
    }
}

#[tauri::command]
pub(crate) fn open_emoji_panel(
    app: tauri::AppHandle,
    options: tauri::State<'_, DictionaryHostOptions>,
    input: tauri::State<'_, PanelInputState>,
) -> Result<(), HostActionError> {
    {
        #[cfg(not(any(target_os = "linux", target_os = "windows")))]
        let _ = (&options, &input);
        #[cfg(target_os = "linux")]
        let position = {
            let _ = &options;
            let _ = remember_panel_input_target(&input, "emoji-panel", true);
            panel_position(&input, "emoji-panel", 720.0, 720.0)
        };
        #[cfg(target_os = "windows")]
        let position = {
            let _ = &options;
            let _ = remember_panel_input_target(&input);
            windows_panel_position(720.0, 720.0)
        };
        #[cfg(not(any(target_os = "linux", target_os = "windows")))]
        let position = None;
        open_panel_window(
            &app,
            "emoji-panel",
            "emoji",
            "Emoji and more",
            720.0,
            720.0,
            position,
        )
    }
}

#[tauri::command]
pub(crate) fn open_voice_panel(
    app: tauri::AppHandle,
    state: tauri::State<'_, PanelInputState>,
) -> Result<(), HostActionError> {
    #[cfg(target_os = "macos")]
    if !app
        .state::<macos_panel_session::PanelState>()
        .can_open_voice_panel()
    {
        // A standalone Tauri keyboard has no authenticated IMK target. Do not
        // open a panel which could recognize text but can never submit it.
        return Err(HostActionError {
            code: "unavailable",
        });
    }
    #[cfg(not(any(target_os = "linux", target_os = "windows")))]
    let _ = &state;
    #[cfg(target_os = "linux")]
    let position = {
        let _ = remember_panel_input_target(&state, "voice-panel", true);
        panel_position(&state, "voice-panel", 620.0, 520.0)
    };
    #[cfg(target_os = "windows")]
    let position = {
        let _ = remember_panel_input_target(&state);
        windows_panel_position(620.0, 520.0)
    };
    #[cfg(not(any(target_os = "linux", target_os = "windows")))]
    let position = None;
    open_panel_window(
        &app,
        "voice-panel",
        "voice",
        "水杉语音输入",
        620.0,
        520.0,
        position,
    )
}

#[tauri::command]
pub(crate) fn open_cloud_clipboard_panel(
    app: tauri::AppHandle,
    state: tauri::State<'_, PanelInputState>,
) -> Result<(), HostActionError> {
    #[cfg(target_os = "windows")]
    {
        let _ = remember_panel_input_target(&state);
        let position = windows_panel_position(560.0, 560.0);
        open_panel_window(
            &app,
            "cloud-clipboard-panel",
            "cloud-clipboard",
            "水杉云剪贴板",
            560.0,
            560.0,
            position,
        )
    }
    #[cfg(not(target_os = "windows"))]
    {
        #[cfg(not(target_os = "linux"))]
        let _ = &state;
        #[cfg(target_os = "linux")]
        let position = {
            let _ = remember_panel_input_target(&state, "cloud-clipboard-panel", true);
            panel_position(&state, "cloud-clipboard-panel", 560.0, 560.0)
        };
        #[cfg(not(target_os = "linux"))]
        let position = None;
        open_panel_window(
            &app,
            "cloud-clipboard-panel",
            "cloud-clipboard",
            "水杉云剪贴板",
            560.0,
            560.0,
            position,
        )
    }
}

#[tauri::command]
pub(crate) fn open_cloud_dictionary_panel(
    app: tauri::AppHandle,
    state: tauri::State<'_, PanelInputState>,
) -> Result<(), HostActionError> {
    #[cfg(target_os = "windows")]
    {
        let _ = remember_panel_input_target(&state);
        let position = windows_panel_position(760.0, 700.0);
        open_panel_window(
            &app,
            "cloud-dictionary-panel",
            "cloud-dictionary",
            "水杉云词库",
            760.0,
            700.0,
            position,
        )
    }
    #[cfg(not(target_os = "windows"))]
    {
        #[cfg(not(target_os = "linux"))]
        let _ = &state;
        #[cfg(target_os = "linux")]
        let position = {
            let _ = remember_panel_input_target(&state, "cloud-dictionary-panel", true);
            panel_position(&state, "cloud-dictionary-panel", 760.0, 700.0)
        };
        #[cfg(not(target_os = "linux"))]
        let position = None;
        open_panel_window(
            &app,
            "cloud-dictionary-panel",
            "cloud-dictionary",
            "水杉云词典",
            760.0,
            700.0,
            position,
        )
    }
}

#[tauri::command]
pub(crate) fn close_panel(
    app: tauri::AppHandle,
    label: String,
    state: tauri::State<'_, PanelInputState>,
) -> Result<(), HostActionError> {
    if !matches!(
        label.as_str(),
        "keyboard-panel"
            | "handwriting-panel"
            | "emoji-panel"
            | "clipboard-panel"
            | "voice-panel"
            | "cloud-clipboard-panel"
            | "cloud-dictionary-panel"
    ) {
        return Err(HostActionError {
            code: "invalid_panel",
        });
    }
    if label == "voice-panel" {
        let _ = cancel_voice(app.clone(), None);
    }
    #[cfg(target_os = "macos")]
    if matches!(label.as_str(), "emoji-panel" | "handwriting-panel") {
        let window = app.get_webview_window(&label).ok_or(HostActionError {
            code: "unavailable",
        })?;
        return macos_panel_session::close(&app, window);
    }
    #[cfg(target_os = "macos")]
    if label == "keyboard-panel" {
        let window = app.get_webview_window(&label).ok_or(HostActionError {
            code: "unavailable",
        })?;
        return macos_keyboard::close(&window).map_err(|_| HostActionError {
            code: "unavailable",
        });
    }
    let result = app
        .get_webview_window(&label)
        .ok_or(HostActionError {
            code: "unavailable",
        })?
        .close()
        .map_err(|_| HostActionError {
            code: "unavailable",
        });
    if result.is_ok()
        && matches!(
            label.as_str(),
            "keyboard-panel"
                | "handwriting-panel"
                | "emoji-panel"
                | "clipboard-panel"
                | "voice-panel"
                | "cloud-clipboard-panel"
                | "cloud-dictionary-panel"
        )
    {
        if let Ok(mut target) = state.0.lock() {
            #[cfg(target_os = "linux")]
            {
                target.remove(&label);
            }
            #[cfg(not(target_os = "linux"))]
            {
                *target = None;
            }
        }
    }
    result
}
