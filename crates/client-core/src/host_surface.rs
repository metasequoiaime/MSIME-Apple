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
    /// The HarmonyOS phone host. Its keyboard is an InputMethodExtensionAbility panel, so it groups with the mobile hosts rather than the desktop ones. A HarmonyOS 2in1 host would group with the desktop side instead, but it gets its own variant only once that host exists: every capability keyed off `is_desktop` would otherwise claim a surface no HarmonyOS code has written yet.
    Harmony,
}

impl HostPlatform {
    pub fn as_str(self) -> &'static str {
        match self {
            HostPlatform::Windows => "windows",
            HostPlatform::Macos => "macos",
            HostPlatform::Linux => "linux",
            HostPlatform::Android => "android",
            HostPlatform::Ios => "ios",
            HostPlatform::Harmony => "harmony",
        }
    }

    pub fn parse(value: &str) -> Result<Self, RouteError> {
        match value {
            "windows" => Ok(HostPlatform::Windows),
            "macos" => Ok(HostPlatform::Macos),
            "linux" => Ok(HostPlatform::Linux),
            "android" => Ok(HostPlatform::Android),
            "ios" => Ok(HostPlatform::Ios),
            "harmony" => Ok(HostPlatform::Harmony),
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
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct HostCapabilities {
    pub platform: HostPlatform,
    /// The shared settings surface uses phone navigation and touch-oriented copy. This is usually
    /// the inverse of `is_desktop`, but a host may override it from the actual device form factor:
    /// one HarmonyOS HAP runs on both phones and 2-in-1 machines.
    pub mobile_settings: bool,
    /// The host can restart the input method service from the settings page.
    pub restart_input_method: bool,
    /// The host can open the shared panels as separate always-on-top windows.
    pub panel_windows: bool,
    /// The host keeps per-application versus global Chinese/English mode state.
    pub ime_mode_scope: bool,
    /// The host records typing statistics.
    pub typing_statistics: bool,
    /// The host exposes the shared fuzzy-pinyin settings.
    pub fuzzy_pinyin: bool,
    /// The host can enumerate installed font families.
    pub system_fonts: bool,
    /// The shared UI draws its own titlebar and resize handles.
    pub window_chrome: bool,
    /// The host presents a floating toolbar in some form. On Linux that is the
    /// IBus property menu rather than a drawn window, so the enable switch and
    /// component visibility are the meaningful controls there.
    pub floating_toolbar: bool,
    /// The toolbar surface honours scale and icon size. An IBus property menu
    /// cannot express either value.
    pub floating_toolbar_appearance: bool,
    /// The host can independently show or hide toolbar components. Linux
    /// expresses this through the IBus property menu even though it cannot
    /// draw the Windows/macOS floating window.
    pub floating_toolbar_components: bool,
    /// The toolbar carries a button that opens the handwriting panel. The
    /// reference's toolbar has six components and this is not one of them, so
    /// only the host that draws the button offers the switch for it.
    #[serde(default)]
    pub floating_toolbar_handwriting: bool,
    /// The toolbar carries a button that starts and stops voice input, for the
    /// same reason as `floating_toolbar_handwriting`.
    #[serde(default)]
    pub floating_toolbar_voice: bool,
    /// The host consumes the shared `keybindings` preferences to switch
    /// Chinese/English and simplified/traditional mode.
    pub mode_switch_shortcuts: bool,
    /// The desktop environment forwards a shortcut that opens a shared panel.
    pub panel_shortcuts: bool,
    /// The host can let the user release number-row candidate selection back
    /// to the focused application.
    #[serde(default)]
    pub number_row_selection: bool,
    /// The host can enumerate audio capture devices for voice input.
    pub voice_capture_devices: bool,
    /// The host can apply candidate font family, fallback family and size preferences.
    pub candidate_font_controls: bool,
    /// The composition drawn beside the candidates has its own size. Linux reads the family and
    /// candidate size into the desktop panel's single font, but the composition itself is drawn by
    /// the focused application, so a separate preedit size would have nothing to change there.
    #[serde(default)]
    pub candidate_preedit_font: bool,
    /// The host can apply candidate foreground/background RGB row colors.
    /// Linux exposes these through IBusText attributes even though it cannot
    /// draw the native card geometry or hover state.
    pub candidate_row_colors: bool,
    /// The host can apply candidate accent, selection, hover and border appearance.
    pub candidate_selection_appearance: bool,
    /// The host places its own candidate window and can therefore pin it where
    /// it first appeared. A host whose desktop owns the placement - IBus draws
    /// and positions the candidate list itself - cannot honour the choice, so
    /// it does not offer it.
    pub candidate_follow_cursor: bool,
    /// The host has more than one way to put a recognized result into the
    /// focused editor, so choosing between them is a real choice. A host with a
    /// single commit path does not offer it: a control with one outcome reads
    /// as a setting that is being ignored.
    #[serde(default)]
    pub voice_commit_mode: bool,
    /// The host renders the Engine's composition text itself, so the choice
    /// between the raw shuangpin keys and the expanded pinyin is visible there.
    /// Every host's Engine honours the preference; this says which of them draw
    /// the result where a user would see the difference. A host that hands the
    /// snapshot's `preedit` to a desktop panel still decides which string goes
    /// there, so the difference is its to show.
    #[serde(default)]
    pub shuangpin_preedit: bool,
    /// The host tells the runtime which character width it is in, so the Engine
    /// widens what it commits. The preference is the width a session starts at;
    /// the host's own toolbar, menu or chord moves it from there. A host that
    /// never makes that call cannot honour the preference at all, and offering
    /// the switch there would be a control with nothing behind it.
    #[serde(default)]
    pub character_width: bool,
    /// The host runs the configured transcription provider itself, so the provider, model and
    /// credential controls have something behind them.
    ///
    /// Was a platform name on the settings page, and it read `!android` because that host once had
    /// only the platform recogniser. It runs the configured provider now — the OpenAI-compatible
    /// uploads and the streaming socket both — and a page keyed on the name would still be hiding
    /// the controls.
    /// The host routes the Ctrl+Shift+Alt maintenance chords: delete the candidate in a numbered
    /// slot, and drop the cached candidate list.
    ///
    /// Touch reaches both by gesture — a long press on the candidate, and nothing at all for the
    /// cache — so a keyboard needs the chords or cannot reach them. Declared rather than inferred
    /// from "draws desktop panels", which is what it used to be read off and is a different fact.
    #[serde(default)]
    pub maintenance_shortcuts: bool,
    /// The host reserves the Option/Alt+Shift+H chord for the character width, so the switch that
    /// gives it back to the application belongs on its settings page.
    #[serde(default)]
    pub fullwidth_chord: bool,
    #[serde(default)]
    pub voice_provider_settings: bool,
    /// The host draws the recogniser's interim text while the user is still speaking.
    ///
    /// Every host can ask a streaming provider for partial results; this says which of them has
    /// somewhere to put one. A host without that surface would be offering a switch whose only
    /// effect is on a display it does not have.
    #[serde(default)]
    pub voice_stream_preedit: bool,
    /// The host shows read-only English word completions while typing directly
    /// in English, governed by the shared `english_suggestions` preference. iOS
    /// offers the same surface but keeps its switch in the native App Group
    /// store, so it reads this as false and shows its own control.
    #[serde(default)]
    pub english_suggestions: bool,
    /// A letter becomes a helper code because the user held Shift for it, rather
    /// than because of where it sits in the spelling. Windows appends helper
    /// codes directly to a finished pinyin and needs no gesture; a keyboard host
    /// does, or the letter would be eaten as more pinyin. The hosts that mark
    /// them this way are the ones running the ported ChineseHelpcodePolicy, and
    /// the settings page explains the gesture only where it applies.
    #[serde(default)]
    pub helpcode_shift_entry: bool,
    /// A skin arrives by being picked rather than by being dropped into a
    /// folder. The source opens its skin folder so the user can put one there;
    /// a host whose folder is inside an application sandbox has nothing to
    /// open, so it asks the user to point at the skin instead. The page needs
    /// to know which of the two it is, because the button says so.
    #[serde(default)]
    pub skin_directory_import: bool,
    /// The one candidate page size the host draws, when it offers no choice. The iOS keyboard numbers its strip's chips 1-9 to match the digits on its symbol layer and lays the expanded panel out in nines, so it holds the Engine to nine whatever the shared setting says; the page shows the count instead of a selector that would do nothing. Absent on a host that pages by the setting.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fixed_candidate_page_size: Option<u8>,
    /// The one candidate layout the host draws, when it offers no choice. The iOS candidate strip is a horizontal row above the keys, so an external skin is adopted there only for its horizontal layout; the skin page has to judge compatibility by that rather than by the shared setting, which defaults to vertical. Absent on a host that follows the setting.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fixed_candidate_layout: Option<crate::preferences::CandidateLayout>,
    /// The host applies a separate family for Latin text in the candidate panel.
    /// A host whose renderer resolves one family list per glyph, or which draws
    /// Latin from its own font, can honour this; one with a single typeface for
    /// the whole row cannot, and does not offer the choice.
    #[serde(default)]
    pub candidate_english_font: bool,
    /// The AI service's credential lives with the host's provider rather than in
    /// the settings document, so the settings page must not ask for a token and
    /// must not gate the service controls on having one. The host still reaches
    /// the service - through that provider - so the model listing and the polish
    /// test are offered; what it cannot do is hold the secret.
    #[serde(default)]
    pub ai_provider_credentials: bool,
    /// The host draws a short, non-activating badge near the caret after the
    /// Chinese/English mode changes. A host with no way to put a window beside
    /// the caret, or one whose keyboard already shows the mode on its own key
    /// faces, has nothing to switch on and does not offer the choice.
    #[serde(default)]
    pub input_mode_hud: bool,
    /// The host can run a 背单词 review session — that is, it has wired the shared vocabulary
    /// entry point and can reach the review store.
    ///
    /// Defaulting to false is the point: a host built before this field existed sends a document
    /// without it, and the page must then stay hidden rather than offer 认识 / 不认识 buttons whose
    /// every press fails. The same rule the other optional capabilities follow.
    #[serde(default)]
    pub vocabulary_review: bool,
    /// The operating system release, as the machine reports it, for the feedback
    /// page to attach. Not a platform assumption like the flags above -- the host
    /// fills it in after `for_platform`, the way `system_fonts` is filled in --
    /// so a host with no cheap way to read it simply leaves it out and the page
    /// falls back to what the web view knows about itself.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub os_version: Option<String>,
}

impl HostCapabilities {
    /// Capabilities as they stand today for each shipped host. Slices that add a
    /// capability to a host flip its flag here, and every consumer follows.
    pub fn for_platform(platform: HostPlatform) -> Self {
        HostCapabilities {
            platform,
            mobile_settings: !platform.is_desktop(),
            // Linux restarts IBus; Windows sends a request to the supervised
            // native Server over its session-less auxiliary pipe; macOS starts
            // a fresh bundle instance with --reregister-input-source so
            // InputMethodKit can discover and enable the current source.
            restart_input_method: matches!(
                platform,
                HostPlatform::Windows | HostPlatform::Linux | HostPlatform::Macos
            ),
            panel_windows: platform.is_desktop(),
            // IBus keeps a session-wide mode. Windows keeps a cross-application
            // CN/EN authority, while macOS switches between its per-application
            // map and a process-wide authority when a client activates.
            // The HarmonyOS keyboard learns which application an editor belongs to from the
            // editor attribute's bundle name, so it can keep the same per-application map the
            // desktop hosts do. A touch host that cannot name the editor's application has nothing
            // to key one on and keeps a single mode.
            ime_mode_scope: matches!(
                platform,
                HostPlatform::Linux
                    | HostPlatform::Windows
                    | HostPlatform::Macos
                    | HostPlatform::Android
                    | HostPlatform::Harmony
            ),
            typing_statistics: true,
            // Every input host consumes the shared fuzzy-pinyin options. The
            // iOS Tauri settings surface writes the same PreferencesStore that
            // the keyboard extension reloads before applying its session.
            fuzzy_pinyin: matches!(
                platform,
                HostPlatform::Windows
                    | HostPlatform::Linux
                    | HostPlatform::Macos
                    | HostPlatform::Android
                    | HostPlatform::Ios
                    | HostPlatform::Harmony
            ),
            // ArkUI hands the installed family names straight to the settings page, so the font
            // inputs can offer a list there rather than asking for an exact name to be typed.
            system_fonts: platform.is_desktop() || platform == HostPlatform::Harmony,
            window_chrome: platform.is_desktop(),
            // A 2in1 draws one from the input method's own status-bar panel, which needs none of
            // the window permissions a desktop floating window would. A HarmonyOS phone has no use
            // for one: the surfaces are on the keyboard's own key faces there.
            floating_toolbar: platform.is_desktop() || platform == HostPlatform::Harmony,
            // macOS FloatingToolbarPanel.mm and the Windows FloatingToolbarWindow
            // both read scale_percent and font_size; the Linux host has no
            // equivalent surface for those two values. The HarmonyOS panel
            // scales its own frame by the former and draws its faces at the
            // latter.
            floating_toolbar_appearance: matches!(
                platform,
                HostPlatform::Windows | HostPlatform::Macos | HostPlatform::Harmony
            ),
            // Linux maps the component switches to IBus menu entries; the
            // native-window hosts apply them to their own toolbar buttons. The
            // HarmonyOS panel hides the button and narrows itself, and its
            // emoji and screen-keyboard buttons open the same surfaces its
            // phone keyboard reaches from a key face.
            floating_toolbar_components: platform.is_desktop() || platform == HostPlatform::Harmony,
            // Only this client's macOS toolbar draws these two.
            floating_toolbar_handwriting: platform == HostPlatform::Macos,
            floating_toolbar_voice: platform == HostPlatform::Macos,
            // The IBus host consumes these directly. The Windows Server now
            // mirrors them into the shared config.toml the TIP reads at
            // activation, so the toggles take effect there too. The HarmonyOS
            // host reads all four in its hardware key router, which only a
            // machine with a physical keyboard has anything to route.
            mode_switch_shortcuts: matches!(
                platform,
                HostPlatform::Linux
                    | HostPlatform::Windows
                    | HostPlatform::Macos
                    | HostPlatform::Android
                    | HostPlatform::Harmony
            ),
            // Windows handles Ctrl+Shift+Win+K on its maintenance hook; Linux
            // uses the current IBus context, and macOS uses the current IMK
            // context with Command in place of the Windows/Super modifier. A
            // HarmonyOS keyboard extension has no global hook and sees keys only
            // while attached to an editor, which turns out to be the wrong
            // reason to withhold this: the panel inserts into the focused
            // editor, so an editor is the precondition for it being useful at
            // all rather than a restriction on when the chord may fire.
            panel_shortcuts: matches!(
                platform,
                HostPlatform::Linux
                    | HostPlatform::Windows
                    | HostPlatform::Macos
                    | HostPlatform::Harmony
            ),
            // Harmony 2-in-1 hardware keyboards use the same candidate number
            // row as Windows; the ArkTS router releases digits when this
            // preference is enabled, so the focused editor can consume them.
            number_row_selection: matches!(
                platform,
                HostPlatform::Linux | HostPlatform::Android | HostPlatform::Harmony
            ),
            // HarmonyOS records through its own AudioCapturer for the HTTP and Doubao providers, so
            // the routing manager's input devices are both enumerable and selectable there. The
            // system speech recognizer keeps its audio inside the service and is unaffected either
            // way; nothing else on this host owns a microphone.
            voice_capture_devices: matches!(
                platform,
                HostPlatform::Linux
                    | HostPlatform::Windows
                    | HostPlatform::Macos
                    | HostPlatform::Harmony
            ),
            // Native Windows/macOS candidate windows consume the shared font
            // controls. Harmony's desktop candidate panel and Android's and
            // iOS's native candidate bars also apply the family chain and both
            // candidate/preedit sizes. Linux writes the family chain and
            // candidate size into the panel's font: the IBus panel settings or
            // the Fcitx5 classic UI.
            candidate_font_controls: true,
            // The iOS strip scales its composition line by `candidate_preedit_font_size`.
            candidate_preedit_font: matches!(
                platform,
                HostPlatform::Windows
                    | HostPlatform::Macos
                    | HostPlatform::Harmony
                    | HostPlatform::Android
                    | HostPlatform::Ios
            ),
            // IBus exposes candidate and label foreground/background RGB
            // attributes, but not native hover state or card borders. The iOS strip resolves every candidate colour once the keyboard's 「使用桌面候选皮肤」 switch is on, which the shared skin page now carries.
            candidate_row_colors: matches!(
                platform,
                HostPlatform::Windows
                    | HostPlatform::Macos
                    | HostPlatform::Linux
                    | HostPlatform::Harmony
                    | HostPlatform::Android
                    | HostPlatform::Ios
            ),
            candidate_selection_appearance: matches!(
                platform,
                HostPlatform::Windows
                    | HostPlatform::Macos
                    | HostPlatform::Harmony
                    | HostPlatform::Android
                    | HostPlatform::Ios
            ),
            // macOS CandidatePanel and the HarmonyOS candidate panel track the current insertion
            // rect themselves; expose the shared toggle on both hosts.
            candidate_follow_cursor: matches!(
                platform,
                HostPlatform::Windows | HostPlatform::Macos | HostPlatform::Harmony
            ),
            // macOS shows it from a non-activating panel. Harmony shows the same badge from a
            // status-bar panel on a 2in1, which is the one form factor with a hardware keyboard and
            // therefore the one where nothing else on screen says the mode changed; its phone
            // keyboard says so on its own key faces and needs no badge. Linux does not draw the
            // badge itself either - the Fcitx5 panel offers exactly this popup for "input method
            // that has internal switches", which is what the Chinese/English mode is, so the host
            // asks the panel rather than placing a window of its own.
            input_mode_hud: matches!(
                platform,
                HostPlatform::Macos | HostPlatform::Harmony | HostPlatform::Linux
            ),
            // macOS draws its own composition, and the HarmonyOS keyboard draws the Engine's
            // editing text on its composition row, so both show the difference. The other hosts
            // hand the text to the application or to the desktop, which decides how it looks.
            // Windows chooses between TSF, SendInput and a paste; macOS between system events and
            // its input session; Linux hands the choice to the user's provider service. A keyboard
            // extension commits through its input client and has nothing to choose between.
            voice_commit_mode: matches!(
                platform,
                HostPlatform::Windows | HostPlatform::Macos | HostPlatform::Linux
            ),
            // The Linux hosts write the snapshot's `preedit` into the IBus and
            // Fcitx5 preedit themselves, and both already carry their own
            // toggle for this in the native status menu - a setting the shared
            // page was hiding could only be reached from there, and only while
            // the shuangpin scheme was active.
            shuangpin_preedit: matches!(
                platform,
                HostPlatform::Macos
                    | HostPlatform::Harmony
                    | HostPlatform::Linux
                    | HostPlatform::Ios
            ),
            // Every host calls `msime_client_set_character_width` when its session starts and
            // from its own width switch, so the preference always has something to act on.
            character_width: true,
            // The Android recognition window shows the transcript once it is settled and has no row for a partial one; putting half-written text there that the final result may contradict is worse than waiting for it. iOS records in the app, because a keyboard extension cannot use the microphone, and hands the keyboard only the final transcript, so it has no row for one either. Every other host draws its own composition.
            // Every host reaches its provider one way or another: the desktops and both mobile
            // hosts call it themselves, and Linux hands the same configuration to its provider
            // service. None of them wants these controls hidden.
            // Harmony reaches this through its form-factor projection of `panel_windows`, which
            // the page still consults, so it is not named here and its behaviour is unchanged.
            maintenance_shortcuts: platform.is_desktop() || platform == HostPlatform::Android,
            // macOS has reserved it since it shipped; the Android host reads the same preference
            // for its own Alt+Shift+H. No other host binds that chord.
            fullwidth_chord: matches!(platform, HostPlatform::Macos | HostPlatform::Android),
            voice_provider_settings: true,
            voice_stream_preedit: !matches!(platform, HostPlatform::Android | HostPlatform::Ios),
            english_suggestions: matches!(platform, HostPlatform::Android | HostPlatform::Harmony),
            // Android, HarmonyOS and the iOS keyboard extension share one gesture: Shift during a quanpin or shuangpin composition hands the next letter to the Engine as a helper code. The desktop hosts append the code to a finished spelling instead of marking it.
            helpcode_shift_entry: matches!(
                platform,
                HostPlatform::Android | HostPlatform::Harmony | HostPlatform::Ios
            ),
            // The skin folder is inside the sandbox on HarmonyOS and in the App Group container on iOS, where no file manager reaches it, so the skin is picked and copied in instead.
            skin_directory_import: matches!(platform, HostPlatform::Harmony | HostPlatform::Ios),
            fixed_candidate_page_size: (platform == HostPlatform::Ios).then_some(9),
            fixed_candidate_layout: (platform == HostPlatform::Ios)
                .then_some(crate::preferences::CandidateLayout::Horizontal),
            // Linux keeps AI credentials in the provider service's owner-only
            // configuration file and passes only non-sensitive options over its
            // socket. Every other host holds the token itself.
            ai_provider_credentials: platform == HostPlatform::Linux,
            // Windows draws Latin from its own family, macOS and Android name it ahead of the primary one, and ArkUI resolves a family list per glyph, so HarmonyOS reaches the same result the same way. Both Linux hosts write one Pango font description for the desktop panel, and Pango resolves its family list per glyph too, so they name it first there.
            candidate_english_font: true,
            // Every host reaches the same shared store through the same entry point, so there is
            // no platform here that can and one that cannot. The flag exists for the version
            // skew: a host binary older than the entry point sends no field and gets `false`.
            vocabulary_review: true,
            os_version: None,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum SettingsCategory {
    /// The account page, the AI conversation and the community browser are pages of the same shared
    /// settings surface as the rest. They were missing from this list, so no host could route to them and
    /// macOS opened its own account window instead of the page the other platforms show.
    Account,
    Chat,
    Community,
    Appearance,
    Input,
    TypingStatistics,
    Helpcode,
    Shortcuts,
    Dictionary,
    /// 背单词. Next to the dictionary because both are word lists the user manages, and away from
    /// the input pages because nothing on it changes how typing behaves.
    Vocabulary,
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
            SettingsCategory::Account => "account",
            SettingsCategory::Chat => "chat",
            SettingsCategory::Community => "community",
            SettingsCategory::Appearance => "appearance",
            SettingsCategory::Input => "input",
            SettingsCategory::TypingStatistics => "typing-statistics",
            SettingsCategory::Helpcode => "helpcode",
            SettingsCategory::Shortcuts => "shortcuts",
            SettingsCategory::Dictionary => "dictionary",
            SettingsCategory::Vocabulary => "vocabulary",
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
            "account" => Ok(SettingsCategory::Account),
            "chat" => Ok(SettingsCategory::Chat),
            "community" => Ok(SettingsCategory::Community),
            "appearance" => Ok(SettingsCategory::Appearance),
            "input" => Ok(SettingsCategory::Input),
            "typing-statistics" => Ok(SettingsCategory::TypingStatistics),
            "helpcode" => Ok(SettingsCategory::Helpcode),
            "shortcuts" => Ok(SettingsCategory::Shortcuts),
            "dictionary" => Ok(SettingsCategory::Dictionary),
            "vocabulary" => Ok(SettingsCategory::Vocabulary),
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

    pub const ALL: [SettingsCategory; 20] = [
        SettingsCategory::Account,
        SettingsCategory::Chat,
        SettingsCategory::Community,
        SettingsCategory::Appearance,
        SettingsCategory::Input,
        SettingsCategory::TypingStatistics,
        SettingsCategory::Helpcode,
        SettingsCategory::Shortcuts,
        SettingsCategory::Dictionary,
        SettingsCategory::Vocabulary,
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
    /// 背单词. A panel rather than a settings page: a review session is something a learner opens
    /// for ten minutes a day, and a settings window is a drawer people open to flip one switch and
    /// leave. It is not the candidate window either — reviewing means recalling a word before the
    /// meaning appears, and that cannot share attention with composing a sentence.
    Vocabulary,
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
            SurfaceRoute::Vocabulary => "vocabulary".to_string(),
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
            "vocabulary" => Ok(SurfaceRoute::Vocabulary),
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
            SurfaceRoute::Vocabulary => Some(PanelSurface {
                label: "vocabulary-panel",
                query: "vocabulary",
                title: "水杉背单词",
                // Taller than it is wide: the card is the page, and a wide window would strand the
                // word in the middle of empty space. Close to the clipboard panel's footprint, so
                // it lands where a user already expects a summoned panel to be.
                width: 560,
                height: 680,
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

    pub const ALL: [SurfaceRoute; 9] = [
        SurfaceRoute::Settings(None),
        SurfaceRoute::Emoji,
        SurfaceRoute::Keyboard,
        SurfaceRoute::Handwriting,
        SurfaceRoute::Voice,
        SurfaceRoute::Clipboard,
        SurfaceRoute::CloudClipboard,
        SurfaceRoute::CloudDictionary,
        SurfaceRoute::Vocabulary,
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
        assert!(!linux.mobile_settings);
        assert!(linux.restart_input_method);
        assert!(linux.ime_mode_scope);
        assert!(linux.panel_windows);
        assert!(linux.mode_switch_shortcuts);
        // Linux stands the toolbar up as an IBus property menu: the switch and
        // component visibility work, but scale and icon size have no surface.
        assert!(linux.floating_toolbar);
        assert!(!linux.floating_toolbar_appearance);
        assert!(linux.floating_toolbar_components);
        assert!(linux.panel_shortcuts);
        assert!(linux.number_row_selection);
        assert!(linux.voice_capture_devices);
        assert!(linux.candidate_font_controls);
        assert!(!linux.candidate_preedit_font);
        assert!(linux.candidate_row_colors);
        assert!(!linux.candidate_selection_appearance);
        // IBus owns the candidate list's placement, so the host cannot pin it.
        assert!(!linux.candidate_follow_cursor);
        // The host chooses the preedit string the panel draws, so the raw keys
        // and the expanded pinyin are both reachable from the shared page.
        assert!(linux.shuangpin_preedit);
        // The AI token is the provider's, so the page neither asks for one nor
        // withholds the service controls for want of it. Every other host holds
        // the token itself and must keep asking.
        assert!(linux.ai_provider_credentials);
        for platform in [
            HostPlatform::Windows,
            HostPlatform::Macos,
            HostPlatform::Android,
            HostPlatform::Ios,
            HostPlatform::Harmony,
        ] {
            assert!(!HostCapabilities::for_platform(platform).ai_provider_credentials);
        }

        let windows = HostCapabilities::for_platform(HostPlatform::Windows);
        assert!(!windows.number_row_selection);
        assert!(windows.restart_input_method);
        // Windows keeps a cross-application CN/EN authority, so the scope
        // choice is real there.
        assert!(windows.ime_mode_scope);
        assert!(windows.panel_windows);
        // The source appends a helper code to a finished spelling; no gesture marks it, so the
        // explanation of the gesture would be describing something that does not happen here.
        assert!(!windows.helpcode_shift_entry);
        assert!(!windows.skin_directory_import);
        // The Server mirrors these into the shared config.toml the TIP reads,
        // so the controls offer settings that actually take effect.
        assert!(windows.mode_switch_shortcuts);
        assert!(
            windows.floating_toolbar
                && windows.floating_toolbar_appearance
                && windows.floating_toolbar_components
        );
        assert!(windows.candidate_font_controls);
        assert!(windows.candidate_preedit_font);
        assert!(windows.candidate_row_colors);
        assert!(windows.candidate_selection_appearance);
        // Windows positions its own card, so pinning it is a real choice there.
        assert!(windows.candidate_follow_cursor);
        let macos = HostCapabilities::for_platform(HostPlatform::Macos);
        assert!(macos.restart_input_method);
        // InputMethodKit controllers identify the active application; the
        // native preference owner selects either that map or its global mode.
        assert!(macos.ime_mode_scope);
        assert!(macos.voice_capture_devices);
        assert!(
            macos.floating_toolbar
                && macos.floating_toolbar_appearance
                && macos.floating_toolbar_components
        );
        assert!(macos.fuzzy_pinyin);
        assert!(macos.candidate_font_controls);
        assert!(macos.candidate_row_colors);
        assert!(macos.candidate_selection_appearance);
        assert!(macos.candidate_follow_cursor);
        assert!(macos.panel_shortcuts);
        // Only the two hosts that can put a badge beside the caret claim it; a touch keyboard says
        // the mode on its own key faces, and Windows/Linux draw nothing of the kind.
        assert!(macos.input_mode_hud);
        assert!(!windows.input_mode_hud);
        assert!(linux.input_mode_hud);
        assert!(!HostCapabilities::for_platform(HostPlatform::Android).input_mode_hud);
        assert!(!HostCapabilities::for_platform(HostPlatform::Ios).input_mode_hud);
        // Mobile hosts draw no toolbar at all.
        let android = HostCapabilities::for_platform(HostPlatform::Android);
        assert!(android.mobile_settings);
        // Android's InputMethodService keys the persisted mode by the focused
        // editor package when the shared scope is set to app.
        assert!(android.ime_mode_scope);
        assert!(
            !android.floating_toolbar
                && !android.floating_toolbar_appearance
                && !android.floating_toolbar_components
        );
        assert!(android.candidate_font_controls);
        assert!(android.candidate_row_colors);
        assert!(android.candidate_selection_appearance);
        let ios = HostCapabilities::for_platform(HostPlatform::Ios);
        assert!(ios.mobile_settings);
        assert!(ios.fuzzy_pinyin);
        assert!(ios.typing_statistics);
        assert!(!ios.panel_windows);
        // The candidate bar cascades the Latin face, the family and its fallbacks.
        assert!(ios.candidate_font_controls);
        assert!(ios.candidate_english_font);
        assert!(ios.candidate_preedit_font);
        assert!(ios.candidate_row_colors);
        assert!(ios.candidate_selection_appearance);
        // The Engine expands shuangpin keys for the candidate bar's spelling, and Shift marks a helper code in a quanpin or shuangpin composition, so both rows describe something the keyboard does.
        assert!(ios.shuangpin_preedit);
        assert!(ios.helpcode_shift_entry);
        // Files cannot reach the App Group skin folder, so the skin button imports a picked folder.
        assert!(ios.skin_directory_import);
        // The strip pages in nines and is always a horizontal row, whatever the shared document says.
        assert_eq!(ios.fixed_candidate_page_size, Some(9));
        assert_eq!(
            ios.fixed_candidate_layout,
            Some(crate::preferences::CandidateLayout::Horizontal)
        );
        for platform in [
            HostPlatform::Windows,
            HostPlatform::Macos,
            HostPlatform::Linux,
            HostPlatform::Android,
            HostPlatform::Harmony,
        ] {
            let other = HostCapabilities::for_platform(platform);
            assert_eq!(other.fixed_candidate_page_size, None);
            assert_eq!(other.fixed_candidate_layout, None);
        }
        // Windows handles Ctrl+Shift+Win+K on its maintenance hook, so the
        // panel shortcut row is real there now.
        assert!(windows.panel_shortcuts);
        // The CN/EN and 简繁 hotkeys are editable now: the Server mirrors them
        // into the config.toml the TIP reads, so the toggles take effect.
        assert!(windows.mode_switch_shortcuts);
        assert!(windows.system_fonts);

        let android = HostCapabilities::for_platform(HostPlatform::Android);
        assert!(!android.panel_windows);
        assert!(!android.window_chrome);
        // Typing statistics were previously gated on a user-agent match.
        assert!(android.typing_statistics);
        assert!(HostCapabilities::for_platform(HostPlatform::Windows).typing_statistics);
        assert!(HostCapabilities::for_platform(HostPlatform::Macos).mode_switch_shortcuts);
        assert!(HostCapabilities::for_platform(HostPlatform::Macos).voice_capture_devices);
        assert!(HostCapabilities::for_platform(HostPlatform::Macos).typing_statistics);
        assert!(linux.fuzzy_pinyin);
        assert!(android.fuzzy_pinyin);
        assert!(android.mode_switch_shortcuts);
        assert!(HostCapabilities::for_platform(HostPlatform::Windows).fuzzy_pinyin);
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
            HostPlatform::Harmony,
        ] {
            assert_eq!(HostPlatform::parse(platform.as_str()), Ok(platform));
        }
        assert_eq!(HostPlatform::parse(""), Err(RouteError::Empty));
        assert_eq!(HostPlatform::parse("bsd"), Err(RouteError::Unknown));
    }

    /// A newly named host must not claim a surface nobody has written. Every
    /// capability here stays false until a HarmonyOS host actually consumes it,
    /// so the shared UI never renders a control that saves and does nothing.
    #[test]
    fn harmony_groups_with_mobile_hosts_and_claims_nothing_unwritten() {
        assert!(!HostPlatform::Harmony.is_desktop());
        let harmony = HostCapabilities::for_platform(HostPlatform::Harmony);
        assert!(harmony.mobile_settings);
        assert!(!harmony.panel_windows);
        assert!(!harmony.window_chrome);
        // ArkUI enumerates the installed families, so the page can offer them.
        assert!(harmony.system_fonts);
        // ArkUI resolves a family list per glyph, which is how a separate Latin family is honoured.
        assert!(harmony.candidate_english_font);
        // The completions are drawn from the packaged dictionary on the candidate strip, and the
        // switch that governs them is the shared preference rather than a native store.
        assert!(harmony.english_suggestions);
        // The composition row draws the Engine's editing text, so raw versus expanded is visible.
        assert!(harmony.shuangpin_preedit);
        // One commit path, so there is nothing to choose between and no control for it.
        assert!(!harmony.voice_commit_mode);
        assert!(HostCapabilities::for_platform(HostPlatform::Windows).voice_commit_mode);
        assert!(HostCapabilities::for_platform(HostPlatform::Macos).shuangpin_preedit);
        assert!(!HostCapabilities::for_platform(HostPlatform::Windows).shuangpin_preedit);
        assert!(!HostCapabilities::for_platform(HostPlatform::Ios).english_suggestions);
        assert!(!HostCapabilities::for_platform(HostPlatform::Windows).english_suggestions);
        // Pango resolves the panel's family list per glyph, so the Linux hosts name the English family first.
        assert!(HostCapabilities::for_platform(HostPlatform::Linux).candidate_english_font);
        // 全角输入 was withheld from every touch platform, which was a statement about form
        // factor rather than about who can honour it. What decides is whether the host tells the
        // runtime a width: all six do, from a toolbar, a menu or the keyboard's own tools.
        for platform in [
            HostPlatform::Windows,
            HostPlatform::Macos,
            HostPlatform::Linux,
            HostPlatform::Android,
            HostPlatform::Harmony,
            HostPlatform::Ios,
        ] {
            assert!(HostCapabilities::for_platform(platform).character_width);
        }
        // Android and iOS run the configured transcription provider, streaming one included, but draw no interim text, so they are the hosts without that switch.
        for platform in [HostPlatform::Android, HostPlatform::Ios] {
            assert!(!HostCapabilities::for_platform(platform).voice_stream_preedit);
            assert!(HostCapabilities::for_platform(platform).voice_provider_settings);
        }
        // The two chords exist wherever a keyboard can send them and the host routes them.
        assert!(HostCapabilities::for_platform(HostPlatform::Android).maintenance_shortcuts);
        assert!(HostCapabilities::for_platform(HostPlatform::Windows).maintenance_shortcuts);
        assert!(!HostCapabilities::for_platform(HostPlatform::Ios).maintenance_shortcuts);
        assert!(HostCapabilities::for_platform(HostPlatform::Android).fullwidth_chord);
        assert!(HostCapabilities::for_platform(HostPlatform::Macos).fullwidth_chord);
        for platform in [
            HostPlatform::Windows,
            HostPlatform::Linux,
            HostPlatform::Ios,
            HostPlatform::Harmony,
        ] {
            assert!(!HostCapabilities::for_platform(platform).fullwidth_chord);
        }
        for platform in [
            HostPlatform::Windows,
            HostPlatform::Macos,
            HostPlatform::Linux,
            HostPlatform::Harmony,
        ] {
            assert!(HostCapabilities::for_platform(platform).voice_stream_preedit);
        }
        // Drawn from the input method's status-bar panel, which scales itself by the shared
        // scale and font size, hides the buttons the user turned off, and opens the emoji panel
        // and the screen keyboard in the window its candidates otherwise occupy.
        assert!(
            harmony.floating_toolbar
                && harmony.floating_toolbar_appearance
                && harmony.floating_toolbar_components
        );
        assert!(!harmony.restart_input_method);
        // The editor attribute carries the client's bundle name, so a per-application map is real.
        assert!(harmony.ime_mode_scope);
        // Harmony's Engine consumes the shared fuzzy-pinyin rules on every prepared session, so
        // the settings page may expose the same rule picker as the other mobile hosts.
        assert!(harmony.fuzzy_pinyin);
        // Consumed: the hardware key router reads all four bindings, so the page may offer them.
        assert!(harmony.mode_switch_shortcuts);
        // Consumed since the panel chord was bound: the extension sees Ctrl+Shift+Super+K while it
        // is attached to an editor, which is the only state in which a panel that inserts into that
        // editor is useful anyway.
        assert!(harmony.panel_shortcuts);
        // Shift marks a helper code here exactly as it does on Android; the page explains that
        // gesture and would otherwise have explained it to nobody on this host.
        assert!(harmony.helpcode_shift_entry);
        // Its skin folder is inside the sandbox, so the page asks the user to point at a skin
        // rather than offering to open a folder that nothing can browse.
        assert!(harmony.skin_directory_import);
        assert!(harmony.number_row_selection);
        // The two network providers create their own capturer, so a chosen microphone is routable.
        assert!(harmony.voice_capture_devices);
        assert!(harmony.candidate_font_controls);
        assert!(harmony.candidate_row_colors);
        assert!(harmony.candidate_selection_appearance);
        assert!(harmony.candidate_follow_cursor);
        // The 2in1 status-bar badge is the only mode readout a machine with a hardware keyboard
        // gets when the toolbar is off, so the switch that governs it belongs on this host too.
        assert!(harmony.input_mode_hud);
        // Typing statistics are unconditional across every host.
        assert!(harmony.typing_statistics);
    }
}
