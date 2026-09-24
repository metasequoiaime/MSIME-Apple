//! Versioned local preferences. Hosts supply a private application data directory.
//! All writers coordinate through the stable lock file, not the replaced data file.

use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum InputScheme {
    #[default]
    Quanpin,
    Shuangpin,
    Wubi,
    Japanese,
}

/// Presentation layout for touch keyboard hosts. Desktop hosts preserve but ignore it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum TouchKeyboardLayout {
    #[default]
    TwentySixKey,
    NineKey,
    Handwriting,
}

/// Apple-compatible built-in visual styles for touch keyboard hosts.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum TouchKeyboardSkin {
    #[default]
    Forest,
    Ocean,
    Rose,
    Porcelain,
    Typewriter,
    Candy,
    Midnight,
    Blueprint,
    Custom,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TouchSkinKeyShape {
    Rounded,
    Capsule,
    Ticket,
    Pebble,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TouchSkinKeyMaterial {
    Flat,
    Raised,
    Glass,
    Paper,
}

/// Apple-compatible current custom design. Named designs live in a separate bounded library.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields, rename_all = "camelCase")]
pub struct TouchKeyboardSkinDesign {
    pub background: u32,
    pub key_background: u32,
    pub key_foreground: u32,
    pub accent: u32,
    pub action_background: u32,
    pub corner_radius: f64,
    pub border_width: f64,
    pub shadow: f64,
    pub pattern: u8,
    pub monospaced: bool,
    pub key_shape: Option<TouchSkinKeyShape>,
    pub key_material: Option<TouchSkinKeyMaterial>,
    pub key_opacity: Option<f64>,
    pub gradient_end: Option<u32>,
    pub gradient_horizontal: Option<bool>,
    pub pattern_opacity: Option<f64>,
    pub custom_border_color: Option<u32>,
    /// Base64 image bytes, matching Swift JSONEncoder's Data representation.
    pub photo: Option<String>,
    pub photo_shade: Option<f64>,
    pub photo_position: Option<f64>,
}

impl Default for TouchKeyboardSkinDesign {
    fn default() -> Self {
        Self {
            background: 0xE8F0EB,
            key_background: 0xFFFFFF,
            key_foreground: 0x17251D,
            accent: 0x185C47,
            action_background: 0x185C47,
            corner_radius: 8.0,
            border_width: 0.0,
            shadow: 0.0,
            pattern: 0,
            monospaced: false,
            key_shape: None,
            key_material: None,
            key_opacity: None,
            gradient_end: None,
            gradient_horizontal: None,
            pattern_opacity: None,
            custom_border_color: None,
            photo: None,
            photo_shade: None,
            photo_position: None,
        }
    }
}

impl TouchKeyboardSkinDesign {
    pub(crate) fn validate(&self) -> bool {
        let colors = [
            Some(self.background),
            Some(self.key_background),
            Some(self.key_foreground),
            Some(self.accent),
            Some(self.action_background),
            self.gradient_end,
            self.custom_border_color,
        ];
        if colors.into_iter().flatten().any(|color| color > 0xFFFFFF)
            || !self.corner_radius.is_finite()
            || !(0.0..=20.0).contains(&self.corner_radius)
            || !self.border_width.is_finite()
            || !(0.0..=2.0).contains(&self.border_width)
            || !self.shadow.is_finite()
            || !(0.0..=0.4).contains(&self.shadow)
            || self.pattern > 3
            || !valid_optional_number(self.key_opacity, 0.25, 1.0)
            || !valid_optional_number(self.pattern_opacity, 0.0, 0.5)
            || !valid_optional_number(self.photo_shade, 0.0, 0.8)
            || !valid_optional_number(self.photo_position, 0.0, 1.0)
        {
            return false;
        }
        let Some(photo) = self.photo.as_ref() else {
            return true;
        };
        if photo.len() > 682_668 {
            return false;
        }
        let Ok(bytes) = BASE64.decode(photo) else {
            return false;
        };
        bytes.len() <= 512_000 && supported_skin_photo(&bytes)
    }

    /// Apple-compatible normalization used when a named design is loaded from its library.
    pub fn normalized(mut self) -> Self {
        self.background &= 0xFFFFFF;
        self.key_background &= 0xFFFFFF;
        self.key_foreground &= 0xFFFFFF;
        self.accent &= 0xFFFFFF;
        self.action_background &= 0xFFFFFF;
        self.corner_radius = normalized_number(self.corner_radius, 0.0, 20.0, 8.0);
        self.border_width = normalized_number(self.border_width, 0.0, 2.0, 0.0);
        self.shadow = normalized_number(self.shadow, 0.0, 0.4, 0.0);
        if self.pattern > 3 {
            self.pattern = 0;
        }
        self.key_opacity = self
            .key_opacity
            .map(|value| normalized_number(value, 0.25, 1.0, 1.0));
        self.gradient_end = self.gradient_end.map(|color| color & 0xFFFFFF);
        self.pattern_opacity = self
            .pattern_opacity
            .map(|value| normalized_number(value, 0.0, 0.5, 0.15));
        self.custom_border_color = self.custom_border_color.map(|color| color & 0xFFFFFF);
        self.photo_shade = self
            .photo_shade
            .map(|value| normalized_number(value, 0.0, 0.8, 0.25));
        self.photo_position = self
            .photo_position
            .map(|value| normalized_number(value, 0.0, 1.0, 0.5));
        if self.photo.is_some() && !self.validate() {
            self.photo = None;
        }
        self
    }
}

fn normalized_number(value: f64, minimum: f64, maximum: f64, fallback: f64) -> f64 {
    if value.is_finite() {
        value.clamp(minimum, maximum)
    } else {
        fallback
    }
}

fn valid_optional_number(value: Option<f64>, minimum: f64, maximum: f64) -> bool {
    value.is_none_or(|value| value.is_finite() && (minimum..=maximum).contains(&value))
}

fn supported_skin_photo(bytes: &[u8]) -> bool {
    bytes.starts_with(&[0xFF, 0xD8, 0xFF])
        || bytes.starts_with(b"\x89PNG\r\n\x1A\n")
        || bytes.starts_with(b"GIF87a")
        || bytes.starts_with(b"GIF89a")
        || (bytes.len() >= 12 && bytes.starts_with(b"RIFF") && &bytes[8..12] == b"WEBP")
}

/// Stable Apple-compatible entries shown by touch-keyboard scheme pickers.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TouchKeyboardScheme {
    Quanpin,
    NineKey,
    Xiaohe,
    Ziranma,
    Microsoft,
    Shoudao,
    Wubi,
    JapaneseNineKey,
    Japanese,
    Handwriting,
    ThoughtfulReply,
}

impl TouchKeyboardScheme {
    pub const ALL: [Self; 11] = [
        Self::Quanpin,
        Self::NineKey,
        Self::Xiaohe,
        Self::Ziranma,
        Self::Microsoft,
        Self::Shoudao,
        Self::Wubi,
        Self::JapaneseNineKey,
        Self::Japanese,
        Self::Handwriting,
        Self::ThoughtfulReply,
    ];
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TouchKeyboardSchemePreferences {
    #[serde(default = "default_touch_keyboard_schemes")]
    pub enabled: BTreeSet<TouchKeyboardScheme>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub selected: Option<TouchKeyboardScheme>,
}

fn default_touch_keyboard_schemes() -> BTreeSet<TouchKeyboardScheme> {
    TouchKeyboardScheme::ALL.into_iter().collect()
}

impl Default for TouchKeyboardSchemePreferences {
    fn default() -> Self {
        Self {
            enabled: default_touch_keyboard_schemes(),
            selected: None,
        }
    }
}

impl TouchKeyboardSchemePreferences {
    fn is_default(&self) -> bool {
        self == &Self::default()
    }
}

/// Which state a new focus session starts in.
///
/// Chinese, because that is what this input method is for: opening in English means the first thing
/// a new user does is find the switch. The macOS host already resolved anything but an explicit
/// "english" to Chinese on its own, so this is the shared default agreeing with the one host that
/// had already decided.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum DefaultImeMode {
    #[default]
    Chinese,
    English,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum ImeModeScope {
    #[default]
    App,
    Global,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ChineseScheme {
    Quanpin,
    Shuangpin,
    Wubi,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum PunctuationLock {
    #[default]
    Follow,
    Chinese,
    English,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum TranslationTargetLanguage {
    #[default]
    En,
    Fr,
    Ja,
    Es,
    Ru,
    De,
    Ko,
}

/// The character width used by desktop hosts for printable ASCII output.
/// This is separate from `floating_toolbar.fullwidth`, which controls whether
/// the toolbar exposes the width switch.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum CharacterWidthPreference {
    #[default]
    Halfwidth,
    Fullwidth,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Preferences {
    #[serde(default)]
    pub default_ime_mode: DefaultImeMode,
    #[serde(default)]
    pub ime_mode_scope: ImeModeScope,
    #[serde(default)]
    pub voice_input: VoiceInputPreferences,
    #[serde(default)]
    pub ai_assistant: AiAssistantPreferences,
    #[serde(default)]
    pub custom_translation: CustomTranslationPreferences,
    #[serde(default)]
    pub tencent_tmt: TencentTmtPreferences,
    #[serde(default)]
    pub niutrans: NiuTransPreferences,
    #[serde(default)]
    pub floating_toolbar: FloatingToolbarPreferences,
    #[serde(default)]
    pub character_width: CharacterWidthPreference,
    #[serde(default)]
    pub theme: ThemeMode,
    #[serde(default)]
    pub settings_theme: SettingsTheme,
    #[serde(default)]
    pub candidate_theme: SettingsTheme,
    #[serde(default)]
    pub toolbar_theme: SettingsTheme,
    #[serde(default)]
    pub screen_keyboard_theme: SettingsTheme,
    #[serde(default)]
    pub handwriting_theme: SettingsTheme,
    #[serde(default)]
    pub voice_theme: SettingsTheme,
    #[serde(default)]
    pub emoji_theme: SettingsTheme,
    /// The tray and candidate context menus. Windows draws its own, so this is
    /// the one surface override the client was missing.
    #[serde(default)]
    pub menu_theme: SettingsTheme,
    #[serde(default = "default_candidate_skin")]
    pub candidate_skin: String,
    #[serde(default)]
    pub candidate_layout: CandidateLayout,
    #[serde(default)]
    pub candidate_preedit_style: CandidatePreeditStyle,
    #[serde(default)]
    pub tsf_preedit_style: PreeditStyle,
    #[serde(default)]
    pub diagnostic_log: DiagnosticLogPreferences,
    /// Accepted for compatibility, and deliberately not honoured.
    ///
    /// The reference offers Direct2D or WebView2 for the candidate window,
    /// toolbar and tray menu because it carries both renderers. This client
    /// draws those three natively with Direct2D and has no second renderer to
    /// switch to, so no host reads this and no settings page offers it -
    /// a control here would be a choice with one outcome.
    ///
    /// It cannot simply be deleted: `Preferences` denies unknown fields, so
    /// dropping it would make every saved document that contains it fail to
    /// parse.
    #[serde(default)]
    pub ui_backend: UiBackend,
    #[serde(default = "enabled_by_default")]
    pub candidate_follow_cursor: bool,
    /// macOS displays a short, non-activating badge after switching between
    /// Chinese and English input. Other hosts preserve this preference but do
    /// not render the native badge.
    #[serde(default = "enabled_by_default")]
    pub input_mode_hud: bool,
    pub scheme: InputScheme,
    /// Show the Wubi code suffix that remains after the typed prefix.
    /// `None` preserves the default-on behavior without rewriting legacy documents.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub wubi_code_hint: Option<bool>,
    /// Answer an unmatched Wubi code with candidates from the same Pinyin spelling.
    #[serde(default)]
    pub wubi_mixed_pinyin: bool,
    #[serde(default)]
    pub touch_keyboard_layout: TouchKeyboardLayout,
    /// Touch-only keyboard appearance. Candidate-window skins remain independent.
    #[serde(default)]
    pub touch_keyboard_skin: TouchKeyboardSkin,
    #[serde(default)]
    pub custom_touch_keyboard_skin: TouchKeyboardSkinDesign,
    /// Touch-only picker visibility and optional host selection. Desktop hosts preserve but ignore it.
    #[serde(
        default,
        skip_serializing_if = "TouchKeyboardSchemePreferences::is_default"
    )]
    pub touch_keyboard_schemes: TouchKeyboardSchemePreferences,
    /// Horizontal key gap in tenths of a density-independent pixel.
    #[serde(default = "default_touch_key_spacing_tenths")]
    pub touch_key_spacing_tenths: u8,
    /// Vertical row gap in tenths of a density-independent pixel.
    #[serde(default = "default_touch_row_spacing_tenths")]
    pub touch_row_spacing_tenths: u8,
    /// Touch-keyboard height adjustment in density-independent pixels.
    #[serde(default)]
    pub touch_keyboard_height_adjustment: i8,
    /// Show a direct voice-result entry in touch-keyboard toolbars.
    #[serde(default)]
    pub touch_voice_shortcut: bool,
    /// The optional buttons on the touch keyboard's toolbar, the counterpart of the floating toolbar's component switches. The voice entry stays under `touch_voice_shortcut`.
    #[serde(default)]
    pub touch_toolbar: TouchToolbarPreferences,
    /// Retained when the active scheme is Japanese. Absent in legacy documents.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_chinese_scheme: Option<ChineseScheme>,
    #[serde(default)]
    pub shuangpin_profile: ShuangpinProfile,
    #[serde(default = "enabled_by_default")]
    pub shuangpin_preedit_uses_raw: bool,
    pub candidate_page_size: u8,
    /// Linux IBus can release the number row to the application while a
    /// candidate list is visible. Other hosts preserve this preference even
    /// when their native candidate presenter does not expose the switch.
    #[serde(default = "enabled_by_default")]
    pub number_row_selection: bool,
    #[serde(default = "default_candidate_font_size")]
    pub candidate_font_size: u8,
    #[serde(default = "default_candidate_preedit_font_size")]
    pub candidate_preedit_font_size: u8,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub candidate_text_color: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub candidate_number_color: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub candidate_accent_color: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub candidate_selected_color: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub candidate_hover_color: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub candidate_surface_color: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub candidate_border_color: Option<String>,
    #[serde(default = "default_candidate_font_family")]
    pub candidate_font_family: String,
    /// Optional leading face for the Windows candidate glyph fallback chain.
    /// The host supplies its default; absent values preserve other hosts.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub candidate_english_font: Option<String>,
    #[serde(default = "default_candidate_fallback_fonts")]
    pub candidate_fallback_fonts: Vec<String>,
    pub learning: bool,
    #[serde(default = "enabled_by_default")]
    /// Legacy all-types switch retained so older snapshots still parse. It no
    /// longer enables either correction type; callers use the two `quanpin`
    /// fields, matching the fixed Windows baseline.
    pub autocorrect: bool,
    #[serde(default, skip_serializing_if = "QuanpinPreferences::is_empty")]
    pub quanpin: QuanpinPreferences,
    #[serde(default)]
    pub fuzzy_pinyin: FuzzyPinyinPreferences,
    #[serde(default = "default_quanpin_helpcode")]
    pub quanpin_helpcode: HelpcodePreferences,
    #[serde(default = "default_shuangpin_helpcode")]
    pub shuangpin_helpcode: HelpcodePreferences,
    /// Render and commit Chinese Engine output in Traditional Chinese at the host boundary.
    #[serde(default)]
    pub traditional_chinese_output: bool,
    pub chinese_punctuation: bool,
    #[serde(default = "smart_punctuation_default")]
    pub smart_punctuation: bool,
    #[serde(default = "smart_punctuation_default")]
    pub smart_punctuation_repeat: bool,
    /// Space after a just-committed Chinese punctuation rewrites it as ASCII. Off by default on every host, like the rest of the family in the source: it changes a character the user already saw land.
    #[serde(default)]
    pub smart_punctuation_space_convert: bool,
    /// Keep `,` `.` `:` as ASCII when they follow a digit.
    #[serde(default = "smart_punctuation_default")]
    pub smart_punctuation_direct_digit: bool,
    /// The same after a letter. Two switches rather than one, because a
    /// version number and an English sentence want different answers.
    ///
    /// Both follow the parent switch's default rather than being off on their
    /// own. The reference has one switch here, and its description - which this
    /// page shows verbatim - promises ASCII after a letter or a digit. Split
    /// into three and with the two halves off, that switch was on out of the
    /// box and did nothing: the sentence under it was false until the user
    /// found two more toggles. A document that already carries the keys is
    /// unaffected, since this answers only for one that does not.
    #[serde(default = "smart_punctuation_default")]
    pub smart_punctuation_direct_letter: bool,
    #[serde(default = "enabled_by_default")]
    pub paired_punctuation: bool,
    #[serde(default)]
    pub punctuation_lock: PunctuationLock,
    #[serde(default)]
    pub navigation: NavigationPreferences,
    #[serde(default)]
    pub keybindings: KeybindingPreferences,
    #[serde(default)]
    pub word_character: WordCharacterPreferences,
    #[serde(default)]
    pub frequency: FrequencyPreferences,
    #[serde(default)]
    pub mixed_input: MixedInputPreferences,
    #[serde(default)]
    pub local_modes: LocalModePreferences,
    #[serde(default)]
    pub clipboard_history: bool,
    /// Fetch one additional candidate from the configured cloud provider.
    #[serde(default = "enabled_by_default")]
    pub cloud_candidates: bool,
    #[serde(default = "enabled_by_default")]
    pub candidate_translations: bool,
    /// Show bounded offline English glosses from the packaged Engine dictionary.
    #[serde(default)]
    pub candidate_english_gloss: bool,
    /// Show read-only English word completions in direct English touch input.
    /// Hosts without a direct English suggestion surface preserve this value.
    #[serde(default = "enabled_by_default")]
    pub english_suggestions: bool,
    #[serde(default)]
    pub translation_target_language: TranslationTargetLanguage,
    /// Optional second language for mobile candidate glosses. `None` preserves the
    /// legacy single-language behavior and is omitted from serialized snapshots.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub translation_secondary_language: Option<TranslationTargetLanguage>,
    /// True only when the user explicitly picks the MSIME account (水杉账号) as the candidate translation service in settings; candidates are then sent to `https://api.msime.app/v1/translate`. Omitted while false so documents that never chose it stay readable by older strict parsers.
    #[serde(default, skip_serializing_if = "is_false")]
    pub translation_account: bool,
    /// Send the anonymous start and crash events to `https://api.msime.app/v1/telemetry/events`. Off until the user turns it on. Only the Windows Server reads it so far; the other hosts keep their own telemetry behaviour, described in PRIVACY.md.
    #[serde(default)]
    pub telemetry_enabled: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct VoiceInputPreferences {
    #[serde(default = "enabled_by_default")]
    pub enabled: bool,
    #[serde(default = "enabled_by_default")]
    pub sound_enabled: bool,
    #[serde(default = "enabled_by_default")]
    pub start_sound: bool,
    #[serde(default = "enabled_by_default")]
    pub end_sound: bool,
    #[serde(default = "source_voice_default")]
    pub mute_system_audio: bool,
    #[serde(default)]
    pub language: String,
    /// Empty values inherit the user-managed Linux recording service defaults.
    #[serde(default)]
    pub capture_backend: String,
    #[serde(default)]
    pub capture_device: String,
    #[serde(default = "default_commit_mode")]
    pub commit_mode: String,
    #[serde(default)]
    pub asr_provider: String,
    #[serde(default)]
    pub asr_app_key: String,
    /// Doubao authentication mode (`api_key` or `legacy`). Empty preserves
    /// compatibility with older files and lets each host infer the mode from
    /// the stored App ID.
    #[serde(default)]
    pub doubao_auth_mode: String,
    #[serde(default)]
    pub asr_token: String,
    /// One recognition token per provider id.
    ///
    /// A single flat token meant switching provider left the previous
    /// provider's key in the box, so it was sent to the new endpoint until the
    /// user noticed, and the old key was gone the moment they retyped.
    #[serde(default)]
    pub asr_tokens: BTreeMap<String, String>,
    #[serde(default)]
    pub asr_endpoint: String,
    #[serde(default)]
    pub asr_model: String,
    /// Absolute path to a local Whisper model file. Only the `local` provider
    /// reads it; nothing is uploaded and no endpoint or token applies.
    #[serde(default)]
    pub asr_model_path: String,
    #[serde(default)]
    pub asr_resource_id: String,
    #[serde(default)]
    pub polish_enabled: bool,
    #[serde(default = "source_voice_default")]
    pub polish_text: bool,
    #[serde(default)]
    pub polish_provider: String,
    #[serde(default)]
    pub polish_token: String,
    /// One polish token per provider id, for the same reason as `asr_tokens`.
    #[serde(default)]
    pub polish_tokens: BTreeMap<String, String>,
    #[serde(default)]
    pub polish_endpoint: String,
    #[serde(default)]
    pub polish_model: String,
    #[serde(default)]
    pub polish_prompt_id: String,
    #[serde(default)]
    pub polish_prompt: String,
    /// Show streaming ASR updates in the host preedit while recording.
    #[serde(default = "enabled_by_default")]
    pub stream_inline_preedit: bool,
    #[serde(default)]
    pub polish_prompt_custom_1: String,
    #[serde(default)]
    pub polish_prompt_custom_2: String,
    #[serde(default)]
    pub polish_prompt_custom_3: String,
    #[serde(default = "enabled_by_default")]
    pub hotkey_ralt: bool,
    #[serde(default)]
    pub hotkey_ctrl_win: bool,
    #[serde(default)]
    pub hotkey_rctrl_ralt: bool,
    #[serde(default = "enabled_by_default")]
    pub hotkey_hold_space_lock: bool,
    #[serde(default = "enabled_by_default")]
    pub hotkey_ctrl_f9: bool,
    #[serde(default = "enabled_by_default")]
    pub doubao_enable_itn: bool,
    #[serde(default = "enabled_by_default")]
    pub doubao_enable_punc: bool,
    #[serde(default = "source_voice_default")]
    pub doubao_enable_ddc: bool,
    #[serde(default)]
    pub doubao_boosting_table_id: String,
}

impl Default for VoiceInputPreferences {
    fn default() -> Self {
        let polish = default_polish_service();
        Self {
            enabled: true,
            sound_enabled: true,
            start_sound: true,
            end_sound: true,
            mute_system_audio: source_voice_default(),
            language: "zh-cn".into(),
            capture_backend: String::new(),
            capture_device: String::new(),
            commit_mode: "tsf".into(),
            asr_provider: "doubao".into(),
            asr_app_key: String::new(),
            doubao_auth_mode: "api_key".into(),
            asr_token: String::new(),
            asr_tokens: BTreeMap::new(),
            asr_endpoint: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async".into(),
            asr_model: String::new(),
            asr_model_path: String::new(),
            asr_resource_id: "volc.seedasr.sauc.duration".into(),
            polish_enabled: false,
            polish_text: source_voice_default(),
            polish_provider: polish.provider.into(),
            polish_token: String::new(),
            polish_tokens: BTreeMap::new(),
            polish_endpoint: polish.endpoint.into(),
            polish_model: polish.model.into(),
            polish_prompt_id: "cleanup".into(),
            polish_prompt: String::new(),
            stream_inline_preedit: true,
            polish_prompt_custom_1: String::new(),
            polish_prompt_custom_2: String::new(),
            polish_prompt_custom_3: String::new(),
            hotkey_ralt: true,
            hotkey_ctrl_win: false,
            hotkey_rctrl_ralt: false,
            hotkey_hold_space_lock: true,
            hotkey_ctrl_f9: true,
            doubao_enable_itn: true,
            doubao_enable_punc: true,
            doubao_enable_ddc: source_voice_default(),
            doubao_boosting_table_id: String::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AiAssistantPreferences {
    #[serde(default = "source_ai_default")]
    pub enabled: bool,
    #[serde(default)]
    pub provider: String,
    #[serde(default)]
    pub model: String,
    #[serde(default)]
    pub token: String,
    #[serde(default)]
    pub tokens: BTreeMap<String, String>,
    #[serde(default)]
    pub endpoint: String,
    #[serde(default = "default_ai_candidate_limit")]
    pub candidate_limit: u8,
    #[serde(default)]
    pub prompt_id: String,
    #[serde(default)]
    pub prompt: String,
    #[serde(default)]
    pub prompt_custom_1: String,
    #[serde(default)]
    pub prompt_custom_2: String,
    #[serde(default)]
    pub prompt_custom_3: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct CustomTranslationPreferences {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub endpoint: String,
    #[serde(default)]
    pub api_key: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct TencentTmtPreferences {
    pub enabled: bool,
    pub secret_id: String,
    pub secret_key: String,
    pub region: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(default)]
pub struct NiuTransPreferences {
    pub enabled: bool,
    pub app_id: String,
    pub apikey: String,
}

impl Default for TencentTmtPreferences {
    fn default() -> Self {
        Self {
            enabled: true,
            secret_id: String::new(),
            secret_key: String::new(),
            region: "ap-guangzhou".into(),
        }
    }
}

fn default_ai_candidate_limit() -> u8 {
    3
}

impl Default for AiAssistantPreferences {
    fn default() -> Self {
        let (endpoint, model) = if source_ai_default() {
            (SOURCE_DEEPSEEK_ENDPOINT, SOURCE_DEEPSEEK_MODEL)
        } else {
            ("", "")
        };
        Self {
            enabled: source_ai_default(),
            provider: "deepseek".into(),
            model: model.into(),
            token: String::new(),
            tokens: BTreeMap::new(),
            endpoint: endpoint.into(),
            candidate_limit: 3,
            prompt_id: "custom_1".into(),
            prompt: String::new(),
            prompt_custom_1: String::new(),
            prompt_custom_2: String::new(),
            prompt_custom_3: String::new(),
        }
    }
}

/// Diagnostic logging, off unless a user turns it on while reproducing a
/// problem. The two hosts log separately because they are separate processes.
/// Neither records keystrokes, input text or candidates.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct DiagnosticLogPreferences {
    /// Server-side timing and window state: slow request stages, candidate
    /// window, floating toolbar, menus, focus sessions and transport status.
    pub server: bool,
    /// In-process TSF preedit and input latency, buffered and batched out.
    pub tsf: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FloatingToolbarPreferences {
    #[serde(default = "enabled_by_default")]
    pub enabled: bool,
    #[serde(default = "enabled_by_default")]
    pub english_mode: bool,
    #[serde(default = "default_toolbar_scale")]
    pub scale_percent: u16,
    #[serde(default = "default_toolbar_font_size")]
    pub font_size: u16,
    #[serde(default = "enabled_by_default")]
    pub fullwidth: bool,
    #[serde(default = "enabled_by_default")]
    pub punctuation: bool,
    #[serde(default = "enabled_by_default")]
    pub character_set: bool,
    #[serde(default = "enabled_by_default")]
    pub emoji: bool,
    /// The handwriting panel button. The reference's toolbar has no such button; this client's
    /// macOS toolbar carries one, and until now it could not be turned off.
    #[serde(default = "enabled_by_default")]
    pub handwriting: bool,
    #[serde(default)]
    pub screen_keyboard: bool,
    /// The voice input button, for the same reason as `handwriting`.
    #[serde(default = "enabled_by_default")]
    pub voice: bool,
    #[serde(default = "enabled_by_default")]
    pub settings: bool,
}

fn default_toolbar_scale() -> u16 {
    100
}
fn default_toolbar_font_size() -> u16 {
    24
}

/// Which optional buttons the touch keyboard's toolbar carries. The first three are the buttons the bar always had; the rest are tools that otherwise sit one tap deeper, in the keyboard's 更多 panel.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct TouchToolbarPreferences {
    pub layout: bool,
    pub emoji: bool,
    pub skin: bool,
    pub clipboard: bool,
    pub ai: bool,
    pub character_set: bool,
    pub fullwidth: bool,
    pub punctuation: bool,
}

impl Default for TouchToolbarPreferences {
    fn default() -> Self {
        Self {
            layout: true,
            emoji: true,
            skin: true,
            clipboard: false,
            ai: false,
            character_set: false,
            fullwidth: false,
            punctuation: false,
        }
    }
}

impl Default for FloatingToolbarPreferences {
    fn default() -> Self {
        Self {
            enabled: true,
            english_mode: true,
            scale_percent: 100,
            font_size: 24,
            fullwidth: true,
            punctuation: true,
            character_set: true,
            emoji: true,
            handwriting: true,
            screen_keyboard: false,
            voice: true,
            settings: true,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum ThemeMode {
    Dark,
    Light,
    #[default]
    System,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum SettingsTheme {
    #[default]
    Follow,
    Dark,
    Light,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum CandidateLayout {
    Horizontal,
    #[default]
    Vertical,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum CandidatePreeditStyle {
    #[default]
    Pinyin,
    Empty,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum PreeditStyle {
    #[default]
    Raw,
    Pinyin,
    Empty,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum UiBackend {
    /// `d2d` is what the Windows factory configuration writes and what the reference's own
    /// `IsSupported` accepts, so the two halves of this product disagreed on the spelling of their
    /// default: a document carrying it was rejected outright rather than read.
    #[default]
    #[serde(alias = "d2d")]
    Direct2d,
    /// The reference treats `webview` and `web` as the same choice, having written both at
    /// different times. Reading them costs nothing and keeps a profile from resetting.
    #[serde(alias = "webview", alias = "web")]
    Webview2,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct LocalModePreferences {
    pub unicode: bool,
    pub date_time: bool,
    pub quick_phrase: bool,
    pub emoji: bool,
    pub kaomoji: bool,
    pub super_jianpin: bool,
    pub temporary_english: bool,
    pub temporary_japanese: bool,
}

impl Default for LocalModePreferences {
    fn default() -> Self {
        Self {
            unicode: true,
            date_time: true,
            quick_phrase: true,
            emoji: true,
            kaomoji: true,
            super_jianpin: true,
            temporary_english: true,
            temporary_japanese: true,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MixedInputPreferences {
    pub english: bool,
    pub minimum_prefix: u8,
    pub emoji: bool,
    pub kaomoji: bool,
}

impl Default for MixedInputPreferences {
    fn default() -> Self {
        Self {
            english: true,
            minimum_prefix: 5,
            emoji: source_mixed_emoji_default(),
            kaomoji: false,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum FrequencyMode {
    Disabled,
    Pin,
    Halve,
    Linear,
    #[default]
    Promote,
}

impl FrequencyMode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Disabled => "disabled",
            Self::Pin => "pin",
            Self::Halve => "halve",
            Self::Linear => "linear",
            Self::Promote => "promote",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FrequencyPreferences {
    pub mode: FrequencyMode,
    pub trigger_count: u8,
    pub linear_step: u8,
}

impl Default for FrequencyPreferences {
    fn default() -> Self {
        Self {
            mode: FrequencyMode::Promote,
            trigger_count: 1,
            linear_step: 1,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum WordCharacterKeys {
    #[default]
    Brackets,
    MinusEqual,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WordCharacterPreferences {
    pub enabled: bool,
    pub keys: WordCharacterKeys,
}

impl Default for WordCharacterPreferences {
    fn default() -> Self {
        Self {
            enabled: true,
            keys: WordCharacterKeys::Brackets,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct NavigationPreferences {
    pub minus_equal: bool,
    pub comma_period: bool,
    pub brackets: bool,
    pub tab: bool,
    pub page_up_down: bool,
    #[serde(default, skip_serializing_if = "is_false")]
    pub mouse_wheel: bool,
    #[serde(alias = "candidate_arrow_navigation")]
    pub arrows: bool,
}

impl Default for NavigationPreferences {
    fn default() -> Self {
        Self {
            minus_equal: true,
            comma_period: true,
            brackets: false,
            tab: true,
            page_up_down: true,
            mouse_wheel: false,
            arrows: true,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct KeybindingPreferences {
    #[serde(default = "enabled_by_default")]
    pub switch_language_shift: bool,
    #[serde(default)]
    pub switch_language_ctrl: bool,
    #[serde(default = "enabled_by_default")]
    pub switch_language_ctrl_alt_space: bool,
    #[serde(default = "enabled_by_default")]
    pub toggle_character_set_ctrl_shift_f: bool,
    /// The macOS Option+Shift+H chord. The host has reserved it unconditionally since it shipped,
    /// so this defaults on: the preference gives the chord back to the application, it does not
    /// turn on something that was off. Other hosts have no such chord and ignore it.
    #[serde(default = "enabled_by_default")]
    pub toggle_fullwidth_option_shift_h: bool,
}

impl Default for KeybindingPreferences {
    fn default() -> Self {
        Self {
            switch_language_shift: true,
            switch_language_ctrl: false,
            switch_language_ctrl_alt_space: true,
            toggle_character_set_ctrl_shift_f: true,
            toggle_fullwidth_option_shift_h: true,
        }
    }
}

fn enabled_by_default() -> bool {
    true
}

/// Smart punctuation is off on a fresh Windows or macOS profile.
///
/// It rewrites a character the user already saw land, so the source ships the whole family disabled and asks for it to be turned on deliberately - `platforms/windows/installer/config.default.toml` has every one of the five switches `false`. That file is only the installed template; the running host reads this document, so without this the effective first-run default would be the opposite of the baseline the source ships. macOS is the port of that desktop product and follows it.
///
/// Linux, Android, iOS and HarmonyOS keep what they have shipped, since a preference that changes under existing users is worse than one that differs by platform. A stored value is never reinterpreted either way; this answers only for a document that does not have the key yet.
fn smart_punctuation_default() -> bool {
    !cfg!(any(windows, target_os = "macos"))
}

/// Three voice switches the source ships on and the shared document had off: muting other audio while recording, Doubao's semantic smoothing (DDC), and polishing the recognized text.
///
/// `platforms/windows/installer/config.default.toml` has all three `true`, matching the source's factory configuration, but like smart punctuation that file is only the installed template - the running host reads this document - so the effective first-run value on Windows was `false`. macOS is the port of that desktop product and follows it. None of the three depends on the platform: muting uses CoreAudio on macOS, DDC is a Doubao request flag, and polishing still needs a polish token before anything is sent.
///
/// The other hosts keep what they have shipped. A stored value is untouched either way; this answers only for a document that does not have the key yet.
fn source_voice_default() -> bool {
    cfg!(any(windows, target_os = "macos"))
}

/// The source's factory template turns the AI assistant on and points it at DeepSeek (`deepseek-v4-flash`); `platforms/windows/installer/config.default.toml` ships the same, but the running host reads this document, so the effective first-run value on Windows was off with no endpoint or model. macOS follows the desktop product it ports. Being on without a token sends nothing: `chat_completion_http_request` refuses to build a request until a usable key is set.
///
/// The other hosts keep the assistant off with an empty endpoint and model. A stored value is untouched either way; this answers only for a document that does not have the key yet.
fn source_ai_default() -> bool {
    cfg!(any(windows, target_os = "macos"))
}

const SOURCE_DEEPSEEK_ENDPOINT: &str = "https://api.deepseek.com/chat/completions";
const SOURCE_DEEPSEEK_MODEL: &str = "deepseek-v4-flash";

/// A polish provider with the endpoint and model that belong to it, kept together so a default never pairs one provider's URL with another's model.
struct PolishService {
    provider: &'static str,
    endpoint: &'static str,
    model: &'static str,
}

/// First-run polish service. The source template and the Windows installer template both ship DeepSeek (`deepseek-v4-flash`), and macOS follows the desktop product it ports; the other hosts keep SiliconFlow with `Qwen/Qwen3-8B`, which is what they have shipped. Stored values are never reinterpreted.
fn default_polish_service() -> PolishService {
    if source_voice_default() {
        PolishService {
            provider: "deepseek",
            endpoint: SOURCE_DEEPSEEK_ENDPOINT,
            model: SOURCE_DEEPSEEK_MODEL,
        }
    } else {
        PolishService {
            provider: "siliconflow",
            endpoint: "https://api.siliconflow.cn/v1/chat/completions",
            model: "Qwen/Qwen3-8B",
        }
    }
}

/// The source's `config.default.toml` ships `emoji_mixed_input = true`; Windows already receives it through the installer's config.toml and the one-time legacy import, macOS follows the desktop product it ports, the other hosts keep `false`, and a stored value is untouched either way.
fn source_mixed_emoji_default() -> bool {
    cfg!(any(windows, target_os = "macos"))
}

fn default_candidate_font_size() -> u8 {
    18
}

fn default_candidate_preedit_font_size() -> u8 {
    15
}

fn default_touch_key_spacing_tenths() -> u8 {
    60
}

fn default_touch_row_spacing_tenths() -> u8 {
    70
}

fn default_candidate_skin() -> String {
    crate::skin::catalog::DEFAULT_SKIN.to_owned()
}
fn default_candidate_font_family() -> String {
    "Noto Sans SC".to_owned()
}
fn default_candidate_fallback_fonts() -> Vec<String> {
    vec!["Noto Sans SC".to_owned(), "Microsoft YaHei".to_owned()]
}

fn default_commit_mode() -> String {
    "tsf".to_owned()
}

impl Default for Preferences {
    fn default() -> Self {
        Self {
            default_ime_mode: DefaultImeMode::default(),
            ime_mode_scope: ImeModeScope::default(),
            ai_assistant: AiAssistantPreferences::default(),
            custom_translation: CustomTranslationPreferences::default(),
            tencent_tmt: TencentTmtPreferences::default(),
            niutrans: NiuTransPreferences::default(),
            voice_input: VoiceInputPreferences::default(),
            floating_toolbar: FloatingToolbarPreferences::default(),
            character_width: CharacterWidthPreference::default(),
            theme: ThemeMode::default(),
            settings_theme: SettingsTheme::default(),
            candidate_theme: SettingsTheme::default(),
            toolbar_theme: SettingsTheme::default(),
            screen_keyboard_theme: SettingsTheme::default(),
            handwriting_theme: SettingsTheme::default(),
            voice_theme: SettingsTheme::default(),
            emoji_theme: SettingsTheme::default(),
            menu_theme: SettingsTheme::default(),
            candidate_skin: default_candidate_skin(),
            candidate_layout: CandidateLayout::default(),
            candidate_preedit_style: CandidatePreeditStyle::default(),
            tsf_preedit_style: PreeditStyle::default(),
            diagnostic_log: DiagnosticLogPreferences::default(),
            ui_backend: UiBackend::default(),
            candidate_follow_cursor: true,
            input_mode_hud: true,
            scheme: InputScheme::default(),
            wubi_code_hint: None,
            wubi_mixed_pinyin: false,
            touch_keyboard_layout: TouchKeyboardLayout::default(),
            touch_keyboard_skin: TouchKeyboardSkin::default(),
            custom_touch_keyboard_skin: TouchKeyboardSkinDesign::default(),
            touch_keyboard_schemes: TouchKeyboardSchemePreferences::default(),
            touch_key_spacing_tenths: default_touch_key_spacing_tenths(),
            touch_row_spacing_tenths: default_touch_row_spacing_tenths(),
            touch_keyboard_height_adjustment: 0,
            touch_voice_shortcut: false,
            touch_toolbar: TouchToolbarPreferences::default(),
            last_chinese_scheme: None,
            shuangpin_profile: ShuangpinProfile::default(),
            shuangpin_preedit_uses_raw: true,
            candidate_page_size: 6,
            number_row_selection: true,
            candidate_font_size: default_candidate_font_size(),
            candidate_preedit_font_size: default_candidate_preedit_font_size(),
            candidate_text_color: None,
            candidate_number_color: None,
            candidate_accent_color: None,
            candidate_selected_color: None,
            candidate_hover_color: None,
            candidate_surface_color: None,
            candidate_border_color: None,
            candidate_font_family: default_candidate_font_family(),
            candidate_english_font: None,
            candidate_fallback_fonts: default_candidate_fallback_fonts(),
            learning: true,
            autocorrect: true,
            quanpin: QuanpinPreferences::default(),
            fuzzy_pinyin: FuzzyPinyinPreferences::default(),
            quanpin_helpcode: default_quanpin_helpcode(),
            shuangpin_helpcode: default_shuangpin_helpcode(),
            traditional_chinese_output: false,
            chinese_punctuation: true,
            smart_punctuation: smart_punctuation_default(),
            smart_punctuation_repeat: smart_punctuation_default(),
            smart_punctuation_space_convert: false,
            smart_punctuation_direct_digit: smart_punctuation_default(),
            smart_punctuation_direct_letter: smart_punctuation_default(),
            paired_punctuation: true,
            punctuation_lock: PunctuationLock::Follow,
            navigation: NavigationPreferences::default(),
            keybindings: KeybindingPreferences::default(),
            word_character: WordCharacterPreferences::default(),
            frequency: FrequencyPreferences::default(),
            mixed_input: MixedInputPreferences::default(),
            local_modes: LocalModePreferences::default(),
            clipboard_history: false,
            cloud_candidates: true,
            candidate_translations: true,
            candidate_english_gloss: false,
            english_suggestions: true,
            translation_target_language: TranslationTargetLanguage::default(),
            translation_secondary_language: None,
            translation_account: false,
            telemetry_enabled: false,
        }
    }
}

/// Stable fuzzy-pinyin rule identifiers and bit assignments shared with the Engine and Apple host.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum FuzzyPinyinRule {
    #[serde(rename = "z-zh")]
    ZZh,
    #[serde(rename = "c-ch")]
    CCh,
    #[serde(rename = "s-sh")]
    SSh,
    #[serde(rename = "n-l")]
    NL,
    #[serde(rename = "f-h")]
    FH,
    #[serde(rename = "r-l")]
    RL,
    #[serde(rename = "an-ang")]
    AnAng,
    #[serde(rename = "en-eng")]
    EnEng,
    #[serde(rename = "in-ing")]
    InIng,
    #[serde(rename = "ian-iang")]
    IanIang,
    #[serde(rename = "uan-uang")]
    UanUang,
}

impl FuzzyPinyinRule {
    fn mask(self) -> u32 {
        match self {
            Self::ZZh => 1 << 0,
            Self::CCh => 1 << 1,
            Self::SSh => 1 << 2,
            Self::NL => 1 << 3,
            Self::FH => 1 << 4,
            Self::RL => 1 << 5,
            Self::AnAng => 1 << 6,
            Self::EnEng => 1 << 7,
            Self::InIng => 1 << 8,
            Self::IanIang => 1 << 9,
            Self::UanUang => 1 << 10,
        }
    }
}

fn is_false(value: &bool) -> bool {
    !*value
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(deny_unknown_fields)]
pub struct FuzzyPinyinPreferences {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub rules: BTreeSet<FuzzyPinyinRule>,
    /// Internal marker used to distinguish first enable from an intentionally
    /// empty rule selection. It is persisted but never rendered by the UI.
    #[serde(default, skip_serializing_if = "is_false")]
    pub seeded: bool,
}

impl FuzzyPinyinPreferences {
    /// Disabled fuzzy pinyin preserves the selected rules while presenting exact matching to Engine.
    pub fn active_rules(&self) -> u32 {
        if !self.enabled {
            return 0;
        }
        self.rules.iter().fold(0, |mask, rule| mask | rule.mask())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(deny_unknown_fields)]
pub struct QuanpinPreferences {
    /// Optional keeps legacy snapshots distinguishable from an explicit value.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub autocorrect_transposition: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub autocorrect_neighbor: Option<bool>,
}

impl QuanpinPreferences {
    fn is_empty(&self) -> bool {
        self.autocorrect_transposition.is_none() && self.autocorrect_neighbor.is_none()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum ShuangpinProfile {
    #[default]
    Xiaohe,
    Ziranma,
    Shoudao,
    Microsoft,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum HelpcodeSchema {
    Lantian,
    #[default]
    Ziranma,
    #[serde(rename = "shouyou2_0")]
    Shouyou2,
    Shouyouplus,
    Xiaohe,
    Jiajia,
}

impl HelpcodeSchema {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Lantian => "lantian",
            Self::Ziranma => "ziranma",
            Self::Shouyou2 => "shouyou2_0",
            Self::Shouyouplus => "shouyouplus",
            Self::Xiaohe => "xiaohe",
            Self::Jiajia => "jiajia",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct HelpcodePreferences {
    #[serde(default = "enabled_by_default")]
    pub enabled: bool,
    pub schema: HelpcodeSchema,
    #[serde(default = "enabled_by_default")]
    pub show_in_candidate_window: bool,
}

impl Default for HelpcodePreferences {
    fn default() -> Self {
        Self {
            enabled: true,
            schema: HelpcodeSchema::default(),
            show_in_candidate_window: true,
        }
    }
}

fn default_quanpin_helpcode() -> HelpcodePreferences {
    HelpcodePreferences {
        enabled: true,
        schema: HelpcodeSchema::Ziranma,
        show_in_candidate_window: false,
    }
}

fn default_shuangpin_helpcode() -> HelpcodePreferences {
    HelpcodePreferences {
        enabled: true,
        schema: HelpcodeSchema::Lantian,
        show_in_candidate_window: true,
    }
}

/// Persisted recognition provider identifiers. Hosts expose only the providers
/// they implement: `system` is the macOS Speech adapter, not a cloud profile,
/// and `local` is on-device Whisper, which needs `asr_model_path` and a host
/// built with the recognizer behind it.
pub const ASR_PROVIDERS: [&str; 8] = [
    "doubao",
    "siliconflow",
    "openai",
    "groq",
    "everyapi",
    "mistral",
    "system",
    "local",
];
/// OpenAI-compatible AI services exposed by the Apple settings surface and
/// shared by every host. Providers that need special request fields are still
/// handled in `ai.rs`; the rest use the common Chat Completions shape.
pub const AI_PROVIDERS: [&str; 12] = [
    "everyapi",
    "openai",
    "anthropic",
    "gemini",
    "deepseek",
    "qwen",
    "kimi",
    "zhipu",
    "siliconflow",
    "groq",
    "openrouter",
    "custom",
];
/// Polishing additionally supports DeepSeek, which offers no recognition.
pub const POLISH_PROVIDERS: [&str; 5] = ["siliconflow", "openai", "deepseek", "groq", "doubao"];

impl Preferences {
    pub fn wubi_code_hint_enabled(&self) -> bool {
        self.wubi_code_hint.unwrap_or(true)
    }

    pub fn quanpin_autocorrect_transposition(&self) -> bool {
        self.quanpin.autocorrect_transposition.unwrap_or(false)
    }

    pub fn quanpin_autocorrect_neighbor(&self) -> bool {
        self.quanpin.autocorrect_neighbor.unwrap_or(false)
    }

    pub fn active_helpcode(&self) -> HelpcodePreferences {
        match self.scheme {
            InputScheme::Shuangpin => self.shuangpin_helpcode,
            InputScheme::Quanpin => self.quanpin_helpcode,
            _ => HelpcodePreferences {
                enabled: false,
                ..HelpcodePreferences::default()
            },
        }
    }

    /// Replace recognition and polishing provider ids no backend implements with
    /// the shared defaults. Used on the read path only: a file written by an
    /// older build must still load, and it is never rewritten as a side effect.
    pub fn normalize_voice_providers(&mut self) {
        let default = Self::default();
        if !ASR_PROVIDERS.contains(&self.voice_input.asr_provider.as_str()) {
            self.voice_input.asr_provider = default.voice_input.asr_provider;
        }
        if !POLISH_PROVIDERS.contains(&self.voice_input.polish_provider.as_str()) {
            self.voice_input.polish_provider = default.voice_input.polish_provider;
        }
    }

    /// Every setting back to its default, except what the user cannot simply retype.
    ///
    /// The source window's 恢复默认设置 clears a fixed list of preference keys, and that list does
    /// not name the translation or voice services at all -- over there their credentials live
    /// outside this document, so a reset there never costs a secret. Here they live in it, so the
    /// same promise has to be kept from the other direction: start at `Default` and carry the
    /// service configuration across.
    ///
    /// The endpoint, provider and model travel with the token rather than resetting beside it. A
    /// key left pointing at a default endpoint is worse than either keeping the pair or clearing
    /// it, because nothing on the page says the two no longer belong together. `asr_model_path`
    /// travels for the same reason: it is a file the user went and found.
    ///
    /// `fuzzy_pinyin.seeded` is not a setting at all -- it records that the one-time seeding has
    /// happened -- so clearing it would silently re-seed rules the user had turned off.
    pub fn restored_to_defaults(&self) -> Self {
        let mut next = Self::default();

        next.voice_input.asr_provider = self.voice_input.asr_provider.clone();
        next.voice_input.asr_app_key = self.voice_input.asr_app_key.clone();
        next.voice_input.asr_token = self.voice_input.asr_token.clone();
        next.voice_input.asr_tokens = self.voice_input.asr_tokens.clone();
        next.voice_input.asr_endpoint = self.voice_input.asr_endpoint.clone();
        next.voice_input.asr_model = self.voice_input.asr_model.clone();
        next.voice_input.asr_model_path = self.voice_input.asr_model_path.clone();
        next.voice_input.asr_resource_id = self.voice_input.asr_resource_id.clone();
        next.voice_input.doubao_auth_mode = self.voice_input.doubao_auth_mode.clone();
        next.voice_input.polish_provider = self.voice_input.polish_provider.clone();
        next.voice_input.polish_token = self.voice_input.polish_token.clone();
        next.voice_input.polish_tokens = self.voice_input.polish_tokens.clone();
        next.voice_input.polish_endpoint = self.voice_input.polish_endpoint.clone();
        next.voice_input.polish_model = self.voice_input.polish_model.clone();

        next.ai_assistant.provider = self.ai_assistant.provider.clone();
        next.ai_assistant.model = self.ai_assistant.model.clone();
        next.ai_assistant.token = self.ai_assistant.token.clone();
        next.ai_assistant.tokens = self.ai_assistant.tokens.clone();
        next.ai_assistant.endpoint = self.ai_assistant.endpoint.clone();

        next.custom_translation.endpoint = self.custom_translation.endpoint.clone();
        next.custom_translation.api_key = self.custom_translation.api_key.clone();

        next.tencent_tmt.secret_id = self.tencent_tmt.secret_id.clone();
        next.tencent_tmt.secret_key = self.tencent_tmt.secret_key.clone();
        next.tencent_tmt.region = self.tencent_tmt.region.clone();

        next.niutrans.app_id = self.niutrans.app_id.clone();
        next.niutrans.apikey = self.niutrans.apikey.clone();

        next.fuzzy_pinyin.seeded = self.fuzzy_pinyin.seeded;

        next
    }

    pub fn validate(&self) -> Result<(), PreferencesError> {
        let tencent = &self.tencent_tmt;
        if tencent.secret_id.len() > 4096
            || tencent.secret_key.len() > 4096
            || tencent.secret_key.chars().any(char::is_control)
            || !tencent
                .secret_id
                .bytes()
                .all(|ch| ch.is_ascii_alphanumeric() || ch == b'_' || ch == b'-')
            || tencent.region.len() > 64
            || !tencent
                .region
                .bytes()
                .all(|ch| ch.is_ascii_alphanumeric() || ch == b'-')
        {
            return Err(PreferencesError::InvalidTencentTmt);
        }
        let niutrans = &self.niutrans;
        if niutrans.app_id.len() > 4096
            || niutrans.apikey.len() > 4096
            || niutrans.app_id.chars().any(char::is_control)
            || niutrans.apikey.chars().any(char::is_control)
            || (!niutrans.app_id.is_empty()
                && !crate::translation::usable_niutrans_credential(&niutrans.app_id))
            || (!niutrans.apikey.is_empty()
                && !crate::translation::usable_niutrans_credential(&niutrans.apikey))
        {
            return Err(PreferencesError::InvalidNiuTrans);
        }
        let translation = &self.custom_translation;
        if translation.endpoint.len() > 2048
            || translation.api_key.len() > 4096
            || translation.endpoint.chars().any(char::is_control)
            || translation.api_key.chars().any(char::is_control)
            || (!translation.endpoint.is_empty()
                && !crate::translation::is_supported_endpoint(&translation.endpoint))
        {
            return Err(PreferencesError::InvalidCustomTranslation);
        }
        if !(1..=10).contains(&self.ai_assistant.candidate_limit)
            || !AI_PROVIDERS.contains(&self.ai_assistant.provider.as_str())
        {
            return Err(PreferencesError::InvalidAiAssistant);
        }
        let model_path = &self.voice_input.asr_model_path;
        if !ASR_PROVIDERS.contains(&self.voice_input.asr_provider.as_str())
            || !POLISH_PROVIDERS.contains(&self.voice_input.polish_provider.as_str())
            || model_path.len() > 4096
            || model_path.chars().any(char::is_control)
            || (!model_path.is_empty() && !model_path.starts_with('/'))
        {
            return Err(PreferencesError::InvalidVoiceInput);
        }
        if !(50..=200).contains(&self.floating_toolbar.scale_percent)
            || !(12..=48).contains(&self.floating_toolbar.font_size)
        {
            return Err(PreferencesError::InvalidFloatingToolbar);
        }
        if !(1..=8).contains(&self.mixed_input.minimum_prefix) {
            return Err(PreferencesError::InvalidMixedInput);
        }
        if !(1..=10).contains(&self.frequency.trigger_count)
            || !(1..=10).contains(&self.frequency.linear_step)
        {
            return Err(PreferencesError::InvalidFrequency);
        }
        if !(1..=9).contains(&self.candidate_page_size) {
            return Err(PreferencesError::InvalidPageSize);
        }
        if !(30..=60).contains(&self.touch_key_spacing_tenths)
            || !(40..=100).contains(&self.touch_row_spacing_tenths)
            || !(-12..=48).contains(&self.touch_keyboard_height_adjustment)
        {
            return Err(PreferencesError::InvalidTouchKeyboardSpacing);
        }
        if !self.custom_touch_keyboard_skin.validate() {
            return Err(PreferencesError::InvalidTouchKeyboardSkinDesign);
        }
        if self.touch_keyboard_schemes.enabled.is_empty()
            || self
                .touch_keyboard_schemes
                .selected
                .is_some_and(|selected| !self.touch_keyboard_schemes.enabled.contains(&selected))
        {
            return Err(PreferencesError::InvalidTouchKeyboardSchemes);
        }
        if !(12..=32).contains(&self.candidate_font_size) {
            return Err(PreferencesError::InvalidCandidateFontSize);
        }
        if !(12..=32).contains(&self.candidate_preedit_font_size) {
            return Err(PreferencesError::InvalidCandidateFontSize);
        }
        if let Some(color) = &self.candidate_text_color {
            if color.len() != 7
                || color.as_bytes()[0] != b'#'
                || !color[1..].bytes().all(|byte| byte.is_ascii_hexdigit())
            {
                return Err(PreferencesError::InvalidCandidateTextColor);
            }
        }
        if let Some(color) = &self.candidate_number_color {
            if color.len() != 7
                || color.as_bytes()[0] != b'#'
                || !color[1..].bytes().all(|byte| byte.is_ascii_hexdigit())
            {
                return Err(PreferencesError::InvalidCandidateNumberColor);
            }
        }
        if let Some(color) = &self.candidate_accent_color {
            if color.len() != 7
                || color.as_bytes()[0] != b'#'
                || !color[1..].bytes().all(|byte| byte.is_ascii_hexdigit())
            {
                return Err(PreferencesError::InvalidCandidateAccentColor);
            }
        }
        if let Some(color) = &self.candidate_selected_color {
            if color.len() != 7
                || color.as_bytes()[0] != b'#'
                || !color[1..].bytes().all(|byte| byte.is_ascii_hexdigit())
            {
                return Err(PreferencesError::InvalidCandidateSelectedColor);
            }
        }
        if let Some(color) = &self.candidate_hover_color {
            if color.len() != 7
                || color.as_bytes()[0] != b'#'
                || !color[1..].bytes().all(|byte| byte.is_ascii_hexdigit())
            {
                return Err(PreferencesError::InvalidCandidateHoverColor);
            }
        }
        for (color, error) in [
            (
                &self.candidate_surface_color,
                PreferencesError::InvalidCandidateSurfaceColor,
            ),
            (
                &self.candidate_border_color,
                PreferencesError::InvalidCandidateBorderColor,
            ),
        ] {
            if let Some(color) = color {
                if color.len() != 7
                    || color.as_bytes()[0] != b'#'
                    || !color[1..].bytes().all(|byte| byte.is_ascii_hexdigit())
                {
                    return Err(error);
                }
            }
        }
        // Font family names are Unicode display names, not paths or identifiers.
        // Keep the existing UTF-8 byte budget while allowing localized families.
        if self.candidate_font_family.is_empty()
            || self.candidate_font_family.len() > 128
            || self.candidate_font_family.chars().any(char::is_control)
        {
            return Err(PreferencesError::InvalidCandidateFontFamily);
        }
        if self.candidate_english_font.as_ref().is_some_and(|font| {
            font.is_empty() || font.len() > 128 || font.chars().any(char::is_control)
        }) {
            return Err(PreferencesError::InvalidCandidateFontFamily);
        }
        if self.candidate_skin.is_empty()
            || self.candidate_skin.len() > 64
            || !self.candidate_skin.is_ascii()
            || !self.candidate_skin.as_bytes()[0].is_ascii_alphanumeric()
            || !self.candidate_skin.bytes().all(|byte| {
                byte.is_ascii_lowercase()
                    || byte.is_ascii_digit()
                    || byte == b'.'
                    || byte == b'_'
                    || byte == b'-'
            })
        {
            return Err(PreferencesError::InvalidCandidateSkin);
        }
        // Match the 32 ordered supplementary families in Windows appearance.ts.
        if self.candidate_fallback_fonts.len() > 32
            || self.candidate_fallback_fonts.iter().any(|font| {
                font.is_empty() || font.len() > 128 || font.chars().any(char::is_control)
            })
        {
            return Err(PreferencesError::InvalidCandidateFontFamily);
        }
        let paging = match self.word_character.keys {
            WordCharacterKeys::Brackets => self.navigation.brackets,
            WordCharacterKeys::MinusEqual => self.navigation.minus_equal,
        };
        if self.word_character.enabled && paging {
            return Err(PreferencesError::ConflictingKeyBindings);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PreferencesSnapshot {
    pub format_version: u32,
    pub revision: u64,
    pub preferences: Preferences,
}

impl Default for PreferencesSnapshot {
    fn default() -> Self {
        Self {
            format_version: 1,
            revision: 0,
            preferences: Preferences::default(),
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum PreferencesError {
    #[error("floating toolbar settings are invalid")]
    InvalidFloatingToolbar,
    #[error("AI assistant provider or candidate limit is invalid")]
    InvalidAiAssistant,
    #[error("voice recognition or polishing provider is not supported")]
    InvalidVoiceInput,
    #[error("custom translation endpoint or API key is invalid")]
    InvalidCustomTranslation,
    #[error("Tencent translation credentials or region are invalid")]
    InvalidTencentTmt,
    #[error("NiuTrans translation credentials are invalid")]
    InvalidNiuTrans,
    #[error("candidate page size must be between 1 and 9")]
    InvalidPageSize,
    #[error("touch keyboard key spacing must be 3.0-6.0 and row spacing must be 4.0-10.0")]
    InvalidTouchKeyboardSpacing,
    #[error(
        "at least one touch keyboard scheme must be enabled and the selection must be visible"
    )]
    InvalidTouchKeyboardSchemes,
    #[error("custom touch keyboard skin design is invalid")]
    InvalidTouchKeyboardSkinDesign,
    #[error("candidate font size must be between 12 and 32")]
    InvalidCandidateFontSize,
    #[error("candidate text color must be #RRGGBB or omitted")]
    InvalidCandidateTextColor,
    #[error("candidate number color must be #RRGGBB or omitted")]
    InvalidCandidateNumberColor,
    #[error("candidate accent color must be #RRGGBB or omitted")]
    InvalidCandidateAccentColor,
    #[error("candidate selected color must be #RRGGBB or omitted")]
    InvalidCandidateSelectedColor,
    #[error("candidate hover color must be #RRGGBB or omitted")]
    InvalidCandidateHoverColor,
    #[error("candidate surface color must be #RRGGBB or omitted")]
    InvalidCandidateSurfaceColor,
    #[error("candidate border color must be #RRGGBB or omitted")]
    InvalidCandidateBorderColor,
    #[error("candidate font family must be non-empty, contain no control characters, and be at most 128 bytes")]
    InvalidCandidateFontFamily,
    #[error("candidate skin identifier is invalid")]
    InvalidCandidateSkin,
    #[error("word-to-character and paging cannot use the same keys")]
    ConflictingKeyBindings,
    #[error("frequency trigger count and linear step must be between 1 and 10")]
    InvalidFrequency,
    #[error("mixed English minimum prefix must be between 1 and 8")]
    InvalidMixedInput,
    #[error("preferences changed; reload before saving")]
    Conflict,
    #[error("unsupported preferences format")]
    UnsupportedFormat,
    #[error("preferences revision exhausted")]
    RevisionExhausted,
    #[error("preferences storage failed: {0}")]
    Io(#[from] std::io::Error),
    #[error("invalid preferences document: {0}")]
    Json(#[from] serde_json::Error),
}

pub struct PreferencesStore {
    directory: PathBuf,
}

impl PreferencesStore {
    pub fn new(directory: impl Into<PathBuf>) -> Self {
        Self {
            directory: directory.into(),
        }
    }

    fn open_lock(&self) -> Result<File, PreferencesError> {
        fs::create_dir_all(&self.directory)?;
        let lock = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(self.directory.join("preferences.lock"))?;
        Ok(lock)
    }

    fn lock(&self) -> Result<File, PreferencesError> {
        let lock = self.open_lock()?;
        crate::file_lock::exclusive(&lock)?;
        Ok(lock)
    }

    fn path(&self) -> PathBuf {
        self.directory.join("preferences.json")
    }

    fn read_locked(&self) -> Result<PreferencesSnapshot, PreferencesError> {
        let bytes = match fs::read(self.path()) {
            Ok(bytes) => bytes,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                return Ok(PreferencesSnapshot::default())
            }
            Err(error) => return Err(error.into()),
        };
        let mut snapshot: PreferencesSnapshot = serde_json::from_slice(&bytes)?;
        if snapshot.format_version != 1 {
            return Err(PreferencesError::UnsupportedFormat);
        }
        // Older builds offered recognition providers no backend implements. Fall
        // back in memory so those files still load; the file is not rewritten.
        snapshot.preferences.normalize_voice_providers();
        snapshot.preferences.validate()?;
        Ok(snapshot)
    }

    pub fn load(&self) -> Result<PreferencesSnapshot, PreferencesError> {
        let _lock = self.lock()?;
        self.read_locked()
    }

    /// None means the writer lock is busy; retry later without using defaults.
    /// File operations may still block on storage. Validation matches load().
    pub fn try_load(&self) -> Result<Option<PreferencesSnapshot>, PreferencesError> {
        let lock = self.open_lock()?;
        if !crate::file_lock::try_exclusive(&lock)? {
            return Ok(None);
        }
        self.read_locked().map(Some)
    }

    /// Capture under the preferences lock so disabling cannot race a later write.
    /// Lock order is preferences, then clipboard history; never reverse it.
    pub fn capture_clipboard_text(&self, text: String) -> Result<bool, PreferencesError> {
        let _lock = self.lock()?;
        if !self.read_locked()?.preferences.clipboard_history {
            return Ok(false);
        }
        let mut history = crate::clipboard::ClipboardHistoryStore::open(
            self.directory.join("clipboard_history.json"),
        );
        Ok(history.push(text)?)
    }

    /// Clear only while history is still disabled, using the same lock order
    /// as capture so another settings writer cannot re-enable between checks.
    pub fn clear_disabled_clipboard_history(&self) -> Result<(), PreferencesError> {
        let _lock = self.lock()?;
        if !self.read_locked()?.preferences.clipboard_history {
            let mut history = crate::clipboard::ClipboardHistoryStore::open(
                self.directory.join("clipboard_history.json"),
            );
            history.clear()?;
        }
        Ok(())
    }

    /// Compare-and-swap prevents stale settings windows or IME hosts losing updates.
    /// Corrupt or future-format files are never silently replaced with defaults.
    pub fn save(
        &self,
        expected_revision: u64,
        mut preferences: Preferences,
    ) -> Result<PreferencesSnapshot, PreferencesError> {
        let _lock = self.lock()?;
        let current = self.read_locked()?;
        if current.revision != expected_revision {
            return Err(PreferencesError::Conflict);
        }
        // Match the Windows baseline: the first transition from disabled to
        // enabled opts every fuzzy rule in once. The marker is separate from
        // the rule set so intentionally clearing every rule does not reseed
        // on a later disable/enable cycle.
        if preferences.fuzzy_pinyin.enabled
            && !current.preferences.fuzzy_pinyin.enabled
            && !current.preferences.fuzzy_pinyin.seeded
        {
            preferences.fuzzy_pinyin.rules = [
                FuzzyPinyinRule::ZZh,
                FuzzyPinyinRule::CCh,
                FuzzyPinyinRule::SSh,
                FuzzyPinyinRule::NL,
                FuzzyPinyinRule::FH,
                FuzzyPinyinRule::RL,
                FuzzyPinyinRule::AnAng,
                FuzzyPinyinRule::EnEng,
                FuzzyPinyinRule::InIng,
                FuzzyPinyinRule::IanIang,
                FuzzyPinyinRule::UanUang,
            ]
            .into_iter()
            .collect();
            preferences.fuzzy_pinyin.seeded = true;
        } else if current.preferences.fuzzy_pinyin.seeded {
            // Keep the internal marker monotonic even if an older client sends
            // a snapshot that predates the field.
            preferences.fuzzy_pinyin.seeded = true;
        }
        preferences.validate()?;
        let snapshot = PreferencesSnapshot {
            format_version: 1,
            revision: current
                .revision
                .checked_add(1)
                .ok_or(PreferencesError::RevisionExhausted)?,
            preferences,
        };
        atomic_write(
            &self.directory,
            &self.path(),
            &serde_json::to_vec_pretty(&snapshot)?,
        )?;
        Ok(snapshot)
    }
}

fn atomic_write(directory: &Path, path: &Path, contents: &[u8]) -> Result<(), PreferencesError> {
    sweep_stale_temporaries(directory);
    let mut temporary = tempfile::NamedTempFile::new_in(directory)?;
    temporary.write_all(contents)?;
    temporary.as_file().sync_all()?;
    temporary.persist(path).map_err(|error| error.error)?;
    Ok(())
}

/// How long a staged write has to sit before it is considered abandoned. A staged write takes
/// milliseconds; a day is far past anything a slow disk explains.
const STALE_TEMPORARY_AGE: std::time::Duration = std::time::Duration::from_secs(24 * 60 * 60);

/// Remove staged writes nobody is going to finish.
///
/// `NamedTempFile` removes itself when it is dropped, but a process killed between creating the
/// file and renaming it drops nothing - and the input method is stopped exactly that way every time
/// it is reinstalled. The staged file then sits in the user's data directory forever, one per
/// interrupted write, and nothing else ever looks at it. Two were found there on a machine running
/// this client, holding a copy of the preferences and of the typing statistics.
///
/// Only files a day old are touched, and the age is what makes this safe rather than the lock: the
/// statistics document stages its writes into this same directory under a lock of its own, so a
/// sweep that went by name alone could delete a write that was in flight.
fn sweep_stale_temporaries(directory: &Path) {
    let Ok(entries) = std::fs::read_dir(directory) else {
        return;
    };
    let now = std::time::SystemTime::now();
    for entry in entries.flatten() {
        if !entry
            .file_name()
            .to_str()
            .is_some_and(|name| name.starts_with(".tmp"))
        {
            continue;
        }
        let Ok(metadata) = entry.metadata() else {
            continue;
        };
        if !metadata.is_file() {
            continue;
        }
        let abandoned = metadata
            .modified()
            .ok()
            .and_then(|modified| now.duration_since(modified).ok())
            .is_some_and(|age| age >= STALE_TEMPORARY_AGE);
        if abandoned {
            let _ = std::fs::remove_file(entry.path());
        }
    }
}

#[cfg(test)]
mod tests;
