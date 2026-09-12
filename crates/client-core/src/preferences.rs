//! Versioned local preferences. Hosts supply a private application data directory.
//! All writers coordinate through the stable lock file, not the replaced data file.

use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
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

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
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
    pub floating_toolbar: FloatingToolbarPreferences,
    #[serde(default)]
    pub theme: ThemeMode,
    #[serde(default)]
    pub settings_theme: SettingsTheme,
    #[serde(default)]
    pub candidate_theme: SettingsTheme,
    #[serde(default = "default_candidate_skin")]
    pub candidate_skin: String,
    #[serde(default)]
    pub candidate_layout: CandidateLayout,
    #[serde(default)]
    pub candidate_preedit_style: CandidatePreeditStyle,
    #[serde(default)]
    pub tsf_preedit_style: PreeditStyle,
    #[serde(default)]
    pub ui_backend: UiBackend,
    #[serde(default = "enabled_by_default")]
    pub candidate_follow_cursor: bool,
    pub scheme: InputScheme,
    #[serde(default)]
    pub touch_keyboard_layout: TouchKeyboardLayout,
    /// Horizontal key gap in tenths of a density-independent pixel.
    #[serde(default = "default_touch_key_spacing_tenths")]
    pub touch_key_spacing_tenths: u8,
    /// Vertical row gap in tenths of a density-independent pixel.
    #[serde(default = "default_touch_row_spacing_tenths")]
    pub touch_row_spacing_tenths: u8,
    /// Show a direct voice-result entry in touch-keyboard toolbars.
    #[serde(default)]
    pub touch_voice_shortcut: bool,
    /// Retained when the active scheme is Japanese. Absent in legacy documents.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_chinese_scheme: Option<ChineseScheme>,
    #[serde(default)]
    pub shuangpin_profile: ShuangpinProfile,
    pub candidate_page_size: u8,
    #[serde(default = "default_candidate_font_size")]
    pub candidate_font_size: u8,
    #[serde(default = "default_candidate_font_size")]
    pub candidate_preedit_font_size: u8,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub candidate_text_color: Option<String>,
    #[serde(default = "default_candidate_font_family")]
    pub candidate_font_family: String,
    #[serde(default)]
    pub candidate_fallback_fonts: Vec<String>,
    pub learning: bool,
    #[serde(default = "enabled_by_default")]
    pub autocorrect: bool,
    #[serde(default)]
    pub quanpin_helpcode: HelpcodePreferences,
    #[serde(default)]
    pub shuangpin_helpcode: HelpcodePreferences,
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
    #[serde(default = "enabled_by_default")]
    pub clipboard_history: bool,
    /// Fetch one additional candidate from the configured cloud provider.
    #[serde(default = "enabled_by_default")]
    pub cloud_candidates: bool,
    #[serde(default = "enabled_by_default")]
    pub candidate_translations: bool,
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
    #[serde(default)]
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
    pub polish_enabled: bool,
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
            commit_mode: "tsf".into(),
            asr_provider: "doubao".into(),
            asr_app_key: String::new(),
            asr_token: String::new(),
            asr_endpoint: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async".into(),
            asr_model: String::new(),
            polish_enabled: false,
            polish_provider: "siliconflow".into(),
            polish_token: String::new(),
            polish_endpoint: "https://api.siliconflow.cn/v1/chat/completions".into(),
            polish_model: "Qwen/Qwen3-8B".into(),
            polish_prompt_id: "cleanup".into(),
            polish_prompt: String::new(),
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

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FloatingToolbarPreferences {
    #[serde(default = "enabled_by_default")]
    pub enabled: bool,
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

impl Default for Preferences {
    fn default() -> Self {
        Self {
            default_ime_mode: DefaultImeMode::default(),
            ime_mode_scope: ImeModeScope::default(),
            ai_assistant: AiAssistantPreferences::default(),
            custom_translation: CustomTranslationPreferences::default(),
            voice_input: VoiceInputPreferences::default(),
            floating_toolbar: FloatingToolbarPreferences::default(),
            theme: ThemeMode::default(),
            settings_theme: SettingsTheme::default(),
            candidate_theme: SettingsTheme::default(),
            candidate_skin: default_candidate_skin(),
            candidate_layout: CandidateLayout::default(),
            candidate_preedit_style: CandidatePreeditStyle::default(),
            tsf_preedit_style: PreeditStyle::default(),
            ui_backend: UiBackend::default(),
            candidate_follow_cursor: true,
            scheme: InputScheme::default(),
            touch_keyboard_layout: TouchKeyboardLayout::default(),
            touch_key_spacing_tenths: default_touch_key_spacing_tenths(),
            touch_row_spacing_tenths: default_touch_row_spacing_tenths(),
            touch_voice_shortcut: false,
            last_chinese_scheme: None,
            shuangpin_profile: ShuangpinProfile::default(),
            candidate_page_size: 5,
            candidate_font_size: default_candidate_font_size(),
            candidate_preedit_font_size: default_candidate_font_size(),
            candidate_text_color: None,
            candidate_font_family: default_candidate_font_family(),
            candidate_fallback_fonts: Vec::new(),
            learning: true,
            autocorrect: true,
            quanpin_helpcode: HelpcodePreferences::default(),
            shuangpin_helpcode: HelpcodePreferences::default(),
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
            clipboard_history: true,
            cloud_candidates: true,
            candidate_translations: true,
            translation_target_language: TranslationTargetLanguage::default(),
        }
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
    pub enabled: bool,
    pub schema: HelpcodeSchema,
}

impl Default for HelpcodePreferences {
    fn default() -> Self {
        Self {
            enabled: true,
            schema: HelpcodeSchema::default(),
        }
    }
}

impl Preferences {
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

    pub fn validate(&self) -> Result<(), PreferencesError> {
        let translation = &self.custom_translation;
        if translation.endpoint.len() > 2048
            || translation.api_key.len() > 4096
            || translation.endpoint.chars().any(char::is_control)
            || translation.api_key.chars().any(char::is_control)
            || (!translation.endpoint.is_empty() && !translation.endpoint.starts_with("https://"))
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
        {
            return Err(PreferencesError::InvalidTouchKeyboardSpacing);
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
        if self.candidate_font_family.is_empty()
            || self.candidate_font_family.len() > 128
            || !self.candidate_font_family.is_ascii()
        {
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
        if self.candidate_fallback_fonts.len() > 8
            || self
                .candidate_fallback_fonts
                .iter()
                .any(|font| font.is_empty() || font.len() > 128 || !font.is_ascii())
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

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
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
    #[error("custom translation endpoint or API key is invalid")]
    InvalidCustomTranslation,
    #[error("candidate page size must be between 1 and 9")]
    InvalidPageSize,
    #[error("touch keyboard key spacing must be 3.0-6.0 and row spacing must be 4.0-10.0")]
    InvalidTouchKeyboardSpacing,
    #[error("candidate font size must be between 12 and 32")]
    InvalidCandidateFontSize,
    #[error("candidate text color must be #RRGGBB or omitted")]
    InvalidCandidateTextColor,
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
        let snapshot: PreferencesSnapshot = serde_json::from_slice(&bytes)?;
        if snapshot.format_version != 1 {
            return Err(PreferencesError::UnsupportedFormat);
        }
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
            ui_backend: UiBackend::Webview2,
            candidate_follow_cursor: false,
            ..Preferences::default()
        };
        let saved = store.save(0, preferences).unwrap();
        assert_eq!(store.load().unwrap(), saved);
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
    fn touch_keyboard_spacing_uses_apple_defaults_bounds_and_legacy_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let mut legacy = serde_json::to_value(PreferencesSnapshot::default()).unwrap();
        for key in [
            "touch_key_spacing_tenths",
            "touch_row_spacing_tenths",
            "touch_voice_shortcut",
        ] {
            legacy["preferences"].as_object_mut().unwrap().remove(key);
        }
        let bytes = serde_json::to_vec(&legacy).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        let loaded = store.load().unwrap();
        assert_eq!(loaded.preferences.touch_key_spacing_tenths, 60);
        assert_eq!(loaded.preferences.touch_row_spacing_tenths, 70);
        assert!(!loaded.preferences.touch_voice_shortcut);
        assert_eq!(fs::read(store.path()).unwrap(), bytes);

        let saved = store
            .save(
                0,
                Preferences {
                    touch_key_spacing_tenths: 35,
                    touch_row_spacing_tenths: 95,
                    touch_voice_shortcut: true,
                    ..Preferences::default()
                },
            )
            .unwrap();
        assert_eq!(saved.preferences.touch_key_spacing_tenths, 35);
        assert_eq!(saved.preferences.touch_row_spacing_tenths, 95);
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
    fn candidate_fallback_fonts_reject_invalid_lists() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let initial = store.save(0, Preferences::default()).unwrap();
        for fonts in [
            vec!["".to_owned()],
            vec!["字体".to_owned()],
            (0..9).map(|index| format!("Font{index}")).collect(),
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
        let valid = vec!["Noto Sans CJK SC".to_owned(); 8];
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
        assert!(defaults.enabled && defaults.fullwidth && defaults.punctuation);
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
        assert!(restored.preferences.floating_toolbar.fullwidth);
        assert!(!restored.preferences.floating_toolbar.screen_keyboard);
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
        valid.custom_translation.endpoint = "https://translate.example/api".into();
        valid.custom_translation.api_key = "masked-test-key".into();
        assert!(valid.validate().is_ok());

        for endpoint in [
            "http://translate.example/api",
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
