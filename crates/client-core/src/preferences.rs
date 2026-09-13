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
    #[serde(default)]
    pub ui_backend: UiBackend,
    #[serde(default = "enabled_by_default")]
    pub candidate_follow_cursor: bool,
    pub scheme: InputScheme,
    /// Show the Wubi code suffix that remains after the typed prefix.
    /// `None` preserves the default-on behavior without rewriting legacy documents.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub wubi_code_hint: Option<bool>,
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
    /// Retained when the active scheme is Japanese. Absent in legacy documents.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_chinese_scheme: Option<ChineseScheme>,
    #[serde(default)]
    pub shuangpin_profile: ShuangpinProfile,
    #[serde(default = "enabled_by_default")]
    pub shuangpin_preedit_uses_raw: bool,
    pub candidate_page_size: u8,
    #[serde(default = "default_candidate_font_size")]
    pub candidate_font_size: u8,
    #[serde(default = "default_candidate_font_size")]
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
    #[serde(default)]
    pub candidate_fallback_fonts: Vec<String>,
    pub learning: bool,
    #[serde(default = "enabled_by_default")]
    /// Legacy all-types switch retained for older snapshots. New callers should
    /// use `quanpin.autocorrect_transposition` and `quanpin.autocorrect_neighbor`.
    pub autocorrect: bool,
    #[serde(default, skip_serializing_if = "QuanpinPreferences::is_empty")]
    pub quanpin: QuanpinPreferences,
    #[serde(default)]
    pub fuzzy_pinyin: FuzzyPinyinPreferences,
    #[serde(default)]
    pub quanpin_helpcode: HelpcodePreferences,
    #[serde(default)]
    pub shuangpin_helpcode: HelpcodePreferences,
    /// Render and commit Chinese Engine output in Traditional Chinese at the host boundary.
    #[serde(default)]
    pub traditional_chinese_output: bool,
    pub chinese_punctuation: bool,
    #[serde(default = "enabled_by_default")]
    pub smart_punctuation: bool,
    #[serde(default = "enabled_by_default")]
    pub smart_punctuation_repeat: bool,
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
    #[serde(default)]
    pub translation_target_language: TranslationTargetLanguage,
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
    #[serde(default)]
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
    #[serde(default)]
    pub asr_token: String,
    #[serde(default)]
    pub asr_endpoint: String,
    #[serde(default)]
    pub asr_model: String,
    #[serde(default)]
    pub asr_resource_id: String,
    #[serde(default)]
    pub polish_enabled: bool,
    #[serde(default)]
    pub polish_text: bool,
    #[serde(default)]
    pub polish_provider: String,
    #[serde(default)]
    pub polish_token: String,
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
    #[serde(default)]
    pub doubao_enable_ddc: bool,
    #[serde(default)]
    pub doubao_boosting_table_id: String,
}

impl Default for VoiceInputPreferences {
    fn default() -> Self {
        Self {
            enabled: true,
            sound_enabled: true,
            start_sound: true,
            end_sound: true,
            mute_system_audio: false,
            language: "zh-cn".into(),
            capture_backend: String::new(),
            capture_device: String::new(),
            commit_mode: "tsf".into(),
            asr_provider: "doubao".into(),
            asr_app_key: String::new(),
            asr_token: String::new(),
            asr_endpoint: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async".into(),
            asr_model: String::new(),
            asr_resource_id: "volc.seedasr.sauc.duration".into(),
            polish_enabled: false,
            polish_text: false,
            polish_provider: "siliconflow".into(),
            polish_token: String::new(),
            polish_endpoint: "https://api.siliconflow.cn/v1/chat/completions".into(),
            polish_model: "Qwen/Qwen3-8B".into(),
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
            doubao_enable_ddc: false,
            doubao_boosting_table_id: String::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AiAssistantPreferences {
    #[serde(default)]
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
        Self {
            enabled: false,
            provider: "deepseek".into(),
            model: String::new(),
            token: String::new(),
            tokens: BTreeMap::new(),
            endpoint: String::new(),
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
    #[serde(default)]
    pub screen_keyboard: bool,
    #[serde(default = "enabled_by_default")]
    pub settings: bool,
}

fn default_toolbar_scale() -> u16 {
    100
}
fn default_toolbar_font_size() -> u16 {
    24
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
            screen_keyboard: false,
            settings: true,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum ThemeMode {
    #[default]
    Dark,
    Light,
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
    #[default]
    Direct2d,
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
            minimum_prefix: 2,
            emoji: false,
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

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(deny_unknown_fields)]
pub struct WordCharacterPreferences {
    pub enabled: bool,
    pub keys: WordCharacterKeys,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct NavigationPreferences {
    pub minus_equal: bool,
    pub comma_period: bool,
    pub brackets: bool,
    pub tab: bool,
    pub page_up_down: bool,
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
}

impl Default for KeybindingPreferences {
    fn default() -> Self {
        Self {
            switch_language_shift: true,
            switch_language_ctrl: false,
            switch_language_ctrl_alt_space: true,
            toggle_character_set_ctrl_shift_f: true,
        }
    }
}

fn enabled_by_default() -> bool {
    true
}
fn default_candidate_font_size() -> u8 {
    16
}

fn default_touch_key_spacing_tenths() -> u8 {
    60
}

fn default_touch_row_spacing_tenths() -> u8 {
    70
}

fn default_candidate_skin() -> String {
    "fluent".to_owned()
}
fn default_candidate_font_family() -> String {
    "Segoe UI".to_owned()
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
            candidate_skin: default_candidate_skin(),
            candidate_layout: CandidateLayout::default(),
            candidate_preedit_style: CandidatePreeditStyle::default(),
            tsf_preedit_style: PreeditStyle::default(),
            diagnostic_log: DiagnosticLogPreferences::default(),
            ui_backend: UiBackend::default(),
            candidate_follow_cursor: true,
            scheme: InputScheme::default(),
            wubi_code_hint: None,
            touch_keyboard_layout: TouchKeyboardLayout::default(),
            touch_keyboard_skin: TouchKeyboardSkin::default(),
            custom_touch_keyboard_skin: TouchKeyboardSkinDesign::default(),
            touch_keyboard_schemes: TouchKeyboardSchemePreferences::default(),
            touch_key_spacing_tenths: default_touch_key_spacing_tenths(),
            touch_row_spacing_tenths: default_touch_row_spacing_tenths(),
            touch_keyboard_height_adjustment: 0,
            touch_voice_shortcut: false,
            last_chinese_scheme: None,
            shuangpin_profile: ShuangpinProfile::default(),
            shuangpin_preedit_uses_raw: true,
            candidate_page_size: 5,
            candidate_font_size: default_candidate_font_size(),
            candidate_preedit_font_size: default_candidate_font_size(),
            candidate_text_color: None,
            candidate_number_color: None,
            candidate_accent_color: None,
            candidate_selected_color: None,
            candidate_hover_color: None,
            candidate_surface_color: None,
            candidate_border_color: None,
            candidate_font_family: default_candidate_font_family(),
            candidate_fallback_fonts: Vec::new(),
            learning: true,
            autocorrect: true,
            quanpin: QuanpinPreferences::default(),
            fuzzy_pinyin: FuzzyPinyinPreferences::default(),
            quanpin_helpcode: HelpcodePreferences::default(),
            shuangpin_helpcode: HelpcodePreferences::default(),
            traditional_chinese_output: false,
            chinese_punctuation: true,
            smart_punctuation: true,
            smart_punctuation_repeat: true,
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
            translation_target_language: TranslationTargetLanguage::default(),
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

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(deny_unknown_fields)]
pub struct FuzzyPinyinPreferences {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub rules: BTreeSet<FuzzyPinyinRule>,
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
}

impl HelpcodeSchema {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Lantian => "lantian",
            Self::Ziranma => "ziranma",
            Self::Shouyou2 => "shouyou2_0",
            Self::Shouyouplus => "shouyouplus",
            Self::Xiaohe => "xiaohe",
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

/// Recognition providers a host can actually reach. The Linux voice provider
/// builds the same set, and the Engine's Windows voice configuration defaults
/// into it; a value outside this list is rejected by every backend.
pub const ASR_PROVIDERS: [&str; 4] = ["doubao", "siliconflow", "openai", "groq"];
/// Polishing additionally supports DeepSeek, which offers no recognition.
pub const POLISH_PROVIDERS: [&str; 5] = ["siliconflow", "openai", "deepseek", "groq", "doubao"];

impl Preferences {
    pub fn wubi_code_hint_enabled(&self) -> bool {
        self.wubi_code_hint.unwrap_or(true)
    }

    pub fn quanpin_autocorrect_transposition(&self) -> bool {
        self.quanpin
            .autocorrect_transposition
            .unwrap_or(self.autocorrect)
    }

    pub fn quanpin_autocorrect_neighbor(&self) -> bool {
        self.quanpin
            .autocorrect_neighbor
            .unwrap_or(self.autocorrect)
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
            || !matches!(
                self.ai_assistant.provider.as_str(),
                "deepseek" | "openai" | "siliconflow" | "groq"
            )
        {
            return Err(PreferencesError::InvalidAiAssistant);
        }
        if !ASR_PROVIDERS.contains(&self.voice_input.asr_provider.as_str())
            || !POLISH_PROVIDERS.contains(&self.voice_input.polish_provider.as_str())
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
        if self.candidate_font_family.is_empty() || self.candidate_font_family.len() > 128 {
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
            || self
                .candidate_fallback_fonts
                .iter()
                .any(|font| font.is_empty() || font.len() > 128)
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
    #[error("candidate font family must be non-empty ASCII and at most 128 bytes")]
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
        preferences: Preferences,
    ) -> Result<PreferencesSnapshot, PreferencesError> {
        preferences.validate()?;
        let _lock = self.lock()?;
        let current = self.read_locked()?;
        if current.revision != expected_revision {
            return Err(PreferencesError::Conflict);
        }
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
    let mut temporary = tempfile::NamedTempFile::new_in(directory)?;
    temporary.write_all(contents)?;
    temporary.as_file().sync_all()?;
    temporary.persist(path).map_err(|error| error.error)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn voice_commit_mode_defaults_for_legacy_documents() {
        let mut value = serde_json::to_value(Preferences::default()).unwrap();
        value["voice_input"]
            .as_object_mut()
            .unwrap()
            .remove("commit_mode");
        let restored: Preferences = serde_json::from_value(value).unwrap();
        assert_eq!(restored.voice_input.commit_mode, "tsf");
    }

    #[test]
    fn unreachable_voice_providers_normalize_on_read_without_rewriting_the_file() {
        // A file written by a build that offered "local_whisper" must still load.
        // No backend implements it: the Linux provider builds
        // {openai, groq, siliconflow, doubao}, so it would fail every recording.
        let directory = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(directory.path());
        let mut document = serde_json::to_value(PreferencesSnapshot {
            format_version: 1,
            revision: 3,
            preferences: Preferences::default(),
        })
        .unwrap();
        document["preferences"]["voice_input"]["asr_provider"] =
            serde_json::Value::String("local_whisper".into());
        document["preferences"]["voice_input"]["polish_provider"] =
            serde_json::Value::String("nonesuch".into());
        let path = directory.path().join("preferences.json");
        std::fs::write(&path, serde_json::to_vec(&document).unwrap()).unwrap();
        let original = std::fs::read(&path).unwrap();

        let snapshot = store.load().expect("a legacy file still loads");
        assert_eq!(
            snapshot.preferences.voice_input.asr_provider,
            Preferences::default().voice_input.asr_provider
        );
        assert_eq!(
            snapshot.preferences.voice_input.polish_provider,
            Preferences::default().voice_input.polish_provider
        );
        // Reading must not rewrite the user's file.
        assert_eq!(std::fs::read(&path).unwrap(), original);
    }

    #[test]
    fn every_reachable_voice_provider_validates_and_others_are_rejected_on_save() {
        for provider in ASR_PROVIDERS {
            let preferences = Preferences {
                voice_input: VoiceInputPreferences {
                    asr_provider: provider.into(),
                    ..Preferences::default().voice_input
                },
                ..Preferences::default()
            };
            assert!(
                preferences.validate().is_ok(),
                "{provider} should be accepted"
            );
        }
        for provider in POLISH_PROVIDERS {
            let preferences = Preferences {
                voice_input: VoiceInputPreferences {
                    polish_provider: provider.into(),
                    ..Preferences::default().voice_input
                },
                ..Preferences::default()
            };
            assert!(
                preferences.validate().is_ok(),
                "{provider} should polish"
            );
        }
        // Saving a provider no backend implements is refused rather than stored.
        for rejected in ["local_whisper", "cloud", "", "DOUBAO"] {
            let preferences = Preferences {
                voice_input: VoiceInputPreferences {
                    asr_provider: rejected.into(),
                    ..Preferences::default().voice_input
                },
                ..Preferences::default()
            };
            assert!(
                matches!(
                    preferences.validate(),
                    Err(PreferencesError::InvalidVoiceInput)
                ),
                "{rejected} should be rejected"
            );
        }
        // Recognition has no DeepSeek profile even though polishing does.
        let preferences = Preferences {
            voice_input: VoiceInputPreferences {
                asr_provider: "deepseek".into(),
                ..Preferences::default().voice_input
            },
            ..Preferences::default()
        };
        assert!(preferences.validate().is_err());
    }

    #[test]
    fn the_shipped_defaults_are_themselves_reachable() {
        let defaults = Preferences::default();
        assert!(ASR_PROVIDERS.contains(&defaults.voice_input.asr_provider.as_str()));
        assert!(POLISH_PROVIDERS.contains(&defaults.voice_input.polish_provider.as_str()));
        assert!(defaults.validate().is_ok());
    }

    #[test]
    fn candidate_english_gloss_is_opt_in_and_round_trips() {
        let defaults = Preferences::default();
        assert!(!defaults.candidate_english_gloss);
        let mut legacy = serde_json::to_value(&defaults).unwrap();
        legacy
            .as_object_mut()
            .unwrap()
            .remove("candidate_english_gloss");
        assert!(
            !serde_json::from_value::<Preferences>(legacy)
                .unwrap()
                .candidate_english_gloss
        );
        let enabled = Preferences {
            candidate_english_gloss: true,
            ..defaults
        };
        assert!(
            serde_json::from_str::<Preferences>(&serde_json::to_string(&enabled).unwrap())
                .unwrap()
                .candidate_english_gloss
        );
    }

    #[test]
    fn wubi_code_hint_defaults_on_and_legacy_documents_stay_implicit() {
        let defaults = Preferences::default();
        assert!(defaults.wubi_code_hint_enabled());
        let legacy = serde_json::to_value(&defaults).unwrap();
        assert!(!legacy.as_object().unwrap().contains_key("wubi_code_hint"));
        assert!(
            serde_json::from_value::<Preferences>(legacy)
                .unwrap()
                .wubi_code_hint_enabled()
        );

        let disabled = Preferences {
            wubi_code_hint: Some(false),
            ..defaults
        };
        assert!(
            !serde_json::from_str::<Preferences>(&serde_json::to_string(&disabled).unwrap())
                .unwrap()
                .wubi_code_hint_enabled()
        );
    }

    #[test]
    fn diagnostic_logging_defaults_off_and_survives_a_round_trip() {
        let defaults = Preferences::default();
        assert!(!defaults.diagnostic_log.server && !defaults.diagnostic_log.tsf);

        // A configuration written before the field existed keeps logging off
        // rather than starting to write a file the user never asked for.
        let mut document = serde_json::to_value(&defaults).unwrap();
        document.as_object_mut().unwrap().remove("diagnostic_log");
        let legacy: Preferences = serde_json::from_value(document).unwrap();
        assert_eq!(legacy.diagnostic_log, DiagnosticLogPreferences::default());

        // The two hosts are separate processes and are enabled separately.
        let preferences = Preferences {
            diagnostic_log: DiagnosticLogPreferences {
                server: true,
                tsf: false,
            },
            ..Preferences::default()
        };
        let restored: Preferences =
            serde_json::from_str(&serde_json::to_string(&preferences).unwrap()).unwrap();
        assert!(restored.diagnostic_log.server && !restored.diagnostic_log.tsf);

        let directory = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(directory.path());
        let saved = store.save(0, preferences).unwrap();
        assert!(saved.preferences.diagnostic_log.server);
        assert_eq!(
            store.load().unwrap().preferences.diagnostic_log,
            saved.preferences.diagnostic_log
        );
    }

    #[test]
    fn fuzzy_pinyin_preserves_disabled_rules_and_rejects_unknown_ids() {
        let directory = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(directory.path());
        let rules = [FuzzyPinyinRule::ZZh, FuzzyPinyinRule::FH]
            .into_iter()
            .collect();
        let fuzzy_pinyin = FuzzyPinyinPreferences {
            enabled: false,
            rules,
        };
        assert_eq!(fuzzy_pinyin.active_rules(), 0);
        let disabled = store
            .save(
                0,
                Preferences {
                    fuzzy_pinyin,
                    ..Preferences::default()
                },
            )
            .unwrap();
        assert_eq!(
            disabled.preferences.fuzzy_pinyin.rules,
            [FuzzyPinyinRule::ZZh, FuzzyPinyinRule::FH]
                .into_iter()
                .collect()
        );
        let mut enabled = disabled.preferences;
        enabled.fuzzy_pinyin.enabled = true;
        assert_eq!(enabled.fuzzy_pinyin.active_rules(), (1 << 0) | (1 << 4));
        let enabled = store.save(disabled.revision, enabled).unwrap();
        assert_eq!(store.load().unwrap(), enabled);

        let mut invalid = serde_json::to_value(enabled.preferences).unwrap();
        invalid["fuzzy_pinyin"]["rules"] = serde_json::json!(["z-zh", "unsupported"]);
        assert!(serde_json::from_value::<Preferences>(invalid).is_err());
    }

    #[test]
    fn capture_obeys_shared_enablement_and_preserves_corrupt_history() {
        let directory = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(directory.path());
        let file = directory.path().join("clipboard_history.json");
        let preferences = Preferences {
            clipboard_history: false,
            ..Preferences::default()
        };
        let disabled = store.save(0, preferences).unwrap();
        assert!(!store
            .capture_clipboard_text("synthetic disabled".into())
            .unwrap());
        assert!(!file.exists());
        let mut preferences = disabled.preferences;
        preferences.clipboard_history = true;
        let enabled = store.save(disabled.revision, preferences).unwrap();
        assert!(store
            .capture_clipboard_text("synthetic first".into())
            .unwrap());
        assert!(!store
            .capture_clipboard_text("synthetic\0invalid".into())
            .unwrap());
        assert_eq!(fs::read(&file).unwrap(), br#"["synthetic first"]"#);
        let mut preferences = enabled.preferences;
        preferences.clipboard_history = false;
        let disabled = store.save(enabled.revision, preferences).unwrap();
        assert!(!store
            .capture_clipboard_text("synthetic stopped".into())
            .unwrap());
        assert_eq!(fs::read(&file).unwrap(), br#"["synthetic first"]"#);
        fs::write(&file, b"broken synthetic document").unwrap();
        let mut preferences = disabled.preferences;
        preferences.clipboard_history = true;
        store.save(disabled.revision, preferences).unwrap();
        assert!(store
            .capture_clipboard_text("synthetic rejected".into())
            .is_err());
        assert_eq!(fs::read(&file).unwrap(), b"broken synthetic document");
    }

    #[test]
    fn default_ime_mode_legacy_defaults_and_roundtrips() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let mut legacy = serde_json::to_value(PreferencesSnapshot::default()).unwrap();
        legacy["preferences"]
            .as_object_mut()
            .unwrap()
            .remove("default_ime_mode");
        let bytes = serde_json::to_vec(&legacy).unwrap();
        fs::write(store.path(), bytes).unwrap();
        assert_eq!(
            store.load().unwrap().preferences.default_ime_mode,
            DefaultImeMode::Chinese
        );
        let mut value = serde_json::to_value(Preferences::default()).unwrap();
        value["default_ime_mode"] = "english".into();
        let saved = store
            .save(0, serde_json::from_value(value).unwrap())
            .unwrap();
        assert_eq!(
            store.load().unwrap().preferences.default_ime_mode,
            DefaultImeMode::English
        );
        assert_eq!(saved.preferences.default_ime_mode, DefaultImeMode::English);
    }

    #[test]
    fn local_mode_defaults_and_each_switch_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let mut legacy = serde_json::to_value(PreferencesSnapshot::default()).unwrap();
        legacy["preferences"]
            .as_object_mut()
            .unwrap()
            .remove("local_modes");
        let bytes = serde_json::to_vec(&legacy).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        assert_eq!(
            store.load().unwrap().preferences.local_modes,
            LocalModePreferences::default()
        );
        assert_eq!(fs::read(store.path()).unwrap(), bytes);
        for (revision, key) in [
            "unicode",
            "date_time",
            "quick_phrase",
            "emoji",
            "kaomoji",
            "super_jianpin",
            "temporary_english",
            "temporary_japanese",
        ]
        .iter()
        .enumerate()
        {
            let mut value = serde_json::to_value(Preferences::default()).unwrap();
            value["local_modes"][*key] = false.into();
            let saved = store
                .save(revision as u64, serde_json::from_value(value).unwrap())
                .unwrap();
            assert_eq!(store.load().unwrap(), saved);
        }
    }

    #[test]
    fn appearance_preferences_legacy_defaults_and_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let mut legacy = serde_json::to_value(PreferencesSnapshot::default()).unwrap();
        for key in [
            "theme",
            "settings_theme",
            "toolbar_theme",
            "screen_keyboard_theme",
            "touch_keyboard_skin",
            "ui_backend",
            "candidate_follow_cursor",
        ] {
            legacy["preferences"].as_object_mut().unwrap().remove(key);
        }
        let bytes = serde_json::to_vec(&legacy).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        assert_eq!(store.load().unwrap(), PreferencesSnapshot::default());
        assert_eq!(fs::read(store.path()).unwrap(), bytes);
        let preferences = Preferences {
            theme: ThemeMode::Light,
            settings_theme: SettingsTheme::Dark,
            toolbar_theme: SettingsTheme::Light,
            ui_backend: UiBackend::Webview2,
            candidate_follow_cursor: false,
            ..Preferences::default()
        };
        let saved = store.save(0, preferences).unwrap();
        assert_eq!(store.load().unwrap(), saved);
    }

    #[test]
    fn character_width_defaults_for_legacy_files_and_roundtrips() {
        let directory = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(directory.path());
        let mut legacy = serde_json::to_value(PreferencesSnapshot::default()).unwrap();
        legacy["preferences"]
            .as_object_mut()
            .unwrap()
            .remove("character_width");
        fs::write(store.path(), serde_json::to_vec(&legacy).unwrap()).unwrap();
        assert_eq!(
            store.load().unwrap().preferences.character_width,
            CharacterWidthPreference::Halfwidth
        );

        let saved = store
            .save(
                0,
                Preferences {
                    character_width: CharacterWidthPreference::Fullwidth,
                    ..Preferences::default()
                },
            )
            .unwrap();
        assert_eq!(
            store.load().unwrap().preferences.character_width,
            CharacterWidthPreference::Fullwidth
        );
        let document = serde_json::to_value(saved).unwrap();
        assert_eq!(document["preferences"]["character_width"], "fullwidth");

        let mut invalid = document["preferences"].clone();
        invalid["character_width"] = "invalid".into();
        assert!(serde_json::from_value::<Preferences>(invalid).is_err());
    }

    #[test]
    fn toolbar_theme_roundtrips_independently_and_rejects_unknown_values() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        for (revision, toolbar_theme) in [
            SettingsTheme::Dark,
            SettingsTheme::Light,
            SettingsTheme::Follow,
        ]
        .into_iter()
        .enumerate()
        {
            let preferences = Preferences {
                theme: ThemeMode::System,
                settings_theme: SettingsTheme::Light,
                candidate_theme: SettingsTheme::Dark,
                toolbar_theme,
                ..Preferences::default()
            };
            let saved = store.save(revision as u64, preferences).unwrap();
            assert_eq!(store.load().unwrap(), saved);
        }
        let mut invalid = serde_json::to_value(Preferences::default()).unwrap();
        invalid["toolbar_theme"] = "system".into();
        assert!(serde_json::from_value::<Preferences>(invalid).is_err());
    }

    #[test]
    fn screen_keyboard_theme_roundtrips_independently() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        for (revision, screen_keyboard_theme) in [
            SettingsTheme::Dark,
            SettingsTheme::Light,
            SettingsTheme::Follow,
        ]
        .into_iter()
        .enumerate()
        {
            let preferences = Preferences {
                theme: ThemeMode::System,
                toolbar_theme: SettingsTheme::Dark,
                screen_keyboard_theme,
                ..Preferences::default()
            };
            let saved = store.save(revision as u64, preferences).unwrap();
            assert_eq!(store.load().unwrap(), saved);
        }
        let mut invalid = serde_json::to_value(Preferences::default()).unwrap();
        invalid["screen_keyboard_theme"] = "system".into();
        assert!(serde_json::from_value::<Preferences>(invalid).is_err());
    }

    #[test]
    fn touch_keyboard_skin_uses_apple_ordered_ids_and_is_independent() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        for (revision, touch_keyboard_skin) in [
            TouchKeyboardSkin::Forest,
            TouchKeyboardSkin::Ocean,
            TouchKeyboardSkin::Rose,
            TouchKeyboardSkin::Porcelain,
            TouchKeyboardSkin::Typewriter,
            TouchKeyboardSkin::Candy,
            TouchKeyboardSkin::Midnight,
            TouchKeyboardSkin::Blueprint,
            TouchKeyboardSkin::Custom,
        ]
        .into_iter()
        .enumerate()
        {
            let preferences = Preferences {
                candidate_skin: "graphite".to_owned(),
                touch_keyboard_skin,
                ..Preferences::default()
            };
            let saved = store.save(revision as u64, preferences).unwrap();
            assert_eq!(saved.preferences.touch_keyboard_skin, touch_keyboard_skin);
            assert_eq!(saved.preferences.candidate_skin, "graphite");
            assert_eq!(store.load().unwrap(), saved);
        }
        let mut invalid = serde_json::to_value(Preferences::default()).unwrap();
        invalid["touch_keyboard_skin"] = "fluent".into();
        assert!(serde_json::from_value::<Preferences>(invalid).is_err());
    }

    #[test]
    fn custom_touch_keyboard_skin_matches_apple_fields_and_bounds() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let mut legacy = serde_json::to_value(PreferencesSnapshot::default()).unwrap();
        legacy["preferences"]
            .as_object_mut()
            .unwrap()
            .remove("custom_touch_keyboard_skin");
        let bytes = serde_json::to_vec(&legacy).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        assert_eq!(
            store.load().unwrap().preferences.custom_touch_keyboard_skin,
            TouchKeyboardSkinDesign::default()
        );
        assert_eq!(fs::read(store.path()).unwrap(), bytes);

        let design = TouchKeyboardSkinDesign {
            background: 0x151022,
            key_background: 0x291E40,
            key_foreground: 0xFFFFFF,
            accent: 0xD4BBFF,
            action_background: 0x69469B,
            corner_radius: 12.0,
            border_width: 1.5,
            shadow: 0.25,
            pattern: 3,
            monospaced: true,
            key_shape: Some(TouchSkinKeyShape::Pebble),
            key_material: Some(TouchSkinKeyMaterial::Glass),
            key_opacity: Some(0.45),
            gradient_end: Some(0x30224A),
            gradient_horizontal: Some(true),
            pattern_opacity: Some(0.2),
            custom_border_color: Some(0xA987E8),
            photo: Some("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=".into()),
            photo_shade: Some(0.8),
            photo_position: Some(1.0),
        };
        let preferences = Preferences {
            touch_keyboard_skin: TouchKeyboardSkin::Custom,
            custom_touch_keyboard_skin: design.clone(),
            ..Preferences::default()
        };
        let saved = store.save(0, preferences).unwrap();
        assert_eq!(saved.preferences.custom_touch_keyboard_skin, design);
        let value = serde_json::to_value(&saved.preferences.custom_touch_keyboard_skin).unwrap();
        assert_eq!(value["keyBackground"], 0x291E40);
        assert_eq!(value["keyShape"], "pebble");
        assert!(value.get("key_background").is_none());

        for invalid in [
            TouchKeyboardSkinDesign {
                background: 0x1000000,
                ..TouchKeyboardSkinDesign::default()
            },
            TouchKeyboardSkinDesign {
                corner_radius: 21.0,
                ..TouchKeyboardSkinDesign::default()
            },
            TouchKeyboardSkinDesign {
                key_opacity: Some(0.24),
                ..TouchKeyboardSkinDesign::default()
            },
            TouchKeyboardSkinDesign {
                photo: Some("not-base64".into()),
                ..TouchKeyboardSkinDesign::default()
            },
        ] {
            let mut preferences = saved.preferences.clone();
            preferences.custom_touch_keyboard_skin = invalid;
            assert!(matches!(
                store.save(saved.revision, preferences),
                Err(PreferencesError::InvalidTouchKeyboardSkinDesign)
            ));
            assert_eq!(store.load().unwrap(), saved);
        }
    }

    #[test]
    fn mixed_input_legacy_roundtrip_and_bounds() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let mut legacy = serde_json::to_value(PreferencesSnapshot::default()).unwrap();
        legacy["preferences"]
            .as_object_mut()
            .unwrap()
            .remove("mixed_input");
        let bytes = serde_json::to_vec(&legacy).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        assert_eq!(
            store.load().unwrap().preferences.mixed_input,
            MixedInputPreferences::default()
        );
        assert_eq!(fs::read(store.path()).unwrap(), bytes);
        for mask in 0..8 {
            let preferences = Preferences {
                mixed_input: MixedInputPreferences {
                    english: mask & 1 != 0,
                    emoji: mask & 2 != 0,
                    kaomoji: mask & 4 != 0,
                    minimum_prefix: mask + 1,
                },
                ..Preferences::default()
            };
            let saved = store.save(u64::from(mask), preferences).unwrap();
            assert_eq!(store.load().unwrap(), saved);
        }
        let saved = store.load().unwrap();
        for value in [0, 9, 255] {
            let mut invalid = saved.preferences.clone();
            invalid.mixed_input.minimum_prefix = value;
            assert!(matches!(
                store.save(saved.revision, invalid),
                Err(PreferencesError::InvalidMixedInput)
            ));
            assert_eq!(store.load().unwrap(), saved);
        }
    }

    #[test]
    fn frequency_legacy_defaults_modes_and_bounds() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let mut legacy = serde_json::to_value(PreferencesSnapshot::default()).unwrap();
        legacy["preferences"]
            .as_object_mut()
            .unwrap()
            .remove("frequency");
        let bytes = serde_json::to_vec(&legacy).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        assert_eq!(
            store.load().unwrap().preferences.frequency,
            FrequencyPreferences::default()
        );
        assert_eq!(fs::read(store.path()).unwrap(), bytes);
        for (revision, mode) in [
            FrequencyMode::Disabled,
            FrequencyMode::Pin,
            FrequencyMode::Halve,
            FrequencyMode::Linear,
            FrequencyMode::Promote,
        ]
        .into_iter()
        .enumerate()
        {
            let saved = store
                .save(
                    revision as u64,
                    Preferences {
                        frequency: FrequencyPreferences {
                            mode,
                            trigger_count: 10,
                            linear_step: 10,
                        },
                        ..Preferences::default()
                    },
                )
                .unwrap();
            assert_eq!(store.load().unwrap(), saved);
        }
        let saved = store.load().unwrap();
        for value in [0, 11, 255] {
            for trigger in [true, false] {
                let mut preferences = Preferences::default();
                if trigger {
                    preferences.frequency.trigger_count = value;
                } else {
                    preferences.frequency.linear_step = value;
                }
                assert!(matches!(
                    store.save(saved.revision, preferences),
                    Err(PreferencesError::InvalidFrequency)
                ));
                assert_eq!(store.load().unwrap(), saved);
            }
        }
    }

    #[test]
    fn word_character_legacy_roundtrip_and_conflict_protection() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let mut legacy = serde_json::to_value(PreferencesSnapshot::default()).unwrap();
        legacy["preferences"]
            .as_object_mut()
            .unwrap()
            .remove("word_character");
        let bytes = serde_json::to_vec(&legacy).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        assert_eq!(
            store.load().unwrap().preferences.word_character,
            WordCharacterPreferences::default()
        );
        assert_eq!(fs::read(store.path()).unwrap(), bytes);
        for (revision, keys) in [WordCharacterKeys::Brackets, WordCharacterKeys::MinusEqual]
            .into_iter()
            .enumerate()
        {
            let mut preferences = Preferences {
                word_character: WordCharacterPreferences {
                    enabled: true,
                    keys,
                },
                ..Preferences::default()
            };
            preferences.navigation.brackets = false;
            preferences.navigation.minus_equal = false;
            let saved = store.save(revision as u64, preferences.clone()).unwrap();
            assert_eq!(store.load().unwrap(), saved);
            match keys {
                WordCharacterKeys::Brackets => preferences.navigation.brackets = true,
                WordCharacterKeys::MinusEqual => preferences.navigation.minus_equal = true,
            }
            assert!(matches!(
                store.save(saved.revision, preferences),
                Err(PreferencesError::ConflictingKeyBindings)
            ));
            assert_eq!(store.load().unwrap(), saved);
        }
    }

    #[test]
    fn navigation_accepts_windows_candidate_arrow_alias() {
        let value = serde_json::json!({"minus_equal": true, "comma_period": true, "brackets": false, "tab": true, "page_up_down": true, "candidate_arrow_navigation": false});
        let parsed: NavigationPreferences = serde_json::from_value(value).unwrap();
        assert!(!parsed.arrows);
    }

    #[test]
    fn navigation_defaults_and_independent_flags_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let mut legacy = serde_json::to_value(PreferencesSnapshot::default()).unwrap();
        legacy["preferences"]
            .as_object_mut()
            .unwrap()
            .remove("navigation");
        let bytes = serde_json::to_vec(&legacy).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        assert_eq!(
            store.load().unwrap().preferences.navigation,
            NavigationPreferences::default()
        );
        assert_eq!(fs::read(store.path()).unwrap(), bytes);
        let preferences = Preferences {
            navigation: NavigationPreferences {
                minus_equal: false,
                comma_period: false,
                brackets: true,
                tab: false,
                page_up_down: false,
                arrows: false,
            },
            ..Preferences::default()
        };
        let saved = store.save(0, preferences).unwrap();
        assert_eq!(store.load().unwrap(), saved);
        let mut invalid = serde_json::to_value(saved).unwrap();
        invalid["preferences"]["navigation"]["tab"] = "invalid".into();
        let bytes = serde_json::to_vec(&invalid).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        assert!(store.save(1, Preferences::default()).is_err());
        assert_eq!(fs::read(store.path()).unwrap(), bytes);
    }

    #[test]
    fn remembered_chinese_scheme_roundtrips_without_changing_legacy_files() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let legacy = serde_json::to_vec(&PreferencesSnapshot::default()).unwrap();
        fs::write(store.path(), &legacy).unwrap();
        assert_eq!(store.load().unwrap().preferences.last_chinese_scheme, None);
        assert_eq!(fs::read(store.path()).unwrap(), legacy);
        for (revision, scheme) in [
            ChineseScheme::Quanpin,
            ChineseScheme::Shuangpin,
            ChineseScheme::Wubi,
        ]
        .into_iter()
        .enumerate()
        {
            let saved = store
                .save(
                    revision as u64,
                    Preferences {
                        scheme: InputScheme::Japanese,
                        last_chinese_scheme: Some(scheme),
                        ..Preferences::default()
                    },
                )
                .unwrap();
            assert_eq!(store.load().unwrap(), saved);
        }
        let mut invalid = serde_json::to_value(store.load().unwrap()).unwrap();
        invalid["preferences"]["last_chinese_scheme"] = "japanese".into();
        let bytes = serde_json::to_vec(&invalid).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        assert!(store.save(3, Preferences::default()).is_err());
        assert_eq!(fs::read(store.path()).unwrap(), bytes);
    }

    #[test]
    fn touch_keyboard_layout_defaults_and_roundtrips_without_rewriting_legacy_files() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let mut legacy = serde_json::to_value(PreferencesSnapshot::default()).unwrap();
        legacy["preferences"]
            .as_object_mut()
            .unwrap()
            .remove("touch_keyboard_layout");
        let bytes = serde_json::to_vec(&legacy).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        assert_eq!(
            store.load().unwrap().preferences.touch_keyboard_layout,
            TouchKeyboardLayout::TwentySixKey
        );
        assert_eq!(fs::read(store.path()).unwrap(), bytes);
        store
            .save(
                0,
                Preferences {
                    touch_keyboard_layout: TouchKeyboardLayout::NineKey,
                    ..Preferences::default()
                },
            )
            .unwrap();
        assert_eq!(
            store.load().unwrap().preferences.touch_keyboard_layout,
            TouchKeyboardLayout::NineKey
        );
        let saved = store
            .save(
                1,
                Preferences {
                    touch_keyboard_layout: TouchKeyboardLayout::Handwriting,
                    ..Preferences::default()
                },
            )
            .unwrap();
        assert_eq!(
            store.load().unwrap().preferences.touch_keyboard_layout,
            TouchKeyboardLayout::Handwriting
        );
        let mut invalid = serde_json::to_value(saved).unwrap();
        invalid["preferences"]["touch_keyboard_layout"] = "future_layout".into();
        let bytes = serde_json::to_vec(&invalid).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        assert!(store.load().is_err());
        assert_eq!(fs::read(store.path()).unwrap(), bytes);
    }

    #[test]
    fn touch_keyboard_scheme_visibility_matches_apple_order_and_fallback_contract() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let legacy = serde_json::to_vec(&PreferencesSnapshot::default()).unwrap();
        fs::write(store.path(), &legacy).unwrap();
        let loaded = store.load().unwrap();
        assert_eq!(
            loaded.preferences.touch_keyboard_schemes.enabled,
            TouchKeyboardScheme::ALL.into_iter().collect()
        );
        assert_eq!(loaded.preferences.touch_keyboard_schemes.selected, None);
        assert_eq!(fs::read(store.path()).unwrap(), legacy);

        let visible = [
            TouchKeyboardScheme::NineKey,
            TouchKeyboardScheme::Handwriting,
        ]
        .into_iter()
        .collect();
        let saved = store
            .save(
                0,
                Preferences {
                    touch_keyboard_schemes: TouchKeyboardSchemePreferences {
                        enabled: visible,
                        selected: Some(TouchKeyboardScheme::Handwriting),
                    },
                    ..Preferences::default()
                },
            )
            .unwrap();
        assert_eq!(store.load().unwrap(), saved);

        for value in [
            serde_json::json!({"enabled": [], "selected": null}),
            serde_json::json!({"enabled": ["nine_key"], "selected": "handwriting"}),
        ] {
            let mut invalid = serde_json::to_value(&saved).unwrap();
            invalid["preferences"]["touch_keyboard_schemes"] = value;
            let bytes = serde_json::to_vec(&invalid).unwrap();
            fs::write(store.path(), &bytes).unwrap();
            assert!(matches!(
                store.save(1, Preferences::default()),
                Err(PreferencesError::InvalidTouchKeyboardSchemes)
            ));
            assert_eq!(fs::read(store.path()).unwrap(), bytes);
        }

        let mut unknown = serde_json::to_value(&saved).unwrap();
        unknown["preferences"]["touch_keyboard_schemes"]["enabled"] =
            serde_json::json!(["nine_key", "future_scheme"]);
        let bytes = serde_json::to_vec(&unknown).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        assert!(store.load().is_err());
        assert_eq!(fs::read(store.path()).unwrap(), bytes);
    }

    #[test]
    fn touch_keyboard_spacing_uses_apple_defaults_bounds_and_legacy_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let mut legacy = serde_json::to_value(PreferencesSnapshot::default()).unwrap();
        for key in [
            "touch_key_spacing_tenths",
            "touch_row_spacing_tenths",
            "touch_keyboard_height_adjustment",
            "touch_voice_shortcut",
        ] {
            legacy["preferences"].as_object_mut().unwrap().remove(key);
        }
        let bytes = serde_json::to_vec(&legacy).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        let loaded = store.load().unwrap();
        assert_eq!(loaded.preferences.touch_key_spacing_tenths, 60);
        assert_eq!(loaded.preferences.touch_row_spacing_tenths, 70);
        assert_eq!(loaded.preferences.touch_keyboard_height_adjustment, 0);
        assert!(!loaded.preferences.touch_voice_shortcut);
        assert_eq!(fs::read(store.path()).unwrap(), bytes);

        let saved = store
            .save(
                0,
                Preferences {
                    touch_key_spacing_tenths: 35,
                    touch_row_spacing_tenths: 95,
                    touch_keyboard_height_adjustment: 24,
                    touch_voice_shortcut: true,
                    ..Preferences::default()
                },
            )
            .unwrap();
        assert_eq!(saved.preferences.touch_key_spacing_tenths, 35);
        assert_eq!(saved.preferences.touch_row_spacing_tenths, 95);
        assert_eq!(saved.preferences.touch_keyboard_height_adjustment, 24);
        assert!(saved.preferences.touch_voice_shortcut);

        for (key, value) in [
            ("touch_key_spacing_tenths", 29),
            ("touch_key_spacing_tenths", 61),
            ("touch_row_spacing_tenths", 39),
            ("touch_row_spacing_tenths", 101),
        ] {
            let mut invalid = saved.preferences.clone();
            match key {
                "touch_key_spacing_tenths" => invalid.touch_key_spacing_tenths = value,
                _ => invalid.touch_row_spacing_tenths = value,
            }
            assert!(matches!(
                invalid.validate(),
                Err(PreferencesError::InvalidTouchKeyboardSpacing)
            ));
        }

        for value in [-13, 49] {
            let mut invalid = saved.preferences.clone();
            invalid.touch_keyboard_height_adjustment = value;
            assert!(matches!(
                invalid.validate(),
                Err(PreferencesError::InvalidTouchKeyboardSpacing)
            ));
        }
    }

    #[test]
    fn helpcode_legacy_defaults_and_independent_schemes_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let mut legacy = serde_json::to_value(PreferencesSnapshot::default()).unwrap();
        for key in ["quanpin_helpcode", "shuangpin_helpcode"] {
            legacy["preferences"].as_object_mut().unwrap().remove(key);
        }
        let bytes = serde_json::to_vec(&legacy).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        assert_eq!(store.load().unwrap(), PreferencesSnapshot::default());
        assert_eq!(fs::read(store.path()).unwrap(), bytes);
        for (revision, schema) in [
            HelpcodeSchema::Lantian,
            HelpcodeSchema::Ziranma,
            HelpcodeSchema::Shouyou2,
            HelpcodeSchema::Shouyouplus,
            HelpcodeSchema::Xiaohe,
        ]
        .into_iter()
        .enumerate()
        {
            let preferences = Preferences {
                quanpin_helpcode: HelpcodePreferences {
                    enabled: false,
                    schema,
                    show_in_candidate_window: true,
                },
                ..Preferences::default()
            };
            let saved = store.save(revision as u64, preferences).unwrap();
            assert_eq!(store.load().unwrap(), saved);
            assert_eq!(
                saved.preferences.shuangpin_helpcode,
                HelpcodePreferences::default()
            );
        }
        let unknown = fs::read_to_string(store.path())
            .unwrap()
            .replace("xiaohe", "unknown");
        fs::write(store.path(), &unknown).unwrap();
        assert!(store.save(5, Preferences::default()).is_err());
        assert_eq!(fs::read_to_string(store.path()).unwrap(), unknown);
    }

    #[test]
    fn autocorrect_legacy_default_and_disabled_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let mut legacy = serde_json::to_value(PreferencesSnapshot::default()).unwrap();
        legacy["preferences"]
            .as_object_mut()
            .unwrap()
            .remove("autocorrect");
        let bytes = serde_json::to_vec(&legacy).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        assert!(store.load().unwrap().preferences.autocorrect);
        assert_eq!(fs::read(store.path()).unwrap(), bytes);
        let preferences = Preferences {
            autocorrect: false,
            ..Preferences::default()
        };
        store.save(0, preferences).unwrap();
        assert!(!store.load().unwrap().preferences.autocorrect);
    }

    #[test]
    fn traditional_chinese_output_legacy_default_and_enabled_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let mut legacy = serde_json::to_value(PreferencesSnapshot::default()).unwrap();
        legacy["preferences"]
            .as_object_mut()
            .unwrap()
            .remove("traditional_chinese_output");
        let bytes = serde_json::to_vec(&legacy).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        assert!(!store.load().unwrap().preferences.traditional_chinese_output);
        assert_eq!(fs::read(store.path()).unwrap(), bytes);
        let preferences = Preferences {
            traditional_chinese_output: true,
            ..Preferences::default()
        };
        store.save(0, preferences).unwrap();
        assert!(store.load().unwrap().preferences.traditional_chinese_output);
    }

    #[test]
    fn shuangpin_profiles_preserve_legacy_files_and_reject_unknown_values() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let legacy = r#"{"format_version":1,"revision":7,"preferences":{"scheme":"shuangpin","candidate_page_size":5,"learning":false,"chinese_punctuation":true}}"#;
        fs::write(store.path(), legacy).unwrap();
        assert_eq!(
            store.load().unwrap().preferences.shuangpin_profile,
            ShuangpinProfile::Xiaohe
        );
        assert_eq!(fs::read_to_string(store.path()).unwrap(), legacy);
        let mut revision = 7;
        for profile in [
            ShuangpinProfile::Xiaohe,
            ShuangpinProfile::Ziranma,
            ShuangpinProfile::Shoudao,
            ShuangpinProfile::Microsoft,
        ] {
            let saved = store
                .save(
                    revision,
                    Preferences {
                        scheme: InputScheme::Shuangpin,
                        shuangpin_profile: profile,
                        ..Preferences::default()
                    },
                )
                .unwrap();
            assert_eq!(store.load().unwrap(), saved);
            revision = saved.revision;
        }
        let unknown = fs::read_to_string(store.path())
            .unwrap()
            .replace("microsoft", "future_profile");
        fs::write(store.path(), &unknown).unwrap();
        assert!(store.load().is_err());
        assert!(store.save(revision, Preferences::default()).is_err());
        assert_eq!(fs::read_to_string(store.path()).unwrap(), unknown);
    }

    #[test]
    fn try_load_distinguishes_busy_missing_and_corrupt() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        assert_eq!(
            store.try_load().unwrap(),
            Some(PreferencesSnapshot::default())
        );
        let lock = store.lock().unwrap();
        assert_eq!(store.try_load().unwrap(), None);
        drop(lock);
        let saved = store.save(0, Preferences::default()).unwrap();
        assert_eq!(store.try_load().unwrap(), Some(saved));
        fs::write(store.path(), "broken").unwrap();
        assert!(store.try_load().is_err());
        assert_eq!(fs::read_to_string(store.path()).unwrap(), "broken");
    }

    #[test]
    fn persists_across_instances_and_rejects_stale_save() {
        let dir = tempfile::tempdir().unwrap();
        let first = PreferencesStore::new(dir.path());
        let second = PreferencesStore::new(dir.path());
        let preferences = Preferences {
            learning: false,
            ..Preferences::default()
        };
        let saved = first.save(0, preferences).unwrap();
        assert_eq!(saved.revision, 1);
        assert_eq!(second.load().unwrap(), saved);
        assert!(matches!(
            second.save(0, Preferences::default()),
            Err(PreferencesError::Conflict)
        ));
        assert_eq!(first.load().unwrap(), saved);
    }

    #[test]
    fn invalid_values_do_not_change_disk() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let initial = store.save(0, Preferences::default()).unwrap();
        for size in [0, 10, 255] {
            assert!(matches!(
                store.save(
                    1,
                    Preferences {
                        candidate_page_size: size,
                        ..Preferences::default()
                    }
                ),
                Err(PreferencesError::InvalidPageSize)
            ));
        }
        assert_eq!(store.load().unwrap(), initial);
    }

    #[test]
    fn ai_assistant_rejects_unknown_provider_and_invalid_candidate_limit() {
        let mut preferences = Preferences::default();
        preferences.ai_assistant.provider = "unknown".into();
        assert!(matches!(
            preferences.validate(),
            Err(PreferencesError::InvalidAiAssistant)
        ));
        preferences.ai_assistant.provider = "openai".into();
        preferences.ai_assistant.candidate_limit = 11;
        assert!(matches!(
            preferences.validate(),
            Err(PreferencesError::InvalidAiAssistant)
        ));
    }

    #[test]
    fn candidate_font_size_bounds_are_strict() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let initial = store.save(0, Preferences::default()).unwrap();
        for size in [11, 33, 255] {
            assert!(matches!(
                store.save(
                    1,
                    Preferences {
                        candidate_font_size: size,
                        ..Preferences::default()
                    }
                ),
                Err(PreferencesError::InvalidCandidateFontSize)
            ));
        }
        let saved = store
            .save(
                1,
                Preferences {
                    candidate_font_size: 12,
                    ..Preferences::default()
                },
            )
            .unwrap();
        assert_eq!(saved.preferences.candidate_font_size, 12);
        let other_dir = tempfile::tempdir().unwrap();
        let other = PreferencesStore::new(other_dir.path());
        other.save(0, Preferences::default()).unwrap();
        let saved = other
            .save(
                1,
                Preferences {
                    candidate_font_size: 32,
                    ..Preferences::default()
                },
            )
            .unwrap();
        assert_eq!(saved.preferences.candidate_font_size, 32);
        assert!(initial.preferences.candidate_font_size == 16);
    }

    #[test]
    fn candidate_appearance_colors_accept_hex_and_reject_unsafe_values() {
        let mut preferences = Preferences::default();
        macro_rules! check {
            ($field:ident) => {{
                preferences.$field = Some("#12aBcD".to_owned());
                assert!(preferences.validate().is_ok());
                preferences.$field = Some("#12345678".to_owned());
                assert!(preferences.validate().is_err());
                preferences.$field = None;
            }};
        }
        check!(candidate_text_color);
        check!(candidate_number_color);
        check!(candidate_accent_color);
        check!(candidate_selected_color);
        check!(candidate_hover_color);
        check!(candidate_surface_color);
        check!(candidate_border_color);
    }

    #[test]
    fn candidate_skin_ids_are_safe_and_bounded() {
        let mut preferences = Preferences::default();
        for skin in ["fluent", "willow_green", "external.skin-1"] {
            preferences.candidate_skin = skin.to_owned();
            assert!(preferences.validate().is_ok(), "{skin}");
        }
        for skin in ["", "-unsafe", "Upper", "../escape", &"a".repeat(65)] {
            preferences.candidate_skin = skin.to_owned();
            assert!(
                matches!(
                    preferences.validate(),
                    Err(PreferencesError::InvalidCandidateSkin)
                ),
                "{skin}"
            );
        }
    }

    #[test]
    fn unicode_font_families_and_ordered_fallbacks_round_trip() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let fallback_fonts: Vec<String> = (0..32).map(|index| format!("示例字体{index}")).collect();
        let preferences = Preferences {
            candidate_font_family: "示例主字体".to_owned(),
            candidate_fallback_fonts: fallback_fonts.clone(),
            ..Preferences::default()
        };
        let saved = store.save(0, preferences).unwrap();
        let loaded = store.load().unwrap();
        assert_eq!(loaded.preferences.candidate_font_family, "示例主字体");
        assert_eq!(loaded.preferences.candidate_fallback_fonts, fallback_fonts);
        assert_eq!(loaded.revision, saved.revision);
    }

    #[test]
    fn candidate_fallback_fonts_reject_invalid_lists() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let initial = store.save(0, Preferences::default()).unwrap();
        for fonts in [
            vec!["".to_owned()],
            vec!["a".repeat(129)],
            vec!["字".repeat(43)],
            (0..33).map(|index| format!("Font{index}")).collect(),
        ] {
            assert!(matches!(
                store.save(
                    1,
                    Preferences {
                        candidate_fallback_fonts: fonts,
                        ..Preferences::default()
                    }
                ),
                Err(PreferencesError::InvalidCandidateFontFamily)
            ));
        }
        let valid = vec!["Noto Sans CJK SC".to_owned(); 32];
        let saved = store
            .save(
                1,
                Preferences {
                    candidate_fallback_fonts: valid.clone(),
                    ..Preferences::default()
                },
            )
            .unwrap();
        assert_eq!(saved.preferences.candidate_fallback_fonts, valid);
        assert_eq!(store.load().unwrap().revision, 2);
        assert_eq!(initial.revision, 1);
    }

    #[test]
    fn unicode_font_names_retain_utf8_byte_budget() {
        let exact_limit = format!("{}ab", "字".repeat(42));
        assert_eq!(exact_limit.len(), 128);
        let mut preferences = Preferences {
            candidate_font_family: exact_limit.clone(),
            candidate_fallback_fonts: vec![exact_limit.clone()],
            ..Preferences::default()
        };
        assert!(preferences.validate().is_ok());
        for invalid in [String::new(), format!("{exact_limit}c"), "字".repeat(43)] {
            preferences.candidate_font_family = invalid;
            assert!(matches!(
                preferences.validate(),
                Err(PreferencesError::InvalidCandidateFontFamily)
            ));
        }
    }

    #[test]
    fn malformed_future_and_unknown_documents_are_preserved() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        for bytes in ["broken".to_owned(), serde_json::to_string(&PreferencesSnapshot { format_version: 2, ..PreferencesSnapshot::default() }).unwrap(),
            r#"{"format_version":1,"revision":0,"preferences":{"scheme":"quanpin","candidate_page_size":5,"learning":true,"chinese_punctuation":true,"future_option":true}}"#.to_owned()] {
            fs::write(store.path(), &bytes).unwrap();
            assert!(store.save(0, Preferences::default()).is_err());
            assert_eq!(fs::read_to_string(store.path()).unwrap(), bytes);
        }
    }

    #[test]
    fn concurrent_stores_have_exactly_one_winner() {
        let dir = tempfile::tempdir().unwrap();
        let barrier = std::sync::Arc::new(std::sync::Barrier::new(8));
        let handles: Vec<_> = (0..8)
            .map(|_| {
                let barrier = barrier.clone();
                let store = PreferencesStore::new(dir.path());
                std::thread::spawn(move || {
                    barrier.wait();
                    store.save(0, Preferences::default())
                })
            })
            .collect();
        let results: Vec<_> = handles.into_iter().map(|h| h.join().unwrap()).collect();
        assert_eq!(results.iter().filter(|r| r.is_ok()).count(), 1);
        assert_eq!(
            results
                .iter()
                .filter(|r| matches!(r, Err(PreferencesError::Conflict)))
                .count(),
            7
        );
    }

    #[test]
    fn floating_toolbar_component_defaults_and_roundtrip() {
        let defaults = Preferences::default().floating_toolbar;
        assert!(
            defaults.enabled && defaults.english_mode && defaults.fullwidth && defaults.punctuation
        );
        assert!(defaults.character_set && defaults.emoji && defaults.settings);
        assert!(!defaults.screen_keyboard);
        let json = serde_json::to_string(&Preferences::default()).unwrap();
        let restored: Preferences = serde_json::from_str(&json).unwrap();
        assert_eq!(restored.floating_toolbar, defaults);
    }

    #[test]
    fn legacy_preferences_without_toolbar_use_component_defaults() {
        let mut value = serde_json::to_value(PreferencesSnapshot::default()).unwrap();
        value["preferences"]
            .as_object_mut()
            .unwrap()
            .remove("floating_toolbar");
        let restored: PreferencesSnapshot = serde_json::from_value(value).unwrap();
        assert!(restored.preferences.floating_toolbar.enabled);
        assert!(restored.preferences.floating_toolbar.english_mode);
        assert!(restored.preferences.floating_toolbar.fullwidth);
        assert!(!restored.preferences.floating_toolbar.screen_keyboard);
    }

    #[test]
    fn tencent_translation_defaults_migrate_and_round_trip() {
        let defaults = Preferences::default();
        assert!(defaults.tencent_tmt.enabled);
        assert!(defaults.tencent_tmt.secret_id.is_empty());
        assert!(defaults.tencent_tmt.secret_key.is_empty());
        assert_eq!(defaults.tencent_tmt.region, "ap-guangzhou");
        let mut legacy = serde_json::to_value(&defaults).unwrap();
        legacy.as_object_mut().unwrap().remove("tencent_tmt");
        let restored: Preferences = serde_json::from_value(legacy).unwrap();
        assert_eq!(restored.tencent_tmt, defaults.tencent_tmt);
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let mut configured = defaults;
        configured.tencent_tmt.secret_id = "AKIDsynthetic".into();
        configured.tencent_tmt.secret_key = "synthetic".into();
        configured.tencent_tmt.region = "ap-shanghai".into();
        configured.candidate_page_size = 7;
        store.save(0, configured.clone()).unwrap();
        assert_eq!(store.load().unwrap().preferences, configured);
    }

    #[test]
    fn tencent_translation_rejects_unbounded_or_injected_parameters() {
        for (id, key, region) in [
            ("x".repeat(4097), String::new(), String::new()),
            (String::new(), "x".repeat(4097), String::new()),
            ("bad id".into(), String::new(), String::new()),
            (String::new(), "bad\r\nkey".into(), String::new()),
            (String::new(), String::new(), "x".repeat(65)),
            (String::new(), String::new(), "region\r\nheader".into()),
        ] {
            let mut preferences = Preferences::default();
            preferences.tencent_tmt.secret_id = id;
            preferences.tencent_tmt.secret_key = key;
            preferences.tencent_tmt.region = region;
            assert!(matches!(
                preferences.validate(),
                Err(PreferencesError::InvalidTencentTmt)
            ));
        }
    }

    #[test]
    fn custom_translation_defaults_and_validation_are_stable() {
        let defaults = Preferences::default();
        assert!(!defaults.custom_translation.enabled);
        assert!(defaults.custom_translation.endpoint.is_empty());
        let json = serde_json::to_string(&defaults).unwrap();
        let restored: Preferences = serde_json::from_str(&json).unwrap();
        assert_eq!(restored.custom_translation, defaults.custom_translation);

        let mut valid = defaults.clone();
        valid.custom_translation.api_key = "masked-test-key".into();
        for endpoint in [
            "https://translate.example/api",
            "http://127.0.0.1:1188/translate",
            "http://[::1]:1188/translate",
            "http://translate.example/api",
        ] {
            valid.custom_translation.endpoint = endpoint.into();
            assert!(valid.validate().is_ok());
        }

        for endpoint in [
            "ftp://translate.example/api",
            "https://translate.example/\napi",
        ] {
            let mut invalid = defaults.clone();
            invalid.custom_translation.endpoint = endpoint.into();
            assert!(matches!(
                invalid.validate(),
                Err(PreferencesError::InvalidCustomTranslation)
            ));
        }
        let mut oversized = defaults;
        oversized.custom_translation.api_key = "x".repeat(4097);
        assert!(matches!(
            oversized.validate(),
            Err(PreferencesError::InvalidCustomTranslation)
        ));
    }
}
