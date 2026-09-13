//! Host capabilities and the shared surface route vocabulary.
//!
//! Every platform host reaches the shared management UI by naming a route
//! instead of opening its own window, and the shared UI decides what to render
//! from injected capabilities instead of sniffing the user agent. Both sides of
//! that agreement live here so no host re-implements the strings.

use serde::{Deserialize, Serialize};
use thiserror::Error;

/// Routes are embedded in command lines and environment variables, so they stay
/// short and free of anything a shell or a line-framed channel would reinterpret.
const MAX_ROUTE_BYTES: usize = 64;

#[derive(Clone, Copy, Debug, Error, Eq, PartialEq)]
pub enum RouteError {
    #[error("route is empty")]
    Empty,
    #[error("route is too long")]
    TooLong,
    #[error("route contains an unsupported character")]
    IllegalCharacter,
    #[error("route is not a known surface")]
    Unknown,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum HostPlatform {
    Windows,
    Macos,
    Linux,
    Android,
    Ios,
}

impl HostPlatform {
    pub fn as_str(self) -> &'static str {
        match self {
            HostPlatform::Windows => "windows",
            HostPlatform::Macos => "macos",
            HostPlatform::Linux => "linux",
            HostPlatform::Android => "android",
            HostPlatform::Ios => "ios",
        }
    }

    pub fn parse(value: &str) -> Result<Self, RouteError> {
        match value {
            "windows" => Ok(HostPlatform::Windows),
            "macos" => Ok(HostPlatform::Macos),
            "linux" => Ok(HostPlatform::Linux),
            "android" => Ok(HostPlatform::Android),
            "ios" => Ok(HostPlatform::Ios),
            "" => Err(RouteError::Empty),
            _ => Err(RouteError::Unknown),
        }
    }

    /// Desktop hosts own separate panel windows; mobile hosts render the shared
    /// UI inside a single activity or container app.
    pub fn is_desktop(self) -> bool {
        matches!(
            self,
            HostPlatform::Windows | HostPlatform::Macos | HostPlatform::Linux
        )
    }
}

/// What the surrounding host can actually do. The shared UI renders from this
/// rather than guessing from `navigator.userAgent`, which previously hid working
/// controls on Windows and macOS and left 打字统计 dead on every desktop.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct HostCapabilities {
    pub platform: HostPlatform,
    /// The host can restart the input method service from the settings page.
    pub restart_input_method: bool,
    /// The host can open the shared panels as separate always-on-top windows.
    pub panel_windows: bool,
    /// The host keeps per-application versus global Chinese/English mode state.
    pub ime_mode_scope: bool,
    /// The host records typing statistics.
    pub typing_statistics: bool,
    /// The host can enumerate installed font families.
    pub system_fonts: bool,
    /// The shared UI draws its own titlebar and resize handles.
    pub window_chrome: bool,
    /// The host renders a floating toolbar surface.
    pub floating_toolbar: bool,
    /// The host consumes the shared `keybindings` preferences to switch
    /// Chinese/English and simplified/traditional mode.
    pub mode_switch_shortcuts: bool,
    /// The desktop environment forwards a shortcut that opens a shared panel.
    pub panel_shortcuts: bool,
    /// The host can enumerate audio capture devices for voice input.
    pub voice_capture_devices: bool,
}

impl HostCapabilities {
    /// Capabilities as they stand today for each shipped host. Slices that add a
    /// capability to a host flip its flag here, and every consumer follows.
    pub fn for_platform(platform: HostPlatform) -> Self {
        HostCapabilities {
            platform,
            // Only the IBus host exposes a restart entry point so far.
            restart_input_method: platform == HostPlatform::Linux,
            panel_windows: platform.is_desktop(),
            // IBus keeps a session-wide mode; the other hosts track it per application.
            ime_mode_scope: platform == HostPlatform::Linux,
            typing_statistics: true,
            system_fonts: platform.is_desktop(),
            window_chrome: platform.is_desktop(),
            floating_toolbar: platform.is_desktop(),
            // Only the IBus host consumes the shared keybindings and forwards
            // panel shortcuts so far; a host flips these once it does.
            mode_switch_shortcuts: platform == HostPlatform::Linux,
            panel_shortcuts: platform == HostPlatform::Linux,
            voice_capture_devices: platform == HostPlatform::Linux,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum SettingsCategory {
    Appearance,
    Input,
    TypingStatistics,
    Helpcode,
    Shortcuts,
    Dictionary,
    Skin,
    ScreenKeyboard,
    Handwriting,
    Voice,
    Ai,
    Tools,
    FloatingToolbar,
    Help,
    About,
    Feedback,
}

impl SettingsCategory {
    /// Matches the category identifiers the shared settings page renders.
    pub fn as_str(self) -> &'static str {
        match self {
            SettingsCategory::Appearance => "appearance",
            SettingsCategory::Input => "input",
            SettingsCategory::TypingStatistics => "typing-statistics",
            SettingsCategory::Helpcode => "helpcode",
            SettingsCategory::Shortcuts => "shortcuts",
            SettingsCategory::Dictionary => "dictionary",
            SettingsCategory::Skin => "skin",
            SettingsCategory::ScreenKeyboard => "screen-keyboard",
            SettingsCategory::Handwriting => "handwriting",
            SettingsCategory::Voice => "voice",
            SettingsCategory::Ai => "ai",
            SettingsCategory::Tools => "tools",
            SettingsCategory::FloatingToolbar => "floating-toolbar",
            SettingsCategory::Help => "help",
            SettingsCategory::About => "about",
            SettingsCategory::Feedback => "feedback",
        }
    }

    pub fn parse(value: &str) -> Result<Self, RouteError> {
        match value {
            "appearance" => Ok(SettingsCategory::Appearance),
            "input" => Ok(SettingsCategory::Input),
            "typing-statistics" => Ok(SettingsCategory::TypingStatistics),
            "helpcode" => Ok(SettingsCategory::Helpcode),
            "shortcuts" => Ok(SettingsCategory::Shortcuts),
            "dictionary" => Ok(SettingsCategory::Dictionary),
            "skin" => Ok(SettingsCategory::Skin),
            "screen-keyboard" => Ok(SettingsCategory::ScreenKeyboard),
            "handwriting" => Ok(SettingsCategory::Handwriting),
            "voice" => Ok(SettingsCategory::Voice),
            "ai" => Ok(SettingsCategory::Ai),
            "tools" => Ok(SettingsCategory::Tools),
            "floating-toolbar" => Ok(SettingsCategory::FloatingToolbar),
            "help" => Ok(SettingsCategory::Help),
            "about" => Ok(SettingsCategory::About),
            "feedback" => Ok(SettingsCategory::Feedback),
            "" => Err(RouteError::Empty),
            _ => Err(RouteError::Unknown),
        }
    }

    pub const ALL: [SettingsCategory; 16] = [
        SettingsCategory::Appearance,
        SettingsCategory::Input,
        SettingsCategory::TypingStatistics,
        SettingsCategory::Helpcode,
        SettingsCategory::Shortcuts,
        SettingsCategory::Dictionary,
        SettingsCategory::Skin,
        SettingsCategory::ScreenKeyboard,
        SettingsCategory::Handwriting,
        SettingsCategory::Voice,
        SettingsCategory::Ai,
        SettingsCategory::Tools,
        SettingsCategory::FloatingToolbar,
        SettingsCategory::Help,
        SettingsCategory::About,
        SettingsCategory::Feedback,
    ];
}

/// A surface a platform host can ask the shared shell to present.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case", tag = "surface", content = "category")]
pub enum SurfaceRoute {
    Settings(Option<SettingsCategory>),
    Emoji,
    Keyboard,
    Handwriting,
    Voice,
    Clipboard,
    CloudClipboard,
    CloudDictionary,
}

/// Geometry and identity of a panel surface, so the window size lives beside the
/// route instead of being repeated per host.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct PanelSurface {
    pub label: &'static str,
    pub query: &'static str,
    pub title: &'static str,
    pub width: u32,
    pub height: u32,
}

impl SurfaceRoute {
    /// Canonical route string. Round-trips through [`SurfaceRoute::parse`].
    pub fn as_arg(self) -> String {
        match self {
            SurfaceRoute::Settings(None) => "settings".to_string(),
            SurfaceRoute::Settings(Some(category)) => format!("settings:{}", category.as_str()),
            SurfaceRoute::Emoji => "emoji".to_string(),
            SurfaceRoute::Keyboard => "keyboard".to_string(),
            SurfaceRoute::Handwriting => "handwriting".to_string(),
            SurfaceRoute::Voice => "voice".to_string(),
            SurfaceRoute::Clipboard => "clipboard".to_string(),
            SurfaceRoute::CloudClipboard => "cloud-clipboard".to_string(),
            SurfaceRoute::CloudDictionary => "cloud-dictionary".to_string(),
        }
    }

    pub fn parse(value: &str) -> Result<Self, RouteError> {
        if value.is_empty() {
            return Err(RouteError::Empty);
        }
        if value.len() > MAX_ROUTE_BYTES {
            return Err(RouteError::TooLong);
        }
        if !value.bytes().all(|byte| {
            byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-' || byte == b':'
        }) {
            return Err(RouteError::IllegalCharacter);
        }
        let mut parts = value.splitn(2, ':');
        let head = parts.next().unwrap_or_default();
        let tail = parts.next();
        if let Some(tail) = tail {
            // Only settings takes a sub-route, and it must name a real category.
            if head != "settings" || tail.contains(':') {
                return Err(RouteError::Unknown);
            }
            return Ok(SurfaceRoute::Settings(Some(SettingsCategory::parse(tail)?)));
        }
        match head {
            "settings" => Ok(SurfaceRoute::Settings(None)),
            "emoji" => Ok(SurfaceRoute::Emoji),
            "keyboard" => Ok(SurfaceRoute::Keyboard),
            "handwriting" => Ok(SurfaceRoute::Handwriting),
            "voice" => Ok(SurfaceRoute::Voice),
            "clipboard" => Ok(SurfaceRoute::Clipboard),
            "cloud-clipboard" => Ok(SurfaceRoute::CloudClipboard),
            "cloud-dictionary" => Ok(SurfaceRoute::CloudDictionary),
            _ => Err(RouteError::Unknown),
        }
    }

    /// The settings section this route names, if it names one. Hosts use it to
    /// open the settings window directly on the section a menu entry asked for.
    pub fn settings_category(self) -> Option<SettingsCategory> {
        match self {
            SurfaceRoute::Settings(category) => category,
            _ => None,
        }
    }

    /// The panel window this route opens, or `None` when the route targets the
    /// main settings window.
    pub fn panel(self) -> Option<PanelSurface> {
        match self {
            SurfaceRoute::Settings(_) => None,
            SurfaceRoute::Keyboard => Some(PanelSurface {
                label: "keyboard-panel",
                query: "keyboard",
                title: "水杉屏幕键盘",
                width: 1100,
                height: 400,
            }),
            SurfaceRoute::Handwriting => Some(PanelSurface {
                label: "handwriting-panel",
                query: "handwriting",
                title: "水杉手写识别板",
                width: 980,
                height: 650,
            }),
            SurfaceRoute::Emoji => Some(PanelSurface {
                label: "emoji-panel",
                query: "emoji",
                title: "Emoji and more",
                width: 720,
                height: 720,
            }),
            SurfaceRoute::Voice => Some(PanelSurface {
                label: "voice-panel",
                query: "voice",
                title: "水杉语音输入",
                width: 620,
                height: 520,
            }),
            SurfaceRoute::Clipboard => Some(PanelSurface {
                label: "clipboard-panel",
                query: "clipboard",
                title: "水杉本地剪贴板",
                width: 560,
                height: 620,
            }),
            SurfaceRoute::CloudClipboard => Some(PanelSurface {
                label: "cloud-clipboard-panel",
                query: "cloud-clipboard",
                title: "水杉云剪贴板",
                width: 560,
                height: 560,
            }),
            SurfaceRoute::CloudDictionary => Some(PanelSurface {
                label: "cloud-dictionary-panel",
                query: "cloud-dictionary",
                title: "水杉云词典",
                width: 760,
                height: 700,
            }),
        }
    }

    pub const ALL: [SurfaceRoute; 8] = [
        SurfaceRoute::Settings(None),
        SurfaceRoute::Emoji,
        SurfaceRoute::Keyboard,
        SurfaceRoute::Handwriting,
        SurfaceRoute::Voice,
        SurfaceRoute::Clipboard,
        SurfaceRoute::CloudClipboard,
        SurfaceRoute::CloudDictionary,
    ];
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_route_round_trips_through_its_argument() {
        for route in SurfaceRoute::ALL {
            assert_eq!(SurfaceRoute::parse(&route.as_arg()), Ok(route));
        }
        for category in SettingsCategory::ALL {
            let route = SurfaceRoute::Settings(Some(category));
            assert_eq!(SurfaceRoute::parse(&route.as_arg()), Ok(route));
        }
    }

    #[test]
    fn settings_deep_link_names_a_category() {
        assert_eq!(
            SurfaceRoute::parse("settings:voice"),
            Ok(SurfaceRoute::Settings(Some(SettingsCategory::Voice)))
        );
        assert_eq!(
            SurfaceRoute::parse("settings:floating-toolbar"),
            Ok(SurfaceRoute::Settings(Some(
                SettingsCategory::FloatingToolbar
            )))
        );
        assert_eq!(
            SurfaceRoute::parse("settings"),
            Ok(SurfaceRoute::Settings(None))
        );
    }

    #[test]
    fn malformed_routes_are_rejected_rather_than_guessed() {
        assert_eq!(SurfaceRoute::parse(""), Err(RouteError::Empty));
        assert_eq!(
            SurfaceRoute::parse(&"a".repeat(MAX_ROUTE_BYTES + 1)),
            Err(RouteError::TooLong)
        );
        assert_eq!(
            SurfaceRoute::parse("Settings"),
            Err(RouteError::IllegalCharacter)
        );
        assert_eq!(
            SurfaceRoute::parse("emoji\n"),
            Err(RouteError::IllegalCharacter)
        );
        assert_eq!(
            SurfaceRoute::parse("emoji panel"),
            Err(RouteError::IllegalCharacter)
        );
        assert_eq!(
            SurfaceRoute::parse("settings:voice:extra"),
            Err(RouteError::Unknown)
        );
        assert_eq!(
            SurfaceRoute::parse("settings:unknown"),
            Err(RouteError::Unknown)
        );
        assert_eq!(SurfaceRoute::parse("emoji:input"), Err(RouteError::Unknown));
        assert_eq!(SurfaceRoute::parse("account"), Err(RouteError::Unknown));
    }

    #[test]
    fn settings_routes_name_the_section_to_open() {
        assert_eq!(
            SurfaceRoute::parse("settings:about")
                .unwrap()
                .settings_category(),
            Some(SettingsCategory::About)
        );
        assert_eq!(
            SurfaceRoute::parse("settings:dictionary")
                .unwrap()
                .settings_category(),
            Some(SettingsCategory::Dictionary)
        );
        // A bare settings route keeps whichever page the shared UI defaults to.
        assert_eq!(SurfaceRoute::Settings(None).settings_category(), None);
        // A panel route never selects a settings section.
        assert_eq!(SurfaceRoute::Emoji.settings_category(), None);
        assert_eq!(SurfaceRoute::Clipboard.settings_category(), None);

        // Every category round-trips through the route a launcher would emit.
        for category in SettingsCategory::ALL {
            let argument = SurfaceRoute::Settings(Some(category)).as_arg();
            assert_eq!(
                SurfaceRoute::parse(&argument).unwrap().settings_category(),
                Some(category)
            );
        }
    }

    #[test]
    fn panel_routes_keep_the_labels_the_hosts_already_use() {
        assert_eq!(SurfaceRoute::Settings(None).panel(), None);
        assert_eq!(
            SurfaceRoute::Settings(Some(SettingsCategory::Input)).panel(),
            None
        );
        let keyboard = SurfaceRoute::Keyboard.panel().expect("keyboard is a panel");
        assert_eq!(keyboard.label, "keyboard-panel");
        assert_eq!(keyboard.query, "keyboard");
        for route in SurfaceRoute::ALL {
            let Some(panel) = route.panel() else { continue };
            // The window label is the query with the shared panel suffix.
            assert_eq!(panel.label, format!("{}-panel", panel.query));
            assert!(panel.width > 0 && panel.height > 0);
        }
    }

    #[test]
    fn capabilities_describe_each_host() {
        let linux = HostCapabilities::for_platform(HostPlatform::Linux);
        assert!(linux.restart_input_method);
        assert!(linux.ime_mode_scope);
        assert!(linux.panel_windows);
        assert!(linux.mode_switch_shortcuts);
        assert!(linux.panel_shortcuts);
        assert!(linux.voice_capture_devices);

        let windows = HostCapabilities::for_platform(HostPlatform::Windows);
        assert!(!windows.restart_input_method);
        assert!(!windows.ime_mode_scope);
        assert!(windows.panel_windows);
        // These stay false until the Windows host actually consumes them;
        // showing the controls earlier would offer settings that do nothing.
        assert!(!windows.mode_switch_shortcuts);
        assert!(!windows.panel_shortcuts);
        assert!(windows.system_fonts);

        let android = HostCapabilities::for_platform(HostPlatform::Android);
        assert!(!android.panel_windows);
        assert!(!android.window_chrome);
        // Typing statistics were previously gated on a user-agent match.
        assert!(android.typing_statistics);
        assert!(HostCapabilities::for_platform(HostPlatform::Windows).typing_statistics);
    }

    #[test]
    fn capabilities_round_trip_and_reject_unknown_keys() {
        let capabilities = HostCapabilities::for_platform(HostPlatform::Macos);
        let text = serde_json::to_string(&capabilities).expect("serializes");
        assert_eq!(
            serde_json::from_str::<HostCapabilities>(&text).expect("deserializes"),
            capabilities
        );
        let mut document: serde_json::Value = serde_json::from_str(&text).expect("valid JSON");
        document["unexpected"] = serde_json::Value::Bool(true);
        assert!(serde_json::from_value::<HostCapabilities>(document).is_err());
    }

    #[test]
    fn platform_names_round_trip() {
        for platform in [
            HostPlatform::Windows,
            HostPlatform::Macos,
            HostPlatform::Linux,
            HostPlatform::Android,
            HostPlatform::Ios,
        ] {
            assert_eq!(HostPlatform::parse(platform.as_str()), Ok(platform));
        }
        assert_eq!(HostPlatform::parse(""), Err(RouteError::Empty));
        assert_eq!(HostPlatform::parse("bsd"), Err(RouteError::Unknown));
    }
}
