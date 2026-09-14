use serde::{Deserialize, Serialize};
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

pub fn is_supported_app_icon_style(style: &str) -> bool {
    matches!(style, "classic" | "forest" | "sky" | "dusk" | "vermilion")
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
    use super::is_supported_app_icon_style;

    #[test]
    fn app_icon_styles_are_an_explicit_allowlist() {
        for style in ["classic", "forest", "sky", "dusk", "vermilion"] {
            assert!(is_supported_app_icon_style(style));
        }
        for style in ["", "Classic", "unknown", "../AppIcon"] {
            assert!(!is_supported_app_icon_style(style));
        }
    }
}
