import { VoiceDevicePicker, type VoiceDeviceReader } from "./voice-device-picker";
import { useEffect, useRef, useState } from "react";
import { HostActionButton } from "./HostActionButton";
import { DICTIONARY_PAGE_SIZE, dictionaryPageStatus, parsePersonalDictionaryImport, personalDictionaryExample, readDictionaryFile, type PersonalDictionaryImportEntry } from "./dictionary-file";
import { SkinCandidatePreview } from "./skin-candidate-preview";
import { AppearanceCandidatePreview } from "./appearance-candidate-preview";
import { candidateFontSize, candidateFontSizes } from "./candidate-font-size";
import { candidateTextColor } from "./candidate-text-color";
import { useCandidatePreviewTheme } from "./candidate-preview-theme";
import { CandidateFontControls } from "./candidate-font-controls";
import { validCandidateFonts } from "./candidate-font-family";
import type { FontCatalogReader } from "./font-catalog";
import { SecretInput } from "./secret-input";
import { asrProviderUpdate, polishProviderUpdate } from "./voice-providers";
import { POLISH_PRESET_IDS, POLISH_PRESET_NAMES, isPolishCustomSlot, normalizePolishSlot, polishPresetPrompt } from "./polish-presets";
import { SkinToolbarPreview } from "./skin-toolbar-preview";
import { ScreenKeyboardPreview, touchKeyboardSkinOptions } from "./screen-keyboard-preview";
import type { TouchKeyboardSkin } from "./screen-keyboard-preview";
import { TouchKeyboardSkinEditor } from "./touch-keyboard-skin-editor";
import { defaultTouchKeyboardSkinDesign, type AiSkinClient, type CustomSkinLibraryClient, type TouchKeyboardSkinDesign } from "./touch-keyboard-skin-design";
export type { AiSkinClient, AiSkinProposal, AiSkinProgress, CustomSkinLibraryAction, CustomSkinLibraryClient, SavedTouchKeyboardSkin, TouchKeyboardSkinDesign } from "./touch-keyboard-skin-design";
import { ExternalSkins, type SkinCatalog } from "./external-skins";
import { TypingStatisticsPage, type TypingStatisticsClient } from "./typing-statistics";
import { AccountPage, type AccountClient } from "./account-page";
import { ChatPage, type ChatClient } from "./chat-page";
import { HomePage, type HomePageActions } from "./home-page";
import { WelcomeFlowPage } from "./onboarding-page";
import { CommunitySkinsPage, type CommunitySkinClient } from "./community-skins";
import { CommunityHomePage, CommunityResourcesPage, type CommunityResourceClient } from "./community-resources";
export { TypingStatisticsPage, type TypingBreakdown, type TypingStatistics, type TypingStatisticsClient, type TypingStatisticsStatus } from "./typing-statistics";
export { AccountPage, type AccountChallenge, type AccountClient, type AccountPreferenceSchema, type AccountPreferences, type AccountPreferenceValue, type AccountProfile, type AccountProviders, type AccountUser, type AppIconClient, type AppIconInfo, type SettingsSyncClient } from "./account-page";
export { ChatPage, type ChatClient, type ChatMessage, type ChatModel, type ChatModels } from "./chat-page";
export { HomePage, type HomePageActions } from "./home-page";
export { WelcomeFlowPage, type OnboardingActions, type OnboardingInputScheme } from "./onboarding-page";
export { CommunitySkinsPage, type CommunitySkin, type CommunitySkinClient, type CommunitySkinDownload, type CommunitySkinPage, type CommunitySkinTrial } from "./community-skins";
export { CommunityHomePage, CommunityResourcesPage, type CommunityLocalDictionaryClient, type CommunityResource, type CommunityResourceApplication, type CommunityResourceClient, type CommunityResourceContent, type CommunityResourceKind, type CommunityResourcePage, type CommunityResourceScope, type CommunitySharedWord } from "./community-resources";
export type { SkinCatalog, ExternalSkin } from "./external-skins";
import type { SkinImageReader } from "./skin-image";
export type { SkinImage, SkinImageReader } from "./skin-image";
import type { SkinFontReader } from "./skin-font";
export type { SkinFont, SkinFontReader } from "./skin-font";
export { POLISH_CUSTOM_IDS, POLISH_PRESETS, POLISH_PRESET_IDS, POLISH_PRESET_NAMES, isPolishCustomSlot, normalizePolishSlot, polishPresetPrompt, type PolishPresetId } from "./polish-presets";
export { ASR_PROVIDER_DEFAULTS, POLISH_PROVIDER_DEFAULTS, asrProviderUpdate, polishProviderUpdate, type ProviderDefaults } from "./voice-providers";
export { candidateTemplate, candidateThemeStylesheet, type CandidateAppearance, type CandidateOrientation, type CandidateTheme } from "./candidate-themes";
import { compareVersions, describeInstallerTrust, parseVersion, validateManifest, type UpdateManifest, type ValidatedUpdate } from "./update-manifest";
export { serializeWindowHostMessage, type WindowControl, type WindowHostMessage, type WindowResizeEdge } from "./window-host";
export { emojiDisplayName } from "./panels";
export { CloudCandidatesPanel, CloudClipboardPanel, CloudDictionaryCatalogPanel, CloudDictionaryPanel, EmojiPanel, HandwritingPanel, KeyboardPanel, VoicePanel, type CloudCandidate, type CloudCandidateKind, type CloudClipboardAction, type CloudClipboardPanelClient, type CloudDictionaryAction, type CloudDictionaryCatalogEntry, type CloudDictionaryEntry, type CloudDictionaryFileFormat, type CloudDictionaryKind, type CloudDictionaryPanelClient, type CloudDictionarySnapshotMetadata, type CloudDictionarySnapshotRequest, type CloudFixedPosition, type CloudRankingMode, type EmojiPanelClient, type PanelClient, type VoicePanelClient } from "./panels";
export type { EmojiCatalogGroup } from "./emoji-catalog";

export type HelpcodeSchema = "lantian" | "ziranma" | "shouyou2_0" | "shouyouplus" | "xiaohe";
export type HelpcodePreferences = { enabled: boolean; schema: HelpcodeSchema; show_in_candidate_window?: boolean };
const defaultHelpcode: HelpcodePreferences = { enabled: true, schema: "ziranma", show_in_candidate_window: true };
export type KeybindingPreferences = {
  switch_language_shift: boolean;
  switch_language_ctrl: boolean;
  switch_language_ctrl_alt_space: boolean;
  toggle_character_set_ctrl_shift_f: boolean;
};
const defaultKeybindings: KeybindingPreferences = {
  switch_language_shift: true,
  switch_language_ctrl: false,
  switch_language_ctrl_alt_space: true,
  toggle_character_set_ctrl_shift_f: true,
};
export type FuzzyPinyinPreferences = { enabled: boolean; rules: string[]; seeded?: boolean };
const defaultFuzzyPinyin: FuzzyPinyinPreferences = { enabled: false, rules: [] };
const fuzzyPinyinGroups: [string, [string, string][]][] = [
  ["平翘舌", [["z-zh", "z ↔ zh"], ["c-ch", "c ↔ ch"], ["s-sh", "s ↔ sh"]]],
  ["声母", [["n-l", "n ↔ l"], ["f-h", "f ↔ h"], ["r-l", "r ↔ l"]]],
  ["前后鼻音", [["an-ang", "an ↔ ang"], ["en-eng", "en ↔ eng"], ["in-ing", "in ↔ ing"]]],
  ["其他韵母", [["ian-iang", "ian ↔ iang"], ["uan-uang", "uan ↔ uang"]]],
];
export type TouchKeyboardScheme = "quanpin" | "nine_key" | "xiaohe" | "ziranma" | "microsoft" |
  "shoudao" | "wubi" | "japanese_nine_key" | "japanese" | "handwriting" | "thoughtful_reply";
export type TouchKeyboardSchemePreferences = { enabled: TouchKeyboardScheme[]; selected?: TouchKeyboardScheme };
const touchKeyboardSchemeOptions: [TouchKeyboardScheme, string][] = [
  ["quanpin", "全拼 26 键"], ["nine_key", "全拼 9 键"], ["xiaohe", "小鹤双拼"],
  ["ziranma", "自然码双拼"], ["microsoft", "微软双拼"], ["shoudao", "首道双拼"],
  ["wubi", "86 五笔"], ["japanese_nine_key", "日语 9 键"], ["japanese", "日语 26 键"],
  ["handwriting", "手写"], ["thoughtful_reply", "高情商回复"],
];
const allTouchKeyboardSchemes = touchKeyboardSchemeOptions.map(([scheme]) => scheme);

function inferredTouchKeyboardScheme(preferences: Preferences): TouchKeyboardScheme {
  const enabled = preferences.touch_keyboard_schemes?.enabled ?? allTouchKeyboardSchemes;
  const selected = preferences.touch_keyboard_schemes?.selected;
  if (selected && enabled.includes(selected)) return selected;
  let inferred: TouchKeyboardScheme = preferences.scheme === "shuangpin"
    ? preferences.shuangpin_profile : preferences.scheme;
  if (preferences.touch_keyboard_layout === "handwriting" && preferences.scheme === "quanpin") inferred = "handwriting";
  else if (preferences.touch_keyboard_layout === "nine_key")
    inferred = preferences.scheme === "japanese" ? "japanese_nine_key" : "nine_key";
  return enabled.includes(inferred) ? inferred : enabled[0] ?? "quanpin";
}

function selectTouchKeyboardScheme(preferences: Preferences, selected: TouchKeyboardScheme): Preferences {
  const touch_keyboard_schemes = {
    enabled: preferences.touch_keyboard_schemes?.enabled ?? allTouchKeyboardSchemes,
    selected,
  };
  if (["xiaohe", "ziranma", "microsoft", "shoudao"].includes(selected)) return {
    ...preferences, scheme: "shuangpin", last_chinese_scheme: "shuangpin",
    shuangpin_profile: selected as Preferences["shuangpin_profile"], touch_keyboard_layout: "twenty_six_key",
    touch_keyboard_schemes,
  };
  if (selected === "japanese" || selected === "japanese_nine_key") return {
    ...preferences, scheme: "japanese",
    last_chinese_scheme: preferences.scheme === "japanese" ? preferences.last_chinese_scheme : preferences.scheme,
    touch_keyboard_layout: selected === "japanese_nine_key" ? "nine_key" : "twenty_six_key",
    touch_keyboard_schemes,
  };
  if (selected === "wubi") return {
    ...preferences, scheme: "wubi", last_chinese_scheme: "wubi", touch_keyboard_layout: "twenty_six_key",
    touch_keyboard_schemes,
  };
  return {
    ...preferences, scheme: "quanpin", last_chinese_scheme: "quanpin",
    touch_keyboard_layout: selected === "nine_key" ? "nine_key"
      : selected === "handwriting" ? "handwriting" : "twenty_six_key",
    touch_keyboard_schemes,
  };
}
const helpcodeSchemas: [HelpcodeSchema, string][] = [["lantian", "蓝天小雨点"], ["ziranma", "自然码"], ["shouyou2_0", "首右2.0"], ["shouyouplus", "首右plus"], ["xiaohe", "小鹤"]];
const pages = [
  { id: "home", title: "首页", icon: new URL("./assets/msime.svg", import.meta.url).href },
  { id: "account", title: "我的", icon: new URL("./assets/account.svg", import.meta.url).href },
  { id: "chat", title: "AI 对话", icon: new URL("./assets/help.svg", import.meta.url).href },
  { id: "community", title: "社区", icon: new URL("./assets/community.svg", import.meta.url).href },
  { id: "appearance", title: "外观", icon: new URL("./assets/appearance.svg", import.meta.url).href },
  { id: "input", title: "输入", icon: new URL("./assets/input.svg", import.meta.url).href },
  { id: "typing-statistics", title: "打字统计", icon: new URL("./assets/statistics.svg", import.meta.url).href },
  { id: "helpcode", title: "辅助码", icon: new URL("./assets/helpcode.svg", import.meta.url).href },
  { id: "shortcuts", title: "快捷键", icon: new URL("./assets/shortcut.svg", import.meta.url).href },
  { id: "dictionary", title: "词库", icon: new URL("./assets/dictionary.svg", import.meta.url).href },
  { id: "skin", title: "皮肤", icon: new URL("./assets/skin.svg", import.meta.url).href },
  { id: "screen-keyboard", title: "屏幕键盘", icon: new URL("./assets/screen-keyboard.svg", import.meta.url).href },
  { id: "handwriting", title: "手写识别板", icon: new URL("./assets/handwriting.svg", import.meta.url).href },
  { id: "voice", title: "语音输入", icon: new URL("./assets/handwriting.svg", import.meta.url).href },
  { id: "ai", title: "AI 辅助", icon: new URL("./assets/help.svg", import.meta.url).href },
  { id: "tools", title: "实用功能", icon: new URL("./assets/utilities.svg", import.meta.url).href },
  { id: "floating-toolbar", title: "悬浮工具栏", icon: new URL("./assets/floating-toolbar.svg", import.meta.url).href },
  { id: "help", title: "帮助", icon: new URL("./assets/help.svg", import.meta.url).href },
  { id: "about", title: "关于", icon: new URL("./assets/about.svg", import.meta.url).href },
  { id: "feedback", title: "反馈", icon: new URL("./assets/feedback.svg", import.meta.url).href },
] as const;
const logo = new URL("./assets/msime.svg", import.meta.url).href;
const windowIcons = {
  minimize: new URL("./assets/minimize.svg", import.meta.url).href,
  maximize: new URL("./assets/maximize.svg", import.meta.url).href,
  restore: new URL("./assets/restore.svg", import.meta.url).href,
  close: new URL("./assets/close.svg", import.meta.url).href,
};
const appVersion = "0.1.0";
const releasesPageUrl = "https://github.com/metasequoiaime/MSIME-Windows/releases";
const linuxReleasesPageUrl = "https://github.com/metasequoiaime/MSIME-Client/releases";
const updateManifestUrl = "https://msime.app/update.json";
const licenseUrl = "https://github.com/metasequoiaime/MSIME-Windows/blob/main/LICENSE";
const privacyUrl = "https://github.com/metasequoiaime/MSIME-Windows/blob/main/PRIVACY.md";
const androidPrivacyUrl = "https://msime.app/privacy/";
const linuxLicenseUrl = "https://github.com/metasequoiaime/MSIME-Client/blob/main/LICENSE";
const linuxIssuesUrl = "https://github.com/metasequoiaime/MSIME-Client/issues";

export type HostPlatform = "windows" | "macos" | "linux" | "android" | "ios";
/** Mirrors `client-core::host_surface::HostCapabilities`. */
export interface HostCapabilities {
  platform: HostPlatform;
  restart_input_method: boolean;
  panel_windows: boolean;
  ime_mode_scope: boolean;
  typing_statistics: boolean;
  fuzzy_pinyin: boolean;
  system_fonts: boolean;
  window_chrome: boolean;
  floating_toolbar: boolean;
  floating_toolbar_appearance: boolean;
  mode_switch_shortcuts: boolean;
  panel_shortcuts: boolean;
  voice_capture_devices: boolean;
  candidate_font_controls: boolean;
  candidate_selection_appearance: boolean;
}

/** Superseded by the host-provided capabilities; used only when a host predates them. */
function isLinuxDesktop(): boolean {
  if (typeof navigator === "undefined") return false;
  const userAgent = navigator.userAgent;
  return /\bLinux\b/i.test(userAgent) && !/\bjsdom\b/i.test(userAgent);
}

export type ThemeMode = "dark" | "light" | "system";
export type SurfaceTheme = "follow" | "dark" | "light";
export { useCandidatePreviewTheme } from "./candidate-preview-theme";

function resolveSettingsTheme(theme: ThemeMode, surface: SurfaceTheme): "dark" | "light" {
  if (surface !== "follow") return surface;
  if (theme !== "system") return theme;
  return typeof window !== "undefined" && typeof window.matchMedia === "function" &&
    window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark";
}

export type Preferences = {
  theme?: ThemeMode;
  settings_theme?: SurfaceTheme;
  candidate_theme?: SurfaceTheme;
  toolbar_theme?: SurfaceTheme;
  screen_keyboard_theme?: SurfaceTheme;
  handwriting_theme?: SurfaceTheme;
  voice_theme?: SurfaceTheme;
  emoji_theme?: SurfaceTheme;
  ai_assistant?: AiAssistantPreferences;
  custom_translation?: { enabled: boolean; endpoint: string; api_key: string };
  tencent_tmt?: { enabled: boolean; secret_id: string; secret_key: string; region: string };
  voice_input?: VoiceInputPreferences;
  local_modes?: LocalModePreferences;
  clipboard_history?: boolean;
  cloud_candidates?: boolean;
  candidate_translations?: boolean;
  candidate_english_gloss?: boolean;
  translation_target_language?: "en" | "fr" | "ja" | "es" | "ru" | "de" | "ko";
  floating_toolbar?: FloatingToolbarPreferences;
  mixed_input?: MixedInputPreferences;
  fuzzy_pinyin?: FuzzyPinyinPreferences;
  frequency?: FrequencyPreferences;
  word_character?: { enabled: boolean; keys: "brackets" | "minus_equal" };
  navigation?: NavigationPreferences;
  keybindings?: KeybindingPreferences;
  scheme: "quanpin" | "shuangpin" | "wubi" | "japanese";
  wubi_code_hint?: boolean;
  touch_keyboard_layout?: "twenty_six_key" | "nine_key" | "handwriting";
  touch_keyboard_skin?: TouchKeyboardSkin;
  custom_touch_keyboard_skin?: TouchKeyboardSkinDesign;
  touch_keyboard_schemes?: TouchKeyboardSchemePreferences;
  touch_key_spacing_tenths?: number;
  touch_row_spacing_tenths?: number;
  touch_keyboard_height_adjustment?: number;
  touch_voice_shortcut?: boolean;
  default_ime_mode?: "chinese" | "english";
  ime_mode_scope?: "app" | "global";
  last_chinese_scheme?: "quanpin" | "shuangpin" | "wubi" | null;
  shuangpin_profile: "xiaohe" | "ziranma" | "shoudao" | "microsoft";
  candidate_page_size: number;
  candidate_font_size?: number;
  candidate_preedit_font_size?: number;
  candidate_text_color?: string | null;
  candidate_number_color?: string | null;
  candidate_accent_color?: string | null;
  candidate_selected_color?: string | null;
  candidate_hover_color?: string | null;
  candidate_surface_color?: string | null;
  candidate_border_color?: string | null;
  candidate_font_family?: string;
  candidate_fallback_fonts?: string[];
  candidate_layout?: "horizontal" | "vertical";
  /** Inline (host-drawn) preedit. Linux applies it via ClientEngine preedit_style(). */
  tsf_preedit_style?: "raw" | "pinyin" | "empty";
  candidate_preedit_style?: "pinyin" | "empty";
  candidate_skin?: string;
  learning: boolean;
  autocorrect?: boolean;
  diagnostic_log?: { server?: boolean; tsf?: boolean };
  quanpin?: {
    autocorrect_transposition?: boolean;
    autocorrect_neighbor?: boolean;
  };
  quanpin_helpcode?: HelpcodePreferences;
  shuangpin_helpcode?: HelpcodePreferences;
  chinese_punctuation: boolean;
  smart_punctuation?: boolean;
  smart_punctuation_repeat?: boolean;
  paired_punctuation?: boolean;
  punctuation_lock?: "follow" | "chinese" | "english";
  traditional_chinese_output?: boolean;
};
export type AiAssistantPreferences = {
  enabled: boolean;
  provider: string;
  model: string;
  endpoint: string;
  candidate_limit: number;
  token?: string;
  tokens?: Record<string, string>;
  prompt_id?: string;
  prompt?: string;
  prompt_custom_1: string;
  prompt_custom_2: string;
  prompt_custom_3: string;
};
export type VoiceInputPreferences = {
  enabled: boolean;
  language: string;
  capture_backend?: "" | "auto" | "pulse" | "pipewire" | "alsa";
  capture_device?: string;
  asr_provider?: string;
  asr_endpoint?: string;
  asr_token?: string;
  asr_tokens?: Record<string, string>;
  asr_app_key?: string;
  hotkey_ralt?: boolean;
  hotkey_ctrl_f9?: boolean;
  hotkey_ctrl_win?: boolean;
  hotkey_rctrl_ralt?: boolean;
  hotkey_hold_space_lock?: boolean;
  sound_enabled?: boolean;
  start_sound?: boolean;
  end_sound?: boolean;
  mute_system_audio?: boolean;
  polish_enabled?: boolean;
  polish_text?: boolean;
  asr_model?: string;
  asr_resource_id?: string;
  commit_mode?: "tsf" | "sendinput" | "ctrl_v";
  polish_provider?: string;
  polish_endpoint?: string;
  polish_token?: string;
  polish_tokens?: Record<string, string>;
  polish_model?: string;
  polish_prompt_id?: string;
  polish_prompt?: string;
  polish_prompt_custom_1?: string;
  polish_prompt_custom_2?: string;
  polish_prompt_custom_3?: string;
  stream_inline_preedit?: boolean;
  doubao_enable_itn?: boolean;
  doubao_enable_punc?: boolean;
  doubao_enable_ddc?: boolean;
  doubao_boosting_table_id?: string;
  [key: string]: unknown;
};
const defaultAiAssistant: AiAssistantPreferences = { enabled: false, provider: "deepseek", model: "deepseek-v4-flash", endpoint: "https://api.deepseek.com/chat/completions", candidate_limit: 3, token: "", tokens: {}, prompt_id: "custom_1", prompt: "请润色以下文字，保持原意，只返回修改后的文字。", prompt_custom_1: "", prompt_custom_2: "", prompt_custom_3: "" };
// asr_provider mirrors client-core's default; the two disagreeing meant a host
// wrote a provider no backend implements.
const defaultVoiceInput: VoiceInputPreferences = { enabled: true, language: "zh-CN", asr_provider: "doubao", asr_resource_id: "volc.seedasr.sauc.duration" };

export function aiCredentialOrigin(endpoint: string): string | null {
  if (!endpoint || endpoint.length > 2048 || /[\u0000-\u001f\u007f]/.test(endpoint)) return null;
  try {
    const url = new URL(endpoint.trim());
    if (url.protocol !== "https:" || !url.hostname || url.username || url.password || url.hash) return null;
    return `https://${url.hostname.toLowerCase()}:${url.port || "443"}`;
  } catch { return null; }
}
const defaultCustomTranslation = { enabled: false, endpoint: "", api_key: "" };
// Matches TencentTmtPreferences::default() in client-core.
const defaultTencentTmt = { enabled: true, secret_id: "", secret_key: "", region: "ap-guangzhou" };
export type ExternalSkinCatalog = { scanned: boolean; directory?: string; revision?: number; packages: Array<{ id: string; title: string; description?: string; valid?: boolean }> ; issues?: string[] };
export type Snapshot = { format_version: number; revision: number; preferences: Preferences; candidate_skin_catalog?: ExternalSkinCatalog };
export type LocalDictionaryKind = "pinyin" | "wubi" | "quick_phrase" | "english";
export type LocalDictionaryFormat = "standard" | "windows" | "rime" | "hans";
export type DictionaryEntry = { kind: LocalDictionaryKind; key: string; value: string; weight: number };
export type DictionaryFailure = { request_id: string; label: string; error: string };
/** Mirrors the import response from `client-core::dictionary_import`. */
export interface DictionaryImportResult {
  applied: number;
  /** Rows examined and skipped. Absent from hosts that predate the report. */
  failed?: number;
  /** Rows beyond the per-file cap were not examined. */
  truncated?: boolean;
  first_failures?: { line: number; issue: string }[];
}

/** A short account of an import the user can act on. */
export function describeImportResult(kind: string, result: DictionaryImportResult): string {
  const parts = [`${kind}导入完成，共 ${result.applied} 条。`];
  if (result.failed) {
    const failures = result.first_failures ?? [];
    const lines = failures.map(failure => failure.line).join("、");
    parts.push(lines
      ? `跳过 ${result.failed} 行，首先出现在第 ${lines} 行。`
      : `跳过 ${result.failed} 行。`);
    // "rejected" means the row parsed but the engine refused it, which is a
    // different thing for the user to fix than a malformed line.
    if (failures.some(failure => failure.issue === "rejected")) {
      parts.push("其中部分行的编码与词不匹配，例如简拼、或音节数与汉字数不一致。");
    }
  }
  if (result.truncated) parts.push("文件过长，仅导入了前一部分。");
  return parts.join("");
}

export interface DictionaryClient {
  list(offset: number, limit: number): Promise<{ entries: DictionaryEntry[]; has_more: boolean; pending_count?: number; failed_requests?: DictionaryFailure[]; snapshot_error?: string | null; page_offset?: number; requested_page_offset?: number }>;
  edit(previous: DictionaryEntry | null, replacement: DictionaryEntry | null, request_id: string): Promise<void>;
  import?(kind: LocalDictionaryKind, format: LocalDictionaryFormat, text: string, request_id: string): Promise<DictionaryImportResult>;
  importPersonal?(text: string, request_id: string): Promise<{ queued: boolean; pending_count: number }>;
  export?(kind: LocalDictionaryKind, format: Exclude<LocalDictionaryFormat, "rime" | "hans">, offset: number, limit: number): Promise<{ text: string; has_more: boolean }>;
  retry?(request_id: string): Promise<void>;
  dismissFailure?(request_id: string): Promise<void>;
}
export type LocalModePreferences = { unicode: boolean; date_time: boolean; quick_phrase: boolean; emoji: boolean; kaomoji: boolean; super_jianpin: boolean; temporary_english: boolean; temporary_japanese: boolean };
const defaultLocalModes: LocalModePreferences = { unicode: true, date_time: true, quick_phrase: true, emoji: true, kaomoji: true, super_jianpin: true, temporary_english: true, temporary_japanese: true };
const localModeRows = [
  ["quick_phrase", "快捷短语(K 模式)", "中文模式下按 Shift+K，再输入编码即可调用快捷短语"],
  ["date_time", "日期与时间快捷输入(T 模式)", "中文模式下按 Shift+T，再输入 rq / riqi / date 输入日期，sj / shijian / time 输入时间，xq / xingqi / week 输入星期"],
  ["unicode", "Unicode 便捷录入(U 模式)", "中文模式下按 Shift+U，再输入十六进制码位（如 4e00 / +1f600）。空格上屏；Shift+数字选词"],
  ["emoji", "Emoji 快捷输入(E 模式)", "中文模式下按 Shift+E，再输入全拼 / 简拼 / 双拼 / 英文关键词。空格上屏；数字选词"],
  ["kaomoji", "颜文字快捷输入(M 模式)", "中文模式下按 Shift+M，再输入全拼 / 简拼 / 双拼 / 英文关键词。空格上屏；数字选词"],
  ["super_jianpin", "超级简拼(J 模式)", "中文模式下按 Shift+J，每个字母作为简拼；双拼按当前方案转换声母。空格上屏；数字选词"],
  ["temporary_english", "临时英文(Y 模式)", "中文模式下按 Shift+Y，之后按英文处理。空格上屏当前输入；数字选词；上屏后回到中文"],
  ["temporary_japanese", "临时日语(R 模式)", "中文模式下按 Shift+R，之后按日语罗马字处理。空格上屏首选；数字选词；上屏后回到中文"],
] as const;
const localDictionaryKinds: [LocalDictionaryKind, string][] = [
  ["pinyin", "全拼"],
  ["wubi", "五笔"],
  ["english", "英文"],
  ["quick_phrase", "快捷短语"],
];

/** The user-facing name of a local dictionary, for messages about it. */
/** Prefer the host's reason; fall back to the generic format hint. */
/**
 * Turn a dictionary command failure into something the user can act on.
 *
 * The host distinguishes several reasons and the desktop bridge now forwards
 * them as codes. Printing one fixed "请稍后重试" for all of them told a user
 * whose IME was simply locked by another process to retry forever.
 */
export function dictionaryErrorMessage(error: unknown, fallback: string): string {
  const code = typeof error === "object" && error !== null && "code" in error
    ? String((error as { code: unknown }).code)
    : "";
  switch (code) {
    case "dictionary_busy":
      return "词库正在被输入法占用，请关闭正在使用输入法的程序后重试。";
    case "dictionary_import_rejected":
      return "词库拒绝了这次写入，请检查编码与词是否匹配。";
    case "dictionary_read_rejected":
      return "词库拒绝了这次读取，请稍后重试。";
    case "dictionary_pinyin_unavailable":
      return "拼音表不可用，无法校验这条词的读音。";
    case "dictionary_unavailable":
      return "无法打开用户词库，请检查输入法是否正在运行。";
    default:
      return fallback;
  }
}

function importFailureMessage(kind: string, error: unknown): string {
  const reason = error instanceof Error ? error.message
    : typeof error === "string" ? error
    : typeof error === "object" && error !== null && "error" in error ? String((error as { error: unknown }).error)
    : "";
  // A host code is more specific than a free-text reason, so try it first.
  const coded = dictionaryErrorMessage(error, "");
  if (coded) return `${kind}导入失败：${coded}`;
  return reason
    ? `${kind}导入失败：${reason}`
    : `${kind}导入失败，请检查文本格式。`;
}

/** The shipped export filenames, one per dictionary kind. */
export function dictionaryExportName(kind: LocalDictionaryKind): string {
  const names: Record<LocalDictionaryKind, string> = {
    pinyin: "水杉IME-拼音用户词库.txt",
    wubi: "水杉IME-五笔用户词库.txt",
    english: "水杉IME-英文用户词库.txt",
    quick_phrase: "水杉IME-快捷短语用户词库.txt",
  };
  return names[kind];
}
/**
 * Prepare the export payload.
 *
 * Two things the plain Blob did not do. A UTF-8 BOM, because Notepad and Excel
 * on a GBK-default Windows render the Chinese as mojibake without one. And for
 * the pinyin book, single-character rows are dropped: those are learning
 * artefacts the engine accumulated, not words the user added, so exporting
 * them buries the real entries.
 */
export function dictionaryExportPayload(
  kind: LocalDictionaryKind,
  format: LocalDictionaryFormat,
  text: string,
): { body: string; rows: number } {
  const lines = text.split("\n").filter(line => line.trim().length > 0);
  // Windows exports put the code first; every other format puts the word first.
  const wordColumn = format === "windows" ? 1 : 0;
  const kept = kind === "pinyin"
    ? lines.filter(line => {
        const columns = line.split("\t");
        const word = columns[wordColumn]?.trim() ?? "";
        return Array.from(word).length > 1;
      })
    : lines;
  if (!kept.length) return { body: "", rows: 0 };
  return { body: "\ufeff" + kept.join("\n") + "\n", rows: kept.length };
}

function dictionaryKindLabel(kind: LocalDictionaryKind): string {
  return localDictionaryKinds.find(([value]) => value === kind)?.[1] ?? "词库";
}

export type MixedInputPreferences = { english: boolean; minimum_prefix: number; emoji: boolean; kaomoji: boolean };
const defaultMixedInput: MixedInputPreferences = { english: true, minimum_prefix: 2, emoji: false, kaomoji: false };
export type FrequencyPreferences = { mode: "disabled" | "pin" | "halve" | "linear" | "promote"; trigger_count: number; linear_step: number };
const defaultFrequency: FrequencyPreferences = { mode: "promote", trigger_count: 1, linear_step: 1 };
export type NavigationPreferences = { minus_equal: boolean; comma_period: boolean; brackets: boolean; tab: boolean; page_up_down: boolean; mouse_wheel?: boolean; arrows: boolean };
const defaultNavigation: NavigationPreferences = { minus_equal: true, comma_period: true, brackets: false, tab: true, page_up_down: true, arrows: true };
const translationLanguages: [NonNullable<Preferences["translation_target_language"]>, string][] = [["en", "英语"], ["fr", "法语"], ["ja", "日语"], ["es", "西班牙语"], ["ru", "俄语"], ["de", "德语"], ["ko", "韩语"]];
const defaultWordCharacter = { enabled: false, keys: "brackets" as const };
const navigationOptions: [keyof NavigationPreferences, string][] = [["minus_equal", "- / ="], ["comma_period", ", / ."], ["brackets", "[ / ]"], ["tab", "Shift+Tab / Tab"], ["page_up_down", "PageUp / PageDown"], ["mouse_wheel", "鼠标滚轮（候选面板支持时翻页）"], ["arrows", "上 / 下（移动候选项）"]];
const skinOptions: [NonNullable<Preferences["candidate_skin"]>, string, string][] = [
  ["fluent", "Fluent", "简洁、紧凑的默认候选窗"],
  ["wechat", "微信绿", "微信绿候选窗与悬浮工具栏"],
  ["graphite", "石墨 Graphite", "克制、平直的候选窗与悬浮工具栏"],
  ["willow_green", "杨柳青 Willow green", "柔和圆角与柳绿色整行高亮"],
];
export type FloatingToolbarPreferences = {
  enabled: boolean;
  english_mode: boolean;
  fullwidth: boolean;
  punctuation: boolean;
  character_set: boolean;
  emoji: boolean;
  screen_keyboard: boolean;
  settings: boolean;
  scale_percent: 75 | 100 | 125 | 150;
  font_size: 16 | 18 | 20 | 22 | 24 | 26 | 28;
};
const defaultFloatingToolbar: FloatingToolbarPreferences = {
  enabled: true,
  english_mode: true,
  fullwidth: true,
  punctuation: true,
  character_set: true,
  emoji: true,
  screen_keyboard: false,
  settings: true,
  scale_percent: 100,
  font_size: 24,
};
const floatingToolbarOptions: [keyof Pick<FloatingToolbarPreferences, "english_mode" | "fullwidth" | "punctuation" | "character_set" | "emoji" | "screen_keyboard" | "settings">, string][] = [
  ["english_mode", "英文输入模式"],
  ["fullwidth", "全角 / 半角"],
  ["punctuation", "中英文标点"],
  ["character_set", "简繁切换"],
  ["emoji", "表情与符号"],
  ["screen_keyboard", "屏幕键盘"],
  ["settings", "设置"],
];
const floatingToolbarScales: FloatingToolbarPreferences["scale_percent"][] = [75, 100, 125, 150];
const floatingToolbarFontSizes: FloatingToolbarPreferences["font_size"][] = [16, 18, 20, 22, 24, 26, 28];
export interface SettingsClient {
  /** What the surrounding host can do. Absent hosts fall back to user-agent detection. */
  host?: HostCapabilities;
  /** Android's platform-adapted Apple-style keyboard home surface. */
  home?: HomePageActions;
  /** Android account commands expose user/profile DTOs but never session tokens. */
  account?: AccountClient;
  /** Android account commands expose the authenticated EveryAPI chat surface. */
  chat?: ChatClient;
  /** Android community commands expose bounded public skin metadata and designs. */
  communitySkins?: CommunitySkinClient;
  /** Android community commands expose dictionaries and reply templates. */
  communityResources?: CommunityResourceClient;
  listVoiceCaptureDevices?: VoiceDeviceReader;
  listFontFamilies?: FontCatalogReader;
  scanSkinCatalog?: () => Promise<SkinCatalog>;
  readSkinImage?: SkinImageReader;
  readSkinFont?: SkinFontReader;
  readSkinToolbarCss?: (id: string) => Promise<string | null>;
  openSkinDirectory?: () => Promise<void>;
  load(): Promise<Snapshot>;
  save(revision: number, preferences: Preferences): Promise<Snapshot>;
  onPreferencesChanged?(listener: (snapshot: Snapshot) => void): Promise<() => void>;
  dictionary?: DictionaryClient;
  openExternalUrl?: (url: string) => Promise<void>;
  copyText?: (text: string) => Promise<void>;
  openScreenKeyboard?: () => Promise<void>;
  openHandwriting?: () => Promise<void>;
  openVoice?: () => Promise<void>;
  openCloudClipboard?: () => Promise<void>;
  openCloudDictionary?: () => Promise<void>;
  restartInputMethod?: () => Promise<void>;
  windowControl?: (action: "minimize" | "maximize" | "restore" | "close") => Promise<void>;
  beginWindowDrag?: () => Promise<void>;
  resizeWindow?: (edge: "n" | "s" | "e" | "w" | "ne" | "nw" | "se" | "sw") => Promise<void>;
  onWindowStateChanged?: (listener: (maximized: boolean) => void, onError?: () => void) => Promise<() => void>;
  clipboard?: {
    clear(): Promise<void>;
    list?(): Promise<string[]>;
    sync?(): Promise<string[]>;
    copy?(text: string): Promise<void>;
  };
  typingStatistics?: TypingStatisticsClient;
  /** The host exposes the shared fuzzy-pinyin settings. */
  fuzzyPinyin?: boolean;
  /** Android exposes Apple-compatible touch-keyboard scheme visibility and selection. */
  touchKeyboardSchemes?: boolean;
  /** Android exposes Apple's current custom touch-keyboard design editor and renderer. */
  customTouchKeyboardSkins?: boolean;
  /** Named custom designs use a separate bounded file, outside hot-path preferences. */
  customSkinLibrary?: CustomSkinLibraryClient;
  /** Android account-backed AI skin draw and artwork jobs. */
  aiSkins?: AiSkinClient;
  /** Android can show packaged offline English glosses without changing candidate identity. */
  candidateEnglishGloss?: boolean;
}

function message(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === "object" && error !== null && "code" in error) {
    switch (error.code) {
      case "conflict": return "设置已在其他窗口修改。请重新读取后再保存。";
      case "invalid": return "候选数量必须为 1 到 9。";
      case "frequency_invalid": return "调频触发频次和步长必须为 1 到 10。";
      case "mixed_input_invalid": return "中英混输触发字符数必须为 1 到 8。";
      case "key_conflict": return "以词定字和翻页不能使用同一组快捷键。";
      case "format": return "配置文件无法读取或版本较新，原文件已保留。";
    }
  }
  return "无法访问设置，请重试。原有设置不会被自动重置。";
}

type SettingsPageId = (typeof pages)[number]["id"];
// A host can ask for the section its menu entry names. An unknown id keeps the
// default page rather than opening an empty one.
function requestedPage(value: string | undefined): SettingsPageId {
  return pages.some(page => page.id === value) ? (value as SettingsPageId) : "appearance";
}

function personalDictionaryKindTitle(kind: PersonalDictionaryImportEntry["kind"]): string {
  return kind === "pinyin" ? "拼音" : kind === "wubi" ? "五笔" : kind === "quickPhrase" ? "快捷短语" : "英文";
}

function PersonalDictionaryImportCard({ dictionary }: { dictionary: DictionaryClient }) {
  const input = useRef<HTMLInputElement>(null);
  const [fileName, setFileName] = useState("");
  const [entries, setEntries] = useState<PersonalDictionaryImportEntry[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  const chooseFile = async (file: File | undefined) => {
    if (!file) return;
    setEntries(null);
    setFileName(file.name);
    setError("");
    setNotice("");
    setBusy(true);
    try {
      if (file.size > 1_048_576) throw new Error("文件不能超过 1 MB。");
      setEntries(parsePersonalDictionaryImport(await readDictionaryFile(file)));
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "无法读取所选文件，请重新选择。");
    } finally {
      setBusy(false);
    }
  };

  const importEntries = async () => {
    if (!entries || !dictionary.importPersonal) return;
    setBusy(true);
    setError("");
    setNotice("");
    try {
      const text = JSON.stringify({ format: "msime-personal-dictionary", version: 1, entries });
      const result = await dictionary.importPersonal(text, `ui-personal-import-${Date.now()}`);
      setNotice(`已加入本机同步队列，共 ${entries.length} 条；当前等待同步 ${result.pending_count} 条。`);
      setEntries(null);
      setFileName("");
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "导入失败，请稍后重试。");
    } finally {
      setBusy(false);
    }
  };

  const saveExample = () => {
    const blob = new Blob([personalDictionaryExample], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = "msime-personal-dictionary-example.json";
    anchor.click();
    URL.revokeObjectURL(url);
  };

  const countByKind = entries ? Array.from(new Set(entries.map(entry => entry.kind)))
    .map(kind => `${personalDictionaryKindTitle(kind)} ${entries.filter(entry => entry.kind === kind).length} 条`).join(" · ") : "";

  return <div className="section personal-dictionary-import" role="region" aria-label="个人词库文件导入">
    <div className="section-header"><span className="section-title">个人词库文件<small>导入 Apple 兼容的 JSON 词条，确认后加入 Android 键盘同步队列；文件内容不会上传。</small></span><span>
      <button type="button" className="secondary" disabled={busy} onClick={() => input.current?.click()}>选择 JSON 文件</button>{" "}
      <button type="button" className="secondary" disabled={busy} onClick={saveExample}>保存示例文件</button>
      <input ref={input} hidden type="file" aria-label="选择个人词库 JSON 文件" accept=".json,application/json" onChange={event => { void chooseFile(event.currentTarget.files?.[0]); event.currentTarget.value = ""; }} />
    </span></div>
    {busy && <p role="status">正在读取或加入同步队列…</p>}
    {fileName && entries && <div className="personal-dictionary-preview"><strong>{fileName}</strong><span>已校验 {entries.length} 条（{countByKind}），确认后逐条同步。</span>{entries.map((entry, index) => <div key={`${entry.kind}-${entry.key}-${index}`}><span>{entry.value}</span><code>{personalDictionaryKindTitle(entry.kind)} · {entry.key}</code></div>)}</div>}
    {error && <p role="alert" className="error">{error}</p>}
    {notice && <p role="status" className="notice">{notice}</p>}
    {entries && <button type="button" className="primary" disabled={busy} onClick={() => void importEntries()}>确认导入</button>}
  </div>;
}

/** Mirrors `client-core::translation::is_supported_endpoint`. */
/** Mirrors `usable_tencent_secret` in client-core: a placeholder is not a key. */
export function tencentSecretConfigured(value: string): boolean {
  const trimmed = value.trim();
  if (!trimmed) return false;
  if (trimmed.startsWith("<") && trimmed.endsWith(">")) return false;
  return !trimmed.startsWith("FAKESECRET_");
}
/**
 * Mirrors the SecretId/Region rules in `Preferences::validate`. Saving a value
 * outside them is rejected wholesale, so the user is told here instead of
 * losing the save with no explanation.
 */
export function tencentCredentialIssue(secretId: string, secretKey: string, region: string): string {
  if (secretId.length > 4096 || secretKey.length > 4096) return "凭据过长。";
  if (secretId && !/^[A-Za-z0-9_-]+$/.test(secretId)) {
    return "SecretId 只能包含字母、数字、下划线和连字符。";
  }
  // eslint-disable-next-line no-control-regex
  if (/[\u0000-\u001f\u007f]/.test(secretKey)) return "SecretKey 不能包含控制字符。";
  if (region.length > 64) return "地域过长。";
  if (region && !/^[A-Za-z0-9-]+$/.test(region)) {
    return "地域只能包含字母、数字和连字符。";
  }
  return "";
}
export function translationEndpointIssue(endpoint: string): string {
  if (!endpoint) return "请填写完整的接口地址。";
  if (endpoint.length > 2048) return "接口地址过长。";
  // eslint-disable-next-line no-control-regex
  if (/[\u0000-\u001f\u007f]/.test(endpoint)) return "接口地址不能包含控制字符。";
  if (!endpoint.startsWith("https://") && !endpoint.startsWith("http://")) {
    return "请填写以 http:// 或 https:// 开头的完整接口地址。";
  }
  return "";
}

export function SettingsPage({ client, initialPage }: { client: SettingsClient; initialPage?: string }) {
  // Hosts that report capabilities are authoritative; the user-agent probe stays
  // only so a host that predates the contract keeps its current behaviour.
  const linuxPlatform = client.host ? client.host.platform === "linux" : isLinuxDesktop();
  const androidPlatform = client.host?.platform === "android";
  // Functional controls follow what the host declares it can do. Only the prose
  // below still varies by platform name. A host that predates the contract keeps
  // the previous Linux-only behaviour.
  const host = client.host;
  const showModeScope = host ? host.ime_mode_scope : linuxPlatform;
  const showModeSwitchShortcuts = host ? host.mode_switch_shortcuts : linuxPlatform;
  const showPanelShortcuts = host ? host.panel_shortcuts : linuxPlatform;
  const showRestartInputMethod = (host ? host.restart_input_method : linuxPlatform) && client.restartInputMethod;
  // An IBus property menu has no scale, icon size or component list to apply.
  const showToolbarAppearance = host ? host.floating_toolbar_appearance : true;
  const showCandidateFontControls = host ? host.candidate_font_controls : true;
  const showCandidateSelectionAppearance = host ? host.candidate_selection_appearance : true;
  const showVoiceCaptureDevices = !androidPlatform && (host ? host.voice_capture_devices : linuxPlatform) && client.listVoiceCaptureDevices;
  const showDesktopMaintenanceShortcuts = !host || (host.platform !== "android" && host.platform !== "ios");
  const platformReleasesPageUrl = linuxPlatform || androidPlatform ? linuxReleasesPageUrl : releasesPageUrl;
  const platformLicenseUrl = linuxPlatform || androidPlatform ? linuxLicenseUrl : licenseUrl;
  const platformIssuesUrl = linuxPlatform || androidPlatform ? linuxIssuesUrl : "https://github.com/metasequoiaime/MSIME-Windows/issues";
  const [snapshot, setSnapshot] = useState<Snapshot>();
  const [draft, setDraft] = useState<Preferences>();
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [page, setPage] = useState<SettingsPageId>(() => requestedPage(initialPage ?? (client.home ? "home" : undefined)));
  const [communityMine, setCommunityMine] = useState(false);
  const [updateStatus, setUpdateStatus] = useState("");
  const [updateBusy, setUpdateBusy] = useState(false);
  const [availableUpdate, setAvailableUpdate] = useState<ValidatedUpdate | null>(null);
  const [feedbackCopied, setFeedbackCopied] = useState(false);
  const [phrases, setPhrases] = useState<DictionaryEntry[]>([]);
  const [phrasePage, setPhrasePage] = useState({ offset: 0, hasMore: false, status: "" });
  const [phraseBusy, setPhraseBusy] = useState(false);
  const [phraseError, setPhraseError] = useState("");
  const [dictionaryPendingCount, setDictionaryPendingCount] = useState(0);
  const [dictionaryFailures, setDictionaryFailures] = useState<DictionaryFailure[]>([]);
  const [dictionarySnapshotError, setDictionarySnapshotError] = useState("");
  const [phraseNotice, setPhraseNotice] = useState("");
  const [phraseSearch, setPhraseSearch] = useState("");
  const [phraseForm, setPhraseForm] = useState<{ key: string; value: string; weight: number; previous: DictionaryEntry | null } | null>(null);
  const [dictionaryKind, setDictionaryKind] = useState<LocalDictionaryKind>("quick_phrase");
  const [dictionaryFormat, setDictionaryFormat] = useState<LocalDictionaryFormat>("standard");
  const [windowMaximized, setWindowMaximized] = useState(false);
  const [skinPreviewThemes, setSkinPreviewThemes] = useState<Partial<Record<NonNullable<Preferences["candidate_skin"]>, "light" | "dark">>>({});
  const [showTouchSkinEditor, setShowTouchSkinEditor] = useState(false);
  const pendingTitlebarDrag = useRef<{ x: number; y: number; pointerId: number } | null>(null);
  useEffect(() => {
    const clear = () => { pendingTitlebarDrag.current = null; };
    window.addEventListener("blur", clear);
    return () => { clear(); window.removeEventListener("blur", clear); };
  }, [client]);
  useEffect(() => {
    let active = true; let unsubscribe: (() => void) | undefined;
    setWindowMaximized(false);
    const subscribe = client.onWindowStateChanged;
    if (subscribe) {
      void Promise.resolve().then(() => {
        if (!active) return;
        return subscribe(maximized => { if (active) setWindowMaximized(maximized); },
          () => { if (active) setError("无法读取窗口状态，请重试。"); });
      }).then(value => {
        if (active) unsubscribe = value;
        else value?.();
      }).catch(() => {
        if (active) setError("无法读取窗口状态，请重试。");
      });
    }
    return () => { active = false; unsubscribe?.(); };
  }, [client]);
  const snapshotRef = useRef(snapshot);
  const draftRef = useRef(draft);

  useEffect(() => {
    snapshotRef.current = snapshot;
    draftRef.current = draft;
  }, [snapshot, draft]);

  useEffect(() => {
    if (!client.onPreferencesChanged) return;
    let active = true;
    let unsubscribe: (() => void) | undefined;
    void client.onPreferencesChanged(value => {
      if (!active) return;
      const currentSnapshot = snapshotRef.current;
      const currentDraft = draftRef.current;
      const dirty = !!currentSnapshot && !!currentDraft &&
        JSON.stringify(currentDraft) !== JSON.stringify(currentSnapshot.preferences);
      if (dirty) {
        setNotice("设置已被其他窗口修改。请重新读取后再保存。");
        return;
      }
      setSnapshot(value);
      setDraft(value.preferences);
      setError("");
      setNotice("设置已从其他窗口更新。");
    }).then(value => {
      if (active) unsubscribe = value;
      else value();
    }).catch(() => undefined);
    return () => {
      active = false;
      unsubscribe?.();
    };
  }, [client]);

  useEffect(() => {
    let active = true;
    client.load().then(value => {
      if (active) { setSnapshot(value); setDraft(value.preferences); }
    }).catch(reason => { if (active) setError(message(reason)); })
      .finally(() => { if (active) setBusy(false); });
    return () => { active = false; };
  }, [client]);

  async function reload() {
    setBusy(true); setError(""); setNotice("");
    try {
      const value = await client.load();
      setSnapshot(value); setDraft(value.preferences);
    } catch (reason) { setError(message(reason)); }
    finally { setBusy(false); }
  }

  async function save() {
    if (!draft || !snapshot || !validCandidateFonts(draft)) return;
    setBusy(true); setError(""); setNotice("");
    try {
      const value = await client.save(snapshot.revision, draft);
      setSnapshot(value); setDraft(value.preferences); setNotice("设置已保存。");
    } catch (reason) { setError(message(reason)); }
    finally { setBusy(false); }
  }

  function resetTouchKeyboardSettings() {
    if (!draft || !window.confirm("恢复屏幕键盘的高度、间距和顶部语音入口默认值？")) return;
    const next = { ...draft };
    // Delete the optional fields instead of storing the current defaults. This keeps reset
    // forward-compatible when a host changes its fallback values.
    delete next.touch_key_spacing_tenths;
    delete next.touch_row_spacing_tenths;
    delete next.touch_keyboard_height_adjustment;
    delete next.touch_voice_shortcut;
    setDraft(next);
    setError("");
    setNotice("屏幕键盘设置已恢复默认，请点击保存设置。");
  }

  async function openExternalUrl(url: string) {
    try {
      if (client.openExternalUrl) {
        await client.openExternalUrl(url);
      } else {
        const opened = window.open(url, "_blank", "noopener,noreferrer");
        if (!opened) throw new Error("popup blocked");
      }
    } catch {
      setError("无法打开外部链接，请稍后重试。");
    }
  }

  async function checkForUpdate() {
    setUpdateBusy(true); setUpdateStatus(""); setAvailableUpdate(null);
    try {
      const response = await fetch(`${updateManifestUrl}?t=${Date.now()}`, { cache: "no-store" });
      if (!response.ok) throw new Error(`update manifest returned ${response.status}`);
      const manifest = await response.json() as UpdateManifest;
      const update = validateManifest(manifest, platformReleasesPageUrl);
      const current = parseVersion(appVersion);
      if (!update || !current) throw new Error("invalid update manifest");
      if (compareVersions(update.version, current) > 0) {
        setAvailableUpdate(update);
        setUpdateStatus(`发现新版本 v${update.version.display}`);
      } else {
        setUpdateStatus("已是最新版本");
      }
    } catch {
      setUpdateStatus("检查失败，请稍后重试");
    } finally {
      setUpdateBusy(false);
    }
  }

  async function openPanel(action: (() => Promise<void>) | undefined) {
    if (!action) {
      setError("当前宿主未接入该原生面板。");
      return;
    }
    try { await action(); }
    catch { setError("无法打开原生面板，请稍后重试。"); }
  }

  const requestId = (prefix: string) => `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  // One page per request: a real dictionary is far too large to pull into the
  // page before showing anything.
  async function loadPhrases(kind: LocalDictionaryKind = dictionaryKind, offset = 0) {
    if (!client.dictionary) return;
    setPhraseBusy(true); setPhraseError(""); setPhraseNotice("");
    setPhrasePage(current => ({ ...current, status: "查询中…" }));
    try {
      const page = await client.dictionary.list(offset, DICTIONARY_PAGE_SIZE);
      const entries = page.entries.filter(entry => entry.kind === kind);
      setPhrases(entries);
      setDictionaryPendingCount(page.pending_count ?? 0);
      setDictionaryFailures(page.failed_requests ?? []);
      setDictionarySnapshotError(page.snapshot_error ?? "");
      setPhrasePage({
        offset,
        hasMore: page.has_more && page.entries.length > 0,
        status: dictionaryPageStatus(offset, entries.length, page.has_more),
      });
    } catch {
      setPhraseError("无法读取词库。");
      setPhrasePage(current => ({ ...current, status: "查询失败，请重试" }));
    } finally {
      setPhraseBusy(false);
    }
  }
  async function removePhrase(entry: DictionaryEntry) {
    if (!client.dictionary) return;
    // Deletion is not undoable and the row is one click away from 编辑.
    if (typeof window !== "undefined" && !window.confirm(`删除词条“${entry.value}”（${entry.key}）？此操作无法撤销。`)) return;
    setPhraseBusy(true); setPhraseError(""); setPhraseNotice("");
    try {
      await client.dictionary.edit(entry, null, requestId("ui-remove"));
      // Stay on the page the user was reading; deleting the last row on a page
      // would otherwise leave them looking at an empty one.
      const remaining = phrases.length - 1;
      const offset = remaining === 0 && phrasePage.offset > 0
        ? Math.max(0, phrasePage.offset - DICTIONARY_PAGE_SIZE)
        : phrasePage.offset;
      await loadPhrases(dictionaryKind, offset);
    }
    catch (error) { setPhraseError(dictionaryErrorMessage(error, `${dictionaryKindLabel(dictionaryKind)}删除失败，请稍后重试。`)); }
    finally { setPhraseBusy(false); }
  }
  async function savePhrase() {
    if (!client.dictionary || !phraseForm) return;
    const replacement: DictionaryEntry = { kind: dictionaryKind, key: phraseForm.key.trim(), value: phraseForm.value, weight: phraseForm.weight };
    if (!replacement.key || !replacement.value) { setPhraseError("编码和短语不能为空。"); return; }
    setPhraseBusy(true); setPhraseError(""); setPhraseNotice("");
    try {
      await client.dictionary.edit(phraseForm.previous, replacement, requestId(phraseForm.previous ? "ui-edit" : "ui-add"));
      setPhraseForm(null);
      // An edit keeps the reader where they were; only a new entry returns to
      // the first page, where the shared runtime lists it.
      await loadPhrases(dictionaryKind, phraseForm.previous ? phrasePage.offset : 0);
    }
    catch (error) { setPhraseError(dictionaryErrorMessage(error, `${dictionaryKindLabel(dictionaryKind)}保存失败，请稍后重试。`)); }
    finally { setPhraseBusy(false); }
  }
  async function importPhrases(file: File) {
    if (!client.dictionary) return;
    setPhraseBusy(true); setPhraseError(""); setPhraseNotice("");
    try {
      const text = await readDictionaryFile(file);
      let imported: DictionaryImportResult | null = null;
      if (client.dictionary.import) {
        imported = await client.dictionary.import(dictionaryKind, dictionaryFormat, text, requestId("ui-import"));
      } else {
        if (dictionaryFormat === "hans") throw new Error("hans format requires batch import");
        const lines = text.split(/\r?\n/).filter(Boolean);
        for (const line of lines) {
          const [first, second, weight = "100000"] = line.split("\t");
          if (!first || !second) continue;
          const [value, key] = dictionaryFormat === "windows" ? [second, first] : [first, second];
          await client.dictionary.edit(null, { kind: dictionaryKind, key: key.trim(), value, weight: Number(weight) || 100000 }, requestId("ui-import"));
        }
      }
      await loadPhrases(dictionaryKind);
      // The host reports what it skipped; saying nothing reads as a clean import.
      if (imported) setPhraseNotice(describeImportResult(dictionaryKindLabel(dictionaryKind), imported));
    } catch (error) {
      setPhraseError(importFailureMessage(dictionaryKindLabel(dictionaryKind), error));
    }
    finally { setPhraseBusy(false); }
  }
  async function retryDictionaryFailure(requestId: string) {
    if (!client.dictionary?.retry) return;
    setPhraseBusy(true); setPhraseError("");
    try {
      await client.dictionary.retry(requestId);
      await loadPhrases(dictionaryKind, phrasePage.offset);
    } catch { setPhraseError("词条重试失败，请稍后重试。"); }
    finally { setPhraseBusy(false); }
  }
  async function dismissDictionaryFailure(requestId: string) {
    if (!client.dictionary?.dismissFailure) return;
    setPhraseBusy(true); setPhraseError("");
    try {
      await client.dictionary.dismissFailure(requestId);
      await loadPhrases(dictionaryKind, phrasePage.offset);
    } catch { setPhraseError("移除失败记录失败，请稍后重试。"); }
    finally { setPhraseBusy(false); }
  }
  async function exportPhrases() {
    if (!client.dictionary) return;
    if (dictionaryFormat === "hans") { setPhraseError("汉字自动注音格式仅支持导入。"); return; }
    setPhraseBusy(true); setPhraseError(""); setPhraseNotice("");
    try {
      let text = "";
      if (client.dictionary.export) {
        let offset = 0;
        let hasMore = true;
        while (hasMore && offset <= 1000000) {
          const page = await client.dictionary.export(dictionaryKind, dictionaryFormat === "rime" ? "standard" : dictionaryFormat, offset, 1000);
          text += page.text;
          const count = page.text ? page.text.trimEnd().split("\n").length : 0;
          offset += count;
          hasMore = page.has_more && count > 0;
        }
      } else {
        text = phrases.map(entry => dictionaryFormat === "windows"
          ? `${entry.key}\t${entry.value}\t${entry.weight}`
          : `${entry.value}\t${entry.key}\t${entry.weight}`).join("\n");
      }
      const payload = dictionaryExportPayload(dictionaryKind, dictionaryFormat, text);
      if (!payload.rows) { setPhraseError("当前没有可导出的用户新增词条。"); return; }
      const url = URL.createObjectURL(new Blob([payload.body], { type: "text/plain;charset=utf-8" }));
      const anchor = document.createElement("a"); anchor.href = url; anchor.download = dictionaryExportName(dictionaryKind); anchor.click(); URL.revokeObjectURL(url);
      setPhraseNotice(`已导出 ${payload.rows} 条用户词条。`);
    } catch (error) { setPhraseError(dictionaryErrorMessage(error, "词库导出失败，请稍后重试。")); }
    finally { setPhraseBusy(false); }
  }

  const dirty = !!draft && !!snapshot && JSON.stringify(draft) !== JSON.stringify(snapshot.preferences);
  const ai = draft?.ai_assistant ?? defaultAiAssistant;
  const aiOrigin = aiCredentialOrigin(ai.endpoint);
  const aiToken = aiOrigin ? ai.tokens?.[aiOrigin] ?? "" : "";
  const updateAi = (patch: Partial<AiAssistantPreferences>) => {
    if (draft) setDraft({ ...draft, ai_assistant: { ...ai, ...patch } });
  };
  const updateAiToken = (value: string) => {
    if (aiOrigin) updateAi({ token: "", tokens: { ...(ai.tokens ?? {}), [aiOrigin]: value } });
  };
  const wordCharacter = draft?.word_character ?? defaultWordCharacter;
  const keybindings = draft?.keybindings ?? defaultKeybindings;
  const frequency = draft?.frequency ?? defaultFrequency;
  const mixedInput = draft?.mixed_input ?? defaultMixedInput;
  const fuzzyPinyin = draft?.fuzzy_pinyin ?? defaultFuzzyPinyin;
  const touchKeyboardSchemes = draft?.touch_keyboard_schemes ?? { enabled: allTouchKeyboardSchemes };
  const selectedTouchKeyboardScheme = draft ? inferredTouchKeyboardScheme(draft) : "quanpin";
  const setTouchKeyboardSchemeEnabled = (scheme: TouchKeyboardScheme, enabled: boolean) => {
    if (!draft) return;
    const visible = new Set(touchKeyboardSchemes.enabled);
    if (enabled) visible.add(scheme); else visible.delete(scheme);
    if (visible.size === 0) return;
    const ordered = allTouchKeyboardSchemes.filter(value => visible.has(value));
    const selected = visible.has(selectedTouchKeyboardScheme) ? selectedTouchKeyboardScheme : ordered[0];
    const next = selectTouchKeyboardScheme(draft, selected);
    setDraft({ ...next, touch_keyboard_schemes: { enabled: ordered, selected } });
  };
  const selectHomeScheme = (scheme: TouchKeyboardScheme) => {
    if (!draft) return;
    const visible = new Set(touchKeyboardSchemes.enabled);
    visible.add(scheme);
    const enabled = allTouchKeyboardSchemes.filter(value => visible.has(value));
    const next = selectTouchKeyboardScheme(draft, scheme);
    setDraft({ ...next, touch_keyboard_schemes: { enabled, selected: scheme } });
  };
  const localModes = draft?.local_modes ?? defaultLocalModes;
  const quanpinAutocorrect = {
    autocorrect_transposition: draft?.quanpin?.autocorrect_transposition ?? draft?.autocorrect ?? true,
    autocorrect_neighbor: draft?.quanpin?.autocorrect_neighbor ?? draft?.autocorrect ?? true,
  };
  const clipboardHistory = draft?.clipboard_history ?? false;
  const diagnosticLog = { server: draft?.diagnostic_log?.server ?? false, tsf: draft?.diagnostic_log?.tsf ?? false };
  const cloudCandidates = draft?.cloud_candidates ?? true;
  const candidateTranslations = draft?.candidate_translations ?? true;
  const candidateEnglishGloss = draft?.candidate_english_gloss ?? false;
  const translationTargetLanguage = draft?.translation_target_language ?? "en";
  const voiceInput = { ...defaultVoiceInput, ...(draft?.voice_input ?? {}) };
  const updateVoice = (patch: Partial<VoiceInputPreferences>) => {
    if (draft) setDraft({ ...draft, voice_input: { ...voiceInput, ...patch } });
  };
  const customTranslation = draft?.custom_translation ?? defaultCustomTranslation;
  const tencentTmt = draft?.tencent_tmt ?? defaultTencentTmt;
  // Which prompt slot the 润色方案 select is on, and the text that slot means.
  // A preset resolves to its shipped prompt; a custom slot to whatever the user
  // stored in it. Selecting a preset used to change an id with nothing behind
  // it, leaving the textarea showing something unrelated.
  const polishSlot = normalizePolishSlot(voiceInput.polish_prompt_id);
  const polishSlotField = (slot: string): string | undefined =>
    isPolishCustomSlot(slot) ? `polish_prompt_${normalizePolishSlot(slot)}` : undefined;
  const polishPromptFor = (slot: string, current: VoiceInputPreferences): string => {
    const field = polishSlotField(slot);
    if (!field) return polishPresetPrompt(slot);
    return (current as Record<string, unknown>)[field] as string ?? "";
  };
  const smartPunctuation = draft?.smart_punctuation ?? true;
  const smartPunctuationRepeat = draft?.smart_punctuation_repeat ?? true;
  const pairedPunctuation = draft?.paired_punctuation ?? true;
  const punctuationLock = draft?.punctuation_lock ?? "follow";
  const floatingToolbar = { ...defaultFloatingToolbar, ...(draft?.floating_toolbar ?? {}) };
  const themeMode = draft?.theme ?? "dark";
  const settingsTheme = draft?.settings_theme ?? "follow";
  const candidatePreviewTheme = useCandidatePreviewTheme(themeMode, draft?.candidate_theme);
  const toolbarPreviewTheme = useCandidatePreviewTheme(themeMode, draft?.toolbar_theme);
  const keyboardPreviewTheme = useCandidatePreviewTheme(themeMode, draft?.screen_keyboard_theme);
  const touchKeyboardSkin = draft?.touch_keyboard_skin ?? "forest";
  const customTouchKeyboardSkin = draft?.custom_touch_keyboard_skin ?? defaultTouchKeyboardSkinDesign;
  useEffect(() => setSkinPreviewThemes({}), [candidatePreviewTheme]);
  const touchKeySpacingTenths = draft?.touch_key_spacing_tenths ?? 60;
  const touchRowSpacingTenths = draft?.touch_row_spacing_tenths ?? 70;
  const touchKeyboardHeightAdjustment = draft?.touch_keyboard_height_adjustment ?? 0;
  const installerTrust = availableUpdate ? describeInstallerTrust(availableUpdate) : null;
  const [clipboardEntries, setClipboardEntries] = useState<string[]>([]);
  const availablePages = pages.filter(item =>
    (item.id !== "home" || Boolean(client.home))
    &&
    (item.id !== "typing-statistics" || Boolean(client.typingStatistics))
    && (item.id !== "account" || Boolean(client.account))
    && (item.id !== "chat" || Boolean(client.chat))
    && (item.id !== "community" || Boolean(client.communitySkins || client.communityResources))
    && (item.id !== "floating-toolbar" || (host ? host.floating_toolbar : true)));
  useEffect(() => {
    if (!availablePages.some(item => item.id === page)) setPage("appearance");
  }, [availablePages, page]);
  useEffect(() => {
    if (typeof document === "undefined") return;
    const apply = () => {
      document.documentElement.dataset.theme = resolveSettingsTheme(themeMode, settingsTheme);
    };
    apply();
    if (themeMode !== "system" || settingsTheme !== "follow" ||
        typeof window === "undefined" || typeof window.matchMedia !== "function") return;
    const media = window.matchMedia("(prefers-color-scheme: light)");
    const listener = () => apply();
    if (typeof media.addEventListener === "function") {
      media.addEventListener("change", listener);
      return () => media.removeEventListener("change", listener);
    }
    media.addListener(listener);
    return () => media.removeListener(listener);
  }, [settingsTheme, themeMode]);
  useEffect(() => {
    let active = true;
    if (!snapshot?.preferences.clipboard_history) { setClipboardEntries([]); return; }
    if (!client.clipboard?.list) return;
    void client.clipboard.list().then(entries => { if (active) setClipboardEntries(entries); }).catch(() => undefined);
    return () => { active = false; };
  }, [client, page, snapshot?.revision]);
  return <div className="settings-shell" onPointerDownCapture={event => {
    pendingTitlebarDrag.current = null;
    if (!client.resizeWindow || event.button !== 0 || windowMaximized) return;
    const rect = event.currentTarget.getBoundingClientRect(); const edge = 8;
    const n = event.clientY - rect.top < edge, s = rect.bottom - event.clientY < edge;
    const w = event.clientX - rect.left < edge, e = rect.right - event.clientX < edge;
    const value = n && e ? "ne" : n && w ? "nw" : s && e ? "se" : s && w ? "sw" : n ? "n" : s ? "s" : e ? "e" : w ? "w" : null;
    if (value) {
      event.preventDefault();
      event.stopPropagation();
      void client.resizeWindow(value).catch(() => setError("无法调整窗口大小，请重试。"));
    }
  }}>
    {(client.windowControl || client.beginWindowDrag) && <header className="window-titlebar" aria-label="窗口控制"
      onDoubleClick={event => {
        pendingTitlebarDrag.current = null;
        if (event.button !== 0 || !client.windowControl) return;
        const rect = event.currentTarget.parentElement!.getBoundingClientRect();
        if (!windowMaximized && client.resizeWindow &&
          (event.clientX - rect.left < 8 || rect.right - event.clientX < 8 ||
           event.clientY - rect.top < 8 || rect.bottom - event.clientY < 8)) return;
        void client.windowControl(windowMaximized ? "restore" : "maximize");
      }}
      onPointerDown={event => {
        if (event.button === 0 && event.detail < 2 && client.beginWindowDrag)
          pendingTitlebarDrag.current = { x: event.clientX, y: event.clientY, pointerId: event.pointerId };
      }}
      onPointerMove={event => {
        const pending = pendingTitlebarDrag.current;
        if (!pending || pending.pointerId !== event.pointerId) return;
        if (event.buttons !== 1) { pendingTitlebarDrag.current = null; return; }
        if (Math.abs(event.clientX - pending.x) + Math.abs(event.clientY - pending.y) < 2) return;
        pendingTitlebarDrag.current = null;
        // Invoke during the gesture; catch synchronous and asynchronous host failures.
        void (async () => {
          try { await client.beginWindowDrag?.(); }
          catch { setError("无法移动窗口，请重试。"); }
        })();
      }}
      onPointerUp={() => { pendingTitlebarDrag.current = null; }}
      onPointerCancel={() => { pendingTitlebarDrag.current = null; }}
      onPointerLeave={() => { pendingTitlebarDrag.current = null; }}>
      <span className="window-title">水杉 IME</span>{client.windowControl && <span className="window-controls"
        onPointerDown={event => event.stopPropagation()}
        onDoubleClick={event => event.stopPropagation()}>
        <button type="button" aria-label="最小化" onClick={() => void client.windowControl!("minimize")}>
          <img className="window-icon" src={windowIcons.minimize} alt="" draggable={false} />
        </button>
        <button type="button" aria-label={windowMaximized ? "还原" : "最大化"} onClick={() => void client.windowControl!(windowMaximized ? "restore" : "maximize")}>
          <img className="window-icon" src={windowMaximized ? windowIcons.restore : windowIcons.maximize} alt="" draggable={false} />
        </button>
        <button type="button" className="window-close" aria-label="关闭" onClick={() => void client.windowControl!("close")}>
          <img className="window-icon" src={windowIcons.close} alt="" draggable={false} />
        </button>
      </span>}
    </header>}
    <div className="settings-body">
    <nav className="sidebar" aria-label="设置分类">
      <div className="sidebar-header"><img src={logo} alt="" /><span>水杉 IME</span></div>
      {availablePages.map(item => <button key={item.id} type="button" className={`item${page === item.id ? " active" : ""}`}
        aria-current={page === item.id ? "page" : undefined} aria-controls="settings-content" onClick={() => { setPage(item.id); if (item.id === "community") setCommunityMine(false); }}>
        <span className="icon"><img src={item.icon} alt="" /></span>{item.title}
      </button>)}
      <p className="preview-label">客户端预览版</p>
    </nav>
    <main id="settings-content" aria-labelledby="page-title"><div className="content">
    <header className="content-header"><h1 id="page-title">{availablePages.find(item => item.id === page)?.title ?? "外观"}</h1></header>
    {error && <p role="alert" className="error">{error}</p>}
    {notice && <p role="status" className="notice">{notice}</p>}
    {busy && !draft && <p role="status">正在读取设置…</p>}
    {client.home && draft && page === "home" && <HomePage preferences={draft} actions={client.home} onOpenPage={value => setPage(value as SettingsPageId)} onSelectScheme={selectHomeScheme} onOpenChat={client.chat ? () => setPage("chat") : undefined} />}
    {client.account && page === "account" && <AccountPage client={client.account} onOpenPublishedSkins={() => { setCommunityMine(true); setPage("community"); }} />}
    {client.chat && page === "chat" && <ChatPage client={client.chat} onLogin={() => setPage("account")} />}
    {client.communitySkins && client.communityResources && page === "community" && <CommunityHomePage key={communityMine ? "mine" : "all"} skins={client.communitySkins} resources={client.communityResources} theme={keyboardPreviewTheme} initialMine={communityMine} localDictionary={client.dictionary} />}
    {client.communitySkins && !client.communityResources && page === "community" && <CommunitySkinsPage key={communityMine ? "mine" : "all"} client={client.communitySkins} theme={keyboardPreviewTheme} localSkinLibrary={client.customSkinLibrary} initialMine={communityMine} />}
    {!client.communitySkins && client.communityResources && page === "community" && <CommunityResourcesPage client={client.communityResources} kind="dictionary" />}
    {client.typingStatistics && page === "typing-statistics" && <TypingStatisticsPage client={client.typingStatistics} />}
    {draft && page !== "typing-statistics" && page !== "account" && page !== "chat" && page !== "community" && <form onSubmit={event => { event.preventDefault(); void save(); }}>
      <fieldset disabled={busy} hidden={page !== "appearance"} aria-label="外观">
        <AppearanceCandidatePreview preferences={draft} scan={client.scanSkinCatalog} readImage={client.readSkinImage} active={page === "appearance"} revision={snapshot?.revision ?? 0} />
        <div className="section"><label className="section-header"><span className="section-title">工具栏主题<small>覆盖全局主题；当前影响工具栏设置预览，原生工具栏需宿主支持</small></span><select aria-label="工具栏主题" value={draft.toolbar_theme ?? "follow"} onChange={event => setDraft({ ...draft, toolbar_theme: event.target.value as SurfaceTheme })}><option value="follow">跟随全局</option><option value="dark">深色</option><option value="light">浅色</option></select></label></div>
        <div className="section"><label className="section-header"><span className="section-title">手写面板主题<small>覆盖手写识别板的明暗外观</small></span><select aria-label="手写面板主题" value={draft.handwriting_theme ?? "follow"} onChange={event => setDraft({ ...draft, handwriting_theme: event.target.value as SurfaceTheme })}><option value="follow">跟随全局</option><option value="dark">深色</option><option value="light">浅色</option></select></label></div>
        {!androidPlatform && <div className="section"><label className="section-header"><span className="section-title">语音面板主题<small>覆盖语音输入面板的明暗外观</small></span><select aria-label="语音面板主题" value={draft.voice_theme ?? "follow"} onChange={event => setDraft({ ...draft, voice_theme: event.target.value as SurfaceTheme })}><option value="follow">跟随全局</option><option value="dark">深色</option><option value="light">浅色</option></select></label></div>}
        <div className="section"><label className="section-header"><span className="section-title">Emoji 面板主题<small>覆盖 Emoji、颜文字和符号面板的明暗外观</small></span><select aria-label="Emoji 面板主题" value={draft.emoji_theme ?? "follow"} onChange={event => setDraft({ ...draft, emoji_theme: event.target.value as SurfaceTheme })}><option value="follow">跟随全局</option><option value="dark">深色</option><option value="light">浅色</option></select></label></div>
        {showCandidateFontControls ? <CandidateFontControls value={draft} onChange={patch => setDraft({ ...draft, ...patch })} readFonts={client.listFontFamilies} /> : <div className="section"><small>当前宿主的候选面板不支持自定义字体或字号。</small></div>}
        <div className="section"><label className="section-header"><span className="section-title">全局主题<small>设置窗口和各界面的默认明暗模式</small></span><select aria-label="全局主题" value={themeMode} onChange={event => setDraft({ ...draft, theme: event.target.value as ThemeMode })}><option value="dark">深色</option><option value="light">浅色</option><option value="system">跟随系统</option></select></label></div>
        <div className="section"><label className="section-header"><span className="section-title">设置窗口主题<small>覆盖全局主题，仅影响当前设置窗口</small></span><select aria-label="设置窗口主题" value={settingsTheme} onChange={event => setDraft({ ...draft, settings_theme: event.target.value as SurfaceTheme })}><option value="follow">跟随全局</option><option value="dark">深色</option><option value="light">浅色</option></select></label></div>
        <div className="section"><label className="section-header"><span className="section-title">候选窗主题<small>预览跟随全局主题；Linux IBus panel 支持时使用，跟随时由桌面主题决定</small></span><select aria-label="候选窗主题" value={draft.candidate_theme ?? "follow"} onChange={event => setDraft({ ...draft, candidate_theme: event.target.value as SurfaceTheme })}><option value="follow">跟随</option><option value="dark">深色</option><option value="light">浅色</option></select></label></div>
        <div className="section"><label className="section-header"><span className="section-title">候选布局</span><select aria-label="候选布局" value={draft.candidate_layout ?? "vertical"} onChange={event => setDraft({ ...draft, candidate_layout: event.target.value as Preferences["candidate_layout"] })}>
          <option value="vertical">竖排</option><option value="horizontal">横排</option>
        </select></label></div>
        {showCandidateFontControls && <div className="section"><label className="section-header"><span className="section-title">候选字号</span><select aria-label="候选字号" value={candidateFontSize(draft.candidate_font_size)} onChange={event => setDraft({ ...draft, candidate_font_size: Number(event.target.value) })}>
          {candidateFontSizes.map(size => <option key={size} value={size}>{size}</option>)}
        </select></label></div>}
        {showCandidateFontControls && <div className="section"><label className="section-header"><span className="section-title">候选窗预编辑字号</span><select aria-label="候选窗预编辑字号" value={candidateFontSize(draft.candidate_preedit_font_size)} onChange={event => setDraft({ ...draft, candidate_preedit_font_size: Number(event.target.value) })}>
          {candidateFontSizes.map(size => <option key={size} value={size}>{size}</option>)}
        </select></label></div>}
        <div className="section"><div className="section-header"><span className="section-title">候选文字颜色</span><div className="candidate-color-control">
          <input aria-label="候选文字颜色" type="color" value={candidateTextColor(draft.candidate_text_color) ?? (candidatePreviewTheme === "light" ? "#1a1a1a" : "#e9e8e8")} onChange={event => setDraft({ ...draft, candidate_text_color: event.target.value })} />
          <button type="button" className={`candidate-color-reset${candidateTextColor(draft.candidate_text_color) ? "" : " is-active"}`} aria-pressed={!candidateTextColor(draft.candidate_text_color)} onClick={() => { if (candidateTextColor(draft.candidate_text_color)) setDraft({ ...draft, candidate_text_color: null }); }}>跟随主题</button>
        </div></div></div>
        {!showCandidateSelectionAppearance && <div className="section"><small>当前宿主的候选面板不支持强调、选中、悬停或边框颜色。</small></div>}
        {showCandidateSelectionAppearance && <div className="section"><div className="section-header"><span className="section-title">候选强调色</span><div className="candidate-color-control">
          <input aria-label="候选强调色" type="color" value={candidateTextColor(draft.candidate_accent_color) ?? (candidatePreviewTheme === "light" ? "#1a73e8" : "#8ab4f8")} onChange={event => setDraft({ ...draft, candidate_accent_color: event.target.value })} />
          <button type="button" className={`candidate-color-reset${candidateTextColor(draft.candidate_accent_color) ? "" : " is-active"}`} aria-pressed={!candidateTextColor(draft.candidate_accent_color)} onClick={() => { if (candidateTextColor(draft.candidate_accent_color)) setDraft({ ...draft, candidate_accent_color: null }); }}>跟随主题</button>
        </div></div></div>}
        {showCandidateSelectionAppearance && <div className="section"><div className="section-header"><span className="section-title">候选选中色</span><div className="candidate-color-control">
          <input aria-label="候选选中色" type="color" value={candidateTextColor(draft.candidate_selected_color) ?? (candidatePreviewTheme === "light" ? "#e8e8e8" : "#3e3e3e")} onChange={event => setDraft({ ...draft, candidate_selected_color: event.target.value })} />
          <button type="button" className={`candidate-color-reset${candidateTextColor(draft.candidate_selected_color) ? "" : " is-active"}`} aria-pressed={!candidateTextColor(draft.candidate_selected_color)} onClick={() => { if (candidateTextColor(draft.candidate_selected_color)) setDraft({ ...draft, candidate_selected_color: null }); }}>跟随主题</button>
        </div></div></div>}
        {showCandidateSelectionAppearance && <div className="section"><div className="section-header"><span className="section-title">候选悬停色</span><div className="candidate-color-control">
          <input aria-label="候选悬停色" type="color" value={candidateTextColor(draft.candidate_hover_color) ?? (candidatePreviewTheme === "light" ? "#ececec" : "#414141")} onChange={event => setDraft({ ...draft, candidate_hover_color: event.target.value })} />
          <button type="button" className={`candidate-color-reset${candidateTextColor(draft.candidate_hover_color) ? "" : " is-active"}`} aria-pressed={!candidateTextColor(draft.candidate_hover_color)} onClick={() => { if (candidateTextColor(draft.candidate_hover_color)) setDraft({ ...draft, candidate_hover_color: null }); }}>跟随主题</button>
        </div></div></div>}
        <div className="section"><div className="section-header"><span className="section-title">候选表面色</span><div className="candidate-color-control"><input aria-label="候选表面色" type="color" value={candidateTextColor(draft.candidate_surface_color) ?? (candidatePreviewTheme === "light" ? "#ffffff" : "#202020")} onChange={event => setDraft({ ...draft, candidate_surface_color: event.target.value })} /><button type="button" className={`candidate-color-reset${candidateTextColor(draft.candidate_surface_color) ? "" : " is-active"}`} onClick={() => setDraft({ ...draft, candidate_surface_color: null })}>跟随主题</button></div></div></div>
        {showCandidateSelectionAppearance && <div className="section"><div className="section-header"><span className="section-title">候选边框色</span><div className="candidate-color-control"><input aria-label="候选边框色" type="color" value={candidateTextColor(draft.candidate_border_color) ?? (candidatePreviewTheme === "light" ? "#dedede" : "#303030")} onChange={event => setDraft({ ...draft, candidate_border_color: event.target.value })} /><button type="button" className={`candidate-color-reset${candidateTextColor(draft.candidate_border_color) ? "" : " is-active"}`} onClick={() => setDraft({ ...draft, candidate_border_color: null })}>跟随主题</button></div></div></div>}
        <div className="section"><div className="section-header"><span className="section-title">候选编号颜色</span><div className="candidate-color-control">
          <input aria-label="候选编号颜色" type="color" value={candidateTextColor(draft.candidate_number_color) ?? (candidatePreviewTheme === "light" ? "#5f6368" : "#bdc1c6")} onChange={event => setDraft({ ...draft, candidate_number_color: event.target.value })} />
          <button type="button" className={`candidate-color-reset${candidateTextColor(draft.candidate_number_color) ? "" : " is-active"}`} aria-pressed={!candidateTextColor(draft.candidate_number_color)} onClick={() => { if (candidateTextColor(draft.candidate_number_color)) setDraft({ ...draft, candidate_number_color: null }); }}>跟随主题</button>
        </div></div></div>
        <div className="section"><label className="section-header"><span className="section-title">行内预编辑</span><select aria-label="行内预编辑" value={draft.tsf_preedit_style ?? "raw"} onChange={event => setDraft({ ...draft, tsf_preedit_style: event.target.value as Preferences["tsf_preedit_style"] })}>
          <option value="raw">原始按键</option><option value="pinyin">拼音分词</option><option value="empty">不显示</option>
        </select></label></div>
        <div className="section"><label className="section-header"><span className="section-title">候选窗预编辑</span><select aria-label="候选窗预编辑" value={draft.candidate_preedit_style ?? "pinyin"} onChange={event => setDraft({ ...draft, candidate_preedit_style: event.target.value as Preferences["candidate_preedit_style"] })}>
          <option value="pinyin">显示拼音</option><option value="empty">隐藏</option>
        </select></label></div>
        <div className="section"><label className="section-header"><span className="section-title">每页候选数量</span><select aria-label="每页候选数量" value={draft.candidate_page_size} onChange={event => setDraft({ ...draft, candidate_page_size: Number(event.target.value) })}>
          {Array.from({ length: 9 }, (_, index) => index + 1).map(size => <option key={size} value={size}>{size}</option>)}
        </select></label></div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "dictionary"} aria-label="词库">
        {client.dictionary?.importPersonal && <PersonalDictionaryImportCard dictionary={client.dictionary} />}
        {client.dictionary && <div className="section quick-phrase-manager" role="region" aria-label="快捷短语管理">
          <div className="section-header"><span className="section-title">本地词库管理<small>查询、新增、编辑、导入、导出和删除 Engine 用户词库。导入支持标准、Windows TSV、Rime 和纯汉字自动注音。</small></span><span><button type="button" className="secondary" disabled={phraseBusy} onClick={() => void loadPhrases(dictionaryKind, 0)}>查询</button> <button type="button" className="secondary" disabled={phraseBusy} onClick={() => setPhraseForm({ key: "", value: "", weight: 100000, previous: null })}>新增词条</button> <button type="button" className="secondary" disabled={phraseBusy || dictionaryFormat === "hans"} onClick={() => void exportPhrases()}>导出</button><label className="secondary">导入<input hidden type="file" accept=".txt,.tsv,.yaml,.yml,text/plain" disabled={phraseBusy} onChange={event => { const file = event.target.files?.[0]; if (file) { const name = file.name.toLowerCase(); if (name.endsWith(".yaml") || name.endsWith(".yml")) setDictionaryFormat("rime"); void importPhrases(file); } event.currentTarget.value = ""; }} /></label></span></div>
          {dictionaryPendingCount > 0 && <p className="input-setting-description" role="status">{dictionaryPendingCount} 项等待键盘同步。打开水杉键盘后会在空闲时逐条生效。</p>}
          {dictionarySnapshotError && <p role="alert" className="error">{dictionarySnapshotError}</p>}
          {dictionaryFailures.length > 0 && <div className="dictionary-failures" role="alert"><p>有 {dictionaryFailures.length} 项词库请求同步失败，可以重试或移除失败记录。</p><ul>{dictionaryFailures.map(failure => <li key={failure.request_id}><span><strong>{failure.label}</strong><small>{failure.error}</small></span><span><button type="button" className="secondary" disabled={phraseBusy || !client.dictionary?.retry} onClick={() => void retryDictionaryFailure(failure.request_id)}>重试</button> <button type="button" className="secondary" disabled={phraseBusy || !client.dictionary?.dismissFailure} onClick={() => void dismissDictionaryFailure(failure.request_id)}>移除记录</button></span></li>)}</ul></div>}
          <div className="dictionary-manager-controls"><label>词库 <select aria-label="本地词库类型" value={dictionaryKind} disabled={phraseBusy} onChange={event => { const kind = event.target.value as LocalDictionaryKind; setDictionaryKind(kind); if (kind !== "pinyin" && dictionaryFormat === "hans") setDictionaryFormat("standard"); setPhrases([]); void loadPhrases(kind); }}>{localDictionaryKinds.map(([kind, label]) => <option key={kind} value={kind}>{label}</option>)}</select></label><label>文件格式 <select aria-label="本地词库文件格式" value={dictionaryFormat} disabled={phraseBusy} onChange={event => setDictionaryFormat(event.target.value as LocalDictionaryFormat)}><option value="standard">标准 TSV</option><option value="windows">Windows TSV</option><option value="rime">Rime userdb / dict.yaml</option>{dictionaryKind === "pinyin" && <option value="hans">汉字自动注音（仅导入）</option>}</select></label><label>编码前缀 <input value={phraseSearch} placeholder="留空查看全部" onChange={event => setPhraseSearch(event.target.value)} /></label></div>
          {phraseError && <p role="alert" className="error">{phraseError}</p>}
          {phraseNotice && <p role="status" className="dict-notice">{phraseNotice}</p>}
          {phraseForm && <div className="quick-phrase-form"><label>编码 <input value={phraseForm.key} onChange={event => setPhraseForm({ ...phraseForm, key: event.target.value })} /></label><label>{dictionaryKind === "quick_phrase" ? "短语" : "词条"} <input value={phraseForm.value} onChange={event => setPhraseForm({ ...phraseForm, value: event.target.value })} /></label><label>权重 <input type="number" value={phraseForm.weight} onChange={event => setPhraseForm({ ...phraseForm, weight: Number(event.target.value) })} /></label><button type="button" disabled={phraseBusy} onClick={() => void savePhrase()}>保存</button><button type="button" className="secondary" disabled={phraseBusy} onClick={() => setPhraseForm(null)}>取消</button></div>}
          {phrases.length === 0 ? <p className="dict-empty">点击查询后查看{localDictionaryKinds.find(([kind]) => kind === dictionaryKind)?.[1] ?? "词库"}词条</p> : <ul className="quick-phrase-list">{phrases.filter(entry => entry.key.startsWith(phraseSearch)).map((entry, index) => <li key={`${entry.key}-${entry.value}-${index}`}><span><code>{entry.key}</code>　{entry.value}　<small>{entry.weight}</small></span><span><button type="button" className="secondary" disabled={phraseBusy} onClick={() => setPhraseForm({ key: entry.key, value: entry.value, weight: entry.weight, previous: entry })}>编辑</button> <button type="button" className="secondary" disabled={phraseBusy} onClick={() => void removePhrase(entry)}>删除</button></span></li>)}</ul>}
          <div className="dictionary-pagination">
            <button type="button" className="secondary" disabled={phraseBusy || phrasePage.offset === 0} onClick={() => void loadPhrases(dictionaryKind, Math.max(0, phrasePage.offset - DICTIONARY_PAGE_SIZE))}>上一页</button>
            <span aria-live="polite">{phrasePage.status}</span>
            <button type="button" className="secondary" disabled={phraseBusy || !phrasePage.hasMore} onClick={() => void loadPhrases(dictionaryKind, phrasePage.offset + DICTIONARY_PAGE_SIZE)}>下一页</button>
          </div>
        </div>}
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "skin"} aria-label="皮肤">
        <div className="skin-intro">选择候选窗和悬浮工具栏使用的主题；明暗预览仅影响当前卡片，不修改设置。</div>
        {snapshot?.candidate_skin_catalog && <div className="skin-catalog-status" role="status">外部皮肤目录：{snapshot.candidate_skin_catalog.scanned ? `已扫描（${snapshot.candidate_skin_catalog.packages.length} 个）` : "尚未扫描"}{snapshot.candidate_skin_catalog.issues?.length ? `，${snapshot.candidate_skin_catalog.issues.length} 个问题` : ""}</div>}
        <div className="skin-grid">
          {skinOptions.map(([id, title, description]) => <article aria-label={title} className={`skin-card${(draft.candidate_skin ?? "fluent") === id ? " selected" : ""}`} key={id}>
            <div className="skin-card-header">
              <div className="skin-card-body"><span className="skin-card-title">{title} ({(skinPreviewThemes[id] ?? candidatePreviewTheme) === "dark" ? "Dark" : "Light"})</span><span className="skin-card-description">{description}</span></div>
              <div className="skin-card-actions">
                <button type="button" role="switch" aria-label={title} aria-checked={(draft.candidate_skin ?? "fluent") === id} className="skin-selection-switch" onClick={() => setDraft({ ...draft, candidate_skin: id })}><span /></button>
                <button type="button" className="skin-preview-switch" onClick={() => setSkinPreviewThemes(current => ({ ...current, [id]: (current[id] ?? candidatePreviewTheme) === "dark" ? "light" : "dark" }))}>
                  {(skinPreviewThemes[id] ?? candidatePreviewTheme) === "dark" ? "预览浅色" : "预览深色"}
                </button>
              </div>
            </div>
            <div className={`skin-card-preview skin-${id}`} data-preview-theme={skinPreviewThemes[id] ?? candidatePreviewTheme} aria-hidden="true">
              <div className="skin-preview-stage"><SkinCandidatePreview orientation="horizontal" /></div>
              <div className="skin-preview-stage"><SkinCandidatePreview orientation="vertical" /></div>
              <div className="skin-preview-stage"><SkinToolbarPreview /></div>
            </div>
          </article>)}
        </div>
        <ExternalSkins activeTheme={candidatePreviewTheme} scan={client.scanSkinCatalog} openDirectory={client.openSkinDirectory} readImage={client.readSkinImage} readFont={client.readSkinFont} readToolbarCss={client.readSkinToolbarCss} selected={draft.candidate_skin ?? "fluent"} layout={draft.candidate_layout ?? "vertical"} onSelect={id => setDraft({ ...draft, candidate_skin: id })} />
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "floating-toolbar"} aria-label="悬浮工具栏">
        <div className="section floating-toolbar-card">
          <label className="section-header floating-toolbar-setting-row"><span className="section-title">在桌面显示悬浮工具栏<small>快速访问输入法状态与常用功能</small></span><input aria-label="在桌面显示悬浮工具栏" className="toggle" type="checkbox" checked={floatingToolbar.enabled} onChange={event => setDraft({ ...draft, floating_toolbar: { ...floatingToolbar, enabled: event.target.checked } })} /></label>
          <div className="floating-toolbar-preview" aria-label="悬浮工具栏预览">
            <div className="floating-toolbar-preview-label">预览</div>
            <div className={`skin-card-preview toolbar-settings-preview skin-${draft.candidate_skin ?? "fluent"}`} data-preview-theme={toolbarPreviewTheme}>
              <SkinToolbarPreview preferences={floatingToolbar} />
            </div>
          </div>
        </div>
        {!showToolbarAppearance && <div className="section"><small>当前宿主以输入法菜单呈现工具栏，缩放、图标尺寸与组件选择不适用；上方开关仍然生效。</small></div>}
        {showToolbarAppearance && <div className="section floating-toolbar-appearance">
          <label className="section-header"><span className="section-title">工具栏缩放<small>相对系统 DPI 的额外缩放，不改变系统显示缩放</small></span><select aria-label="工具栏缩放" value={floatingToolbar.scale_percent} onChange={event => setDraft({ ...draft, floating_toolbar: { ...floatingToolbar, scale_percent: Number(event.target.value) as FloatingToolbarPreferences["scale_percent"] } })}>{floatingToolbarScales.map(value => <option key={value} value={value}>{value}%</option>)}</select></label>
          <div className="input-option-divider" />
          <label className="section-header"><span className="section-title">图标尺寸<small>图标基准大小（像素），再乘以上方缩放</small></span><select aria-label="图标尺寸" value={floatingToolbar.font_size} onChange={event => setDraft({ ...draft, floating_toolbar: { ...floatingToolbar, font_size: Number(event.target.value) as FloatingToolbarPreferences["font_size"] } })}>{floatingToolbarFontSizes.map(value => <option key={value} value={value}>{value}</option>)}</select></label>
        </div>}
        {showToolbarAppearance && <div className="section floating-toolbar-components">
          <div className="section-title">工具栏组件<small>勾选要显示在悬浮工具栏中的功能</small></div>
          <div className="floating-toolbar-component-list">
            <label className="check-option floating-toolbar-required-option"><input type="checkbox" checked disabled /><span>中英文切换</span><span className="floating-toolbar-required-label">始终显示</span></label>
            {floatingToolbarOptions.map(([key, label]) => <div key={key}><div className="input-option-divider" /><label className="check-option"><input type="checkbox" checked={floatingToolbar[key]} onChange={event => setDraft({ ...draft, floating_toolbar: { ...floatingToolbar, [key]: event.target.checked } })} /><span>{label}</span></label></div>)}
          </div>
        </div>}
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "input"} aria-label="输入">
        <div className="section"><label className="section-header"><span className="section-title">默认输入状态<small>新焦点会话开始时使用的中文或英文状态</small></span><select aria-label="默认输入状态" value={draft.default_ime_mode ?? "chinese"} onChange={event => setDraft({ ...draft, default_ime_mode: event.target.value as Preferences["default_ime_mode"] })}><option value="chinese">中文</option><option value="english">英文</option></select></label></div>
        {showModeScope && <div className="section"><label className="section-header"><span className="section-title">中英文状态范围<small>应用范围只影响当前输入上下文；全局范围在 Linux 输入法会话之间保持同一状态</small></span><select aria-label="中英文状态范围" value={draft.ime_mode_scope ?? "app"} onChange={event => setDraft({ ...draft, ime_mode_scope: event.target.value as Preferences["ime_mode_scope"] })}><option value="app">按应用</option><option value="global">全局</option></select></label></div>}
        {client.touchKeyboardSchemes && <div className="section touch-keyboard-schemes" role="group" aria-labelledby="touch-keyboard-schemes-title">
          <div className="section-title" id="touch-keyboard-schemes-title">输入方案</div>
          <div className="input-setting-description">开启的方案会显示在键盘快捷切换中，至少保留一种。点击名称设为当前方案。</div>
          <div className="input-option-content">{touchKeyboardSchemeOptions.map(([scheme, label], index) => {
            const enabled = touchKeyboardSchemes.enabled.includes(scheme);
            const selected = selectedTouchKeyboardScheme === scheme;
            return <div className="input-option-item touch-keyboard-scheme-item" key={scheme}>
              {index > 0 && <div className="input-option-divider" />}
              <div className="touch-keyboard-scheme-row">
                <button type="button" className="touch-keyboard-scheme-select" aria-label={`设为当前输入方案 ${label}`}
                  aria-pressed={selected} disabled={!enabled} onClick={() => setDraft(selectTouchKeyboardScheme(draft, scheme))}>
                  <span>{label}</span>{selected && <span aria-hidden="true">✓</span>}
                </button>
                <input className="toggle" type="checkbox" aria-label={`显示输入方案 ${label}`} checked={enabled}
                  disabled={enabled && touchKeyboardSchemes.enabled.length === 1}
                  onChange={event => setTouchKeyboardSchemeEnabled(scheme, event.target.checked)} />
              </div>
            </div>;
          })}</div>
        </div>}
        <div className="section" role="group" aria-labelledby="input-mode-title" hidden={client.touchKeyboardSchemes}>
          <div className="section-title" id="input-mode-title">输入模式</div>
          <div className="input-setting-description">切换中文或日文输入，并保留各模式上次选择的方案</div>
          <div className="input-option-content input-mode-options">
            <label className="radio-option"><input type="radio" name="input-mode" value="chinese" checked={draft.scheme !== "japanese"} onChange={() => setDraft({ ...draft, scheme: draft.last_chinese_scheme ?? "quanpin" })} /><span>中文</span></label>
            <div className="input-option-divider" />
            <label className="radio-option"><input type="radio" name="input-mode" value="japanese" checked={draft.scheme === "japanese"} onChange={() => setDraft({ ...draft, last_chinese_scheme: draft.scheme === "japanese" ? draft.last_chinese_scheme : draft.scheme, scheme: "japanese" })} /><span>日文</span></label>
          </div>
        </div>
        <div className="section" role="group" aria-labelledby="input-scheme-title" hidden={client.touchKeyboardSchemes || draft.scheme === "japanese"}>
          <div className="section-title" id="input-scheme-title">输入方案</div>
          <div className="input-option-content">
            {([["quanpin", "全拼"], ["shuangpin", "双拼"], ["wubi", "五笔"]] as const).map(([scheme, label], index) => <div className="input-option-item" key={scheme}>
              {index > 0 && <div className="input-option-divider" />}
              <label className="radio-option"><input type="radio" name="input-scheme" value={scheme} checked={draft.scheme === scheme} onChange={() => setDraft({ ...draft, scheme, last_chinese_scheme: scheme })} /><span>{label}</span></label>
            </div>)}
          </div>
        </div>
        <div className="section" hidden={client.touchKeyboardSchemes || draft.scheme === "japanese"}><label className="section-header"><span className="section-title">双拼方案</span><select value={draft.shuangpin_profile} onChange={event => setDraft({ ...draft, shuangpin_profile: event.target.value as Preferences["shuangpin_profile"] })}>
          <option value="xiaohe">小鹤双拼</option><option value="ziranma">自然码双拼</option>
          <option value="shoudao">首道双拼</option><option value="microsoft">微软双拼</option>
        </select></label></div>
        <div className="section" hidden={client.touchKeyboardSchemes || draft.scheme === "japanese"}><label className="section-header"><span className="section-title">五笔方案</span><select value="wubi86" onChange={() => {}}><option value="wubi86">86 五笔</option></select></label></div>
        {((client.touchKeyboardSchemes && touchKeyboardSchemes.enabled.includes("wubi")) || draft.scheme === "wubi") && <div className="section" role="group" aria-label="五笔"><label className="section-header"><span className="section-title">候选显示剩余编码<small>在候选后面标出还要再打哪几个字母才能单独打出它。已经打完整码的候选不标。</small></span><input aria-label="候选显示剩余编码" className="toggle" type="checkbox" checked={draft.wubi_code_hint ?? true} onChange={event => setDraft({ ...draft, wubi_code_hint: event.target.checked })} /></label></div>}
        <div className="section" role="group" aria-labelledby="japanese-scheme-title" hidden={client.touchKeyboardSchemes || draft.scheme !== "japanese"}>
          <div className="section-title" id="japanese-scheme-title">日语方案</div>
          <div className="input-option-content"><label className="radio-option"><input type="radio" name="japanese-scheme" checked readOnly /><span>罗马字</span></label></div>
          <div className="input-setting-description japanese-scheme-description">直接输入罗马字，提供平假名、片假名及日语词库候选</div>
        </div>
        <div className="section" role="group" aria-labelledby="paging-title">
          <div className="section-title" id="paging-title">翻页方式</div>
          <div className="input-option-content">{navigationOptions.map(([key, label], index) => <div className="input-option-item" key={key}>
            {index > 0 && <div className="input-option-divider" />}
            <label className="check-option"><input type="checkbox" checked={(draft.navigation ?? defaultNavigation)[key]} onChange={event => setDraft({ ...draft,
              ...(event.target.checked && wordCharacter.enabled && wordCharacter.keys === key ? { word_character: { ...wordCharacter, enabled: false } } : {}),
              navigation: { ...(draft.navigation ?? defaultNavigation), [key]: event.target.checked } })} /><span>{label}</span></label>
          </div>)}</div>
        </div>
        <div className="section">
          <label className="section-header"><span className="section-title">以词定字<small>开启后，按所选键组的左键上屏高亮候选的首个汉字，右键上屏末个汉字</small></span>
            <input className="toggle" type="checkbox" checked={wordCharacter.enabled} onChange={event => setDraft({ ...draft,
              word_character: { ...wordCharacter, enabled: event.target.checked },
              ...(event.target.checked ? { navigation: { ...(draft.navigation ?? defaultNavigation), [wordCharacter.keys]: false } } : {}) })} />
          </label>
          <div className="word-to-character-keys-row"><div className="section-title" id="word-character-title">以词定字快捷键</div>
            <div className="input-option-content" role="radiogroup" aria-labelledby="word-character-title">
              {([["brackets", "[ / ]"], ["minus_equal", "- / ="]] as const).map(([keys, label], index) => <div className="input-option-item" key={keys}>
                {index > 0 && <div className="input-option-divider" />}<label className="radio-option">
                <input type="radio" name="word-character-keys" checked={wordCharacter.keys === keys} disabled={(draft.navigation ?? defaultNavigation)[keys]} onChange={() => setDraft({ ...draft, word_character: { ...wordCharacter, keys } })} /><span>{label}</span>
              </label></div>)}
            </div>
          </div>
        </div>
        <div className="section" role="group" aria-label="全拼纠错">
          <div className="section-title">全拼纠错<small>分别控制字母错位和邻键误触的拼音纠错</small></div>
          <label className="section-header"><span className="section-title">字母顺序错位<small>例如把 shang 输入为 sahng</small></span><input aria-label="全拼纠错：字母顺序错位" className="toggle" type="checkbox" checked={quanpinAutocorrect.autocorrect_transposition} onChange={event => setDraft({ ...draft, quanpin: { ...(draft.quanpin ?? {}), ...quanpinAutocorrect, autocorrect_transposition: event.target.checked } })} /></label>
          <div className="input-option-divider" />
          <label className="section-header"><span className="section-title">相邻键误触<small>例如把 shang 输入为 shabg</small></span><input aria-label="全拼纠错：相邻键误触" className="toggle" type="checkbox" checked={quanpinAutocorrect.autocorrect_neighbor} onChange={event => setDraft({ ...draft, quanpin: { ...(draft.quanpin ?? {}), ...quanpinAutocorrect, autocorrect_neighbor: event.target.checked } })} /></label>
        </div>
        {client.fuzzyPinyin && <div className="section" role="group" aria-label="模糊音">
          <label className="section-header"><span className="section-title">模糊音<small>全拼、九键与双拼均支持；更改会在当前输入结束后生效</small></span>
            <input aria-label="启用模糊音" className="toggle" type="checkbox" checked={fuzzyPinyin.enabled} onChange={event => setDraft({
              ...draft, fuzzy_pinyin: { ...fuzzyPinyin, enabled: event.target.checked },
            })} />
          </label>
          <p className="input-setting-description">勾选容易混淆的读音后，会补充对应候选。关闭总开关会保留已选规则。</p>
          {fuzzyPinyinGroups.map(([title, rules]) => <div key={title} className="fuzzy-pinyin-group">
            <div className="section-title">{title}</div>
            <div className="input-option-content">{rules.map(([id, label], index) => <div className="input-option-item" key={id}>
              {index > 0 && <div className="input-option-divider" />}
              <label className="check-option"><input aria-label={`模糊音规则 ${id}`} type="checkbox" disabled={!fuzzyPinyin.enabled}
                checked={fuzzyPinyin.rules.includes(id)} onChange={event => {
                  const selected = new Set(fuzzyPinyin.rules);
                  if (event.target.checked) selected.add(id); else selected.delete(id);
                  setDraft({ ...draft, fuzzy_pinyin: { ...fuzzyPinyin, rules: [...selected].sort() } });
                }} /><span>{label}</span></label>
            </div>)}</div>
          </div>)}
          <button type="button" className="secondary fuzzy-pinyin-reset" onClick={() => {
            if (window.confirm("关闭模糊音并清空所有规则？")) setDraft({ ...draft, fuzzy_pinyin: { enabled: false, rules: [] } });
          }}>重置模糊音配置</button>
        </div>}
        <div className="section"><label className="section-header"><span className="section-title">学习选词习惯<small>根据选词调整候选顺序</small></span><input className="toggle" type="checkbox" checked={draft.learning} onChange={event => setDraft({ ...draft, learning: event.target.checked })} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">中文标点<small>默认使用中文标点符号</small></span><input className="toggle" type="checkbox" checked={draft.chinese_punctuation} onChange={event => setDraft({ ...draft, chinese_punctuation: event.target.checked })} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">智能标点<small>根据输入上下文选择中文或英文标点形式</small></span><input className="toggle" type="checkbox" checked={smartPunctuation} onChange={event => setDraft({ ...draft, smart_punctuation: event.target.checked })} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">重复标点转中文<small>短时间重复输入 ASCII 标点时转换为中文标点</small></span><input className="toggle" type="checkbox" checked={smartPunctuationRepeat} onChange={event => setDraft({ ...draft, smart_punctuation_repeat: event.target.checked })} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">成对标点<small>自动补全成对引号和括号</small></span><input className="toggle" type="checkbox" checked={pairedPunctuation} onChange={event => setDraft({ ...draft, paired_punctuation: event.target.checked })} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">标点锁定</span><select aria-label="标点锁定" value={punctuationLock} onChange={event => setDraft({ ...draft, punctuation_lock: event.target.value as Preferences["punctuation_lock"] })}><option value="follow">跟随输入模式</option><option value="chinese">固定中文标点</option><option value="english">固定英文标点</option></select></label></div>
        <div className="section"><label className="section-header"><span className="section-title">繁体中文输出<small>将提交的简体中文转换为繁体中文</small></span><input aria-label="繁体中文输出" className="toggle" type="checkbox" checked={draft.traditional_chinese_output ?? false} onChange={event => setDraft({ ...draft, traditional_chinese_output: event.target.checked })} /></label></div>
        {client.candidateEnglishGloss && <div className="section"><label className="section-header"><span className="section-title">显示英文释义<small>在候选词后面标出它的英文意思，中文候选给英文、英文候选给中文。释义来自随键盘打包的离线词库，不联网。</small></span><input aria-label="显示英文释义" className="toggle" type="checkbox" checked={candidateEnglishGloss} onChange={event => setDraft({ ...draft, candidate_english_gloss: event.target.checked })} /></label></div>}
        <div className="section"><label className="section-header"><span className="section-title">云联想<small>向在线服务请求额外候选</small></span><input className="toggle" type="checkbox" checked={cloudCandidates} onChange={event => setDraft({ ...draft, cloud_candidates: event.target.checked })} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">候选翻译<small>为当前候选请求翻译结果并显示在候选行</small></span><input className="toggle" type="checkbox" checked={candidateTranslations} onChange={event => setDraft({ ...draft, candidate_translations: event.target.checked })} /></label>
          <div className="input-option-divider" />
          <label className="section-header"><span className="section-title">目标语言</span><select aria-label="候选翻译目标语言" disabled={!candidateTranslations} value={translationTargetLanguage} onChange={event => setDraft({ ...draft, translation_target_language: event.target.value as Preferences["translation_target_language"] })}>{translationLanguages.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
        </div>
        <div className="section" role="group" aria-label="在线翻译服务">
          <label className="section-header"><span className="section-title">在线翻译服务<small>候选翻译默认使用腾讯云机器翻译，需要填入你自己的 API 凭据</small></span><input aria-label="腾讯云机器翻译" className="toggle" type="checkbox" disabled={!candidateTranslations} checked={tencentTmt.enabled} onChange={event => setDraft({ ...draft, tencent_tmt: { ...tencentTmt, enabled: event.target.checked } })} /></label>
          <div className="input-option-divider" />
          <label className="section-header"><span className="section-title">SecretId</span><input aria-label="腾讯云 SecretId" type="text" autoComplete="off" spellCheck={false} value={tencentTmt.secret_id} disabled={!candidateTranslations || !tencentTmt.enabled} onChange={event => setDraft({ ...draft, tencent_tmt: { ...tencentTmt, secret_id: event.target.value } })} placeholder="AKIDxxxxxxxxxxxxxxxx" /></label>
          <div className="input-option-divider" />
          <label className="section-header"><span className="section-title">SecretKey</span><SecretInput label="腾讯云 SecretKey" value={tencentTmt.secret_key} disabled={!candidateTranslations || !tencentTmt.enabled} onChange={value => setDraft({ ...draft, tencent_tmt: { ...tencentTmt, secret_key: value } })} /></label>
          <div className="input-option-divider" />
          <label className="section-header"><span className="section-title">地域</span><input aria-label="腾讯云地域" type="text" autoComplete="off" spellCheck={false} value={tencentTmt.region} disabled={!candidateTranslations || !tencentTmt.enabled} onChange={event => setDraft({ ...draft, tencent_tmt: { ...tencentTmt, region: event.target.value } })} placeholder="ap-guangzhou" /></label>
          {candidateTranslations && tencentTmt.enabled && tencentCredentialIssue(tencentTmt.secret_id, tencentTmt.secret_key, tencentTmt.region) && <p className="settings-warning" role="status">{tencentCredentialIssue(tencentTmt.secret_id, tencentTmt.secret_key, tencentTmt.region)}</p>}
          {candidateTranslations && tencentTmt.enabled && !tencentCredentialIssue(tencentTmt.secret_id, tencentTmt.secret_key, tencentTmt.region) && !(tencentSecretConfigured(tencentTmt.secret_id) && tencentSecretConfigured(tencentTmt.secret_key)) && !customTranslation.enabled && <p className="settings-warning" role="status">未填写腾讯云凭据，候选翻译不会有任何结果。请填入 SecretId 与 SecretKey，或改用下面的自定义翻译服务。</p>}
        </div>
        <div className="section" role="group" aria-label="自定义翻译服务">
          <label className="section-header"><span className="section-title">自定义翻译服务<small>改用自建的兼容 DeepLX 的 HTTPS 服务；关闭后候选翻译使用上面选择的在线服务</small></span><input aria-label="自定义翻译服务" className="toggle" type="checkbox" disabled={!candidateTranslations} checked={customTranslation.enabled} onChange={event => setDraft({ ...draft, custom_translation: { ...customTranslation, enabled: event.target.checked } })} /></label>
          <div className="input-option-divider" />
          <label className="section-header"><span className="section-title">翻译 Endpoint</span><input aria-label="自定义翻译 Endpoint" type="url" value={customTranslation.endpoint} disabled={!candidateTranslations || !customTranslation.enabled} onChange={event => setDraft({ ...draft, custom_translation: { ...customTranslation, endpoint: event.target.value } })} placeholder="https://example.com/translate" /></label>
          {candidateTranslations && customTranslation.enabled && translationEndpointIssue(customTranslation.endpoint) && <p className="settings-warning" role="status">{translationEndpointIssue(customTranslation.endpoint)}</p>}
          <div className="input-option-divider" />
          <label className="section-header"><span className="section-title">API Key</span><SecretInput label="自定义翻译 API Key" value={customTranslation.api_key} disabled={!candidateTranslations || !customTranslation.enabled} onChange={value => setDraft({ ...draft, custom_translation: { ...customTranslation, api_key: value } })} /></label>
        </div>
        <div className="section" role="group" aria-label="中英混输">
          <label className="section-header"><span className="section-title">中英混输<small>中文输入时在候选项中补充英文单词</small></span><input className="toggle" type="checkbox" checked={mixedInput.english} onChange={event => setDraft({ ...draft, mixed_input: { ...mixedInput, english: event.target.checked } })} /></label>
          <div className="input-option-divider" />
          <label className="section-header frequency-option-row"><span className="section-title">触发字符数<small>预编辑字母达到该长度后才出现英文候选项</small></span><select aria-label="触发字符数" disabled={!mixedInput.english} value={mixedInput.minimum_prefix} onChange={event => setDraft({ ...draft, mixed_input: { ...mixedInput, minimum_prefix: Number(event.target.value) } })}>
            {[1, 2, 3, 4, 5, 6, 7, 8].map(value => <option key={value} value={value}>{value}</option>)}
          </select></label>
        </div>
        {([["emoji", "emoji 混输", "中文输入时在候选项中加入匹配的 emoji（位于英文候选之后；云候选与 AI 联想会使其相应顺移）"], ["kaomoji", "颜文字混输", "中文输入时在候选项中加入匹配的颜文字（排在 emoji 之后；云候选与 AI 联想会使其相应顺移）"]] as const).map(([key, label, description]) => <div className="section" key={key}>
          <label className="section-header"><span className="section-title">{label}<small>{description}</small></span><input className="toggle" type="checkbox" checked={mixedInput[key]} onChange={event => setDraft({ ...draft, mixed_input: { ...mixedInput, [key]: event.target.checked } })} /></label>
        </div>)}
        <div className="section" role="group" aria-labelledby="frequency-title">
          <div className="section-title" id="frequency-title">拼音方案调频</div>
          <div className="frequency-option-content">
            <label className="section-header frequency-option-row"><span className="section-title">调频方式</span><select value={frequency.mode} onChange={event => setDraft({ ...draft, frequency: { ...frequency, mode: event.target.value as FrequencyPreferences["mode"] } })}>
              <option value="disabled">关闭</option><option value="pin">一次置顶</option><option value="halve">折半调频</option><option value="linear">线性调频</option><option value="promote">一次置前</option>
            </select></label>
            {([["trigger_count", "触发频次(第几次上屏触发)"], ["linear_step", "线性调频步长"]] as const).map(([key, label]) => <div key={key}>
              <div className="input-option-divider" />
              <label className="section-header frequency-option-row"><span className="section-title">{label}</span><select value={frequency[key]} onChange={event => setDraft({ ...draft, frequency: { ...frequency, [key]: Number(event.target.value) } })}>
                {[1, 2, 3, 4, 5, 6, ...(frequency[key] > 6 ? [frequency[key]] : [])].map(value => <option key={value} value={value}>{value}</option>)}
              </select></label>
            </div>)}
          </div>
        </div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "helpcode"} aria-label="辅助码">
        {([['shuangpin_helpcode', '双拼'], ['quanpin_helpcode', '全拼']] as const).map(([key, label]) => {
          const value = { ...defaultHelpcode, ...(draft[key] ?? {}) } as Required<HelpcodePreferences>;
          return <div className="section" key={key}>
            <label className="section-header"><span className="section-title">{label}辅助码</span><input className="toggle" type="checkbox" checked={value.enabled} onChange={event => setDraft({ ...draft, [key]: { ...value, enabled: event.target.checked } })} /></label>
            <label className="section-header helpcode-schema"><span className="section-title">{label}辅助码方案</span><select disabled={!value.enabled} value={value.schema} onChange={event => setDraft({ ...draft, [key]: { ...value, schema: event.target.value as HelpcodeSchema } })}>
              {helpcodeSchemas.map(([schema, name]) => <option key={schema} value={schema}>{name}</option>)}
            </select></label>
            <label className="section-header"><span className="section-title">在候选窗口显示辅助码</span><input className="toggle" type="checkbox" checked={value.show_in_candidate_window} onChange={event => setDraft({ ...draft, [key]: { ...value, show_in_candidate_window: event.target.checked } })} /></label>
          </div>;
        })}
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "shortcuts"} aria-label="快捷键">
        <div className="section shortcut-intro">输入法快捷键仅在对应输入状态或候选窗口显示时生效。翻页方式可在“输入”中启用或关闭。</div>
        {showModeSwitchShortcuts && <div className="section" role="group" aria-label="输入模式切换快捷键">
          <div className="section-title">输入模式切换</div>
          <small>在当前输入上下文中切换中英文模式；关闭后快捷键会交给应用处理。</small>
          {([[
            "switch_language_shift", "Shift 切换中英文",
          ], [
            "switch_language_ctrl", "单击 Ctrl 切换中英文",
          ], [
            "switch_language_ctrl_alt_space", "Ctrl+Alt+Space 切换中英文",
          ], [
            "toggle_character_set_ctrl_shift_f", "Ctrl+Shift+F 切换简繁",
          ]] as const).map(([key, label]) => <label className="section-header" key={key}>
            <span className="section-title">{label}</span>
            <input aria-label={label} className="toggle" type="checkbox" checked={keybindings[key]} onChange={event => setDraft({ ...draft, keybindings: { ...keybindings, [key]: event.target.checked } })} />
          </label>)}
        </div>}
        {showPanelShortcuts && <div className="section" role="group" aria-label="面板快捷键">
          <div className="section-title">面板快捷键</div>
          <small>桌面环境转发 Super 组合键时可从当前输入上下文打开面板。</small>
          <div className="shortcut-list">
            <div className="shortcut-row"><span>打开屏幕键盘</span><kbd>Ctrl+Shift+Super+K</kbd></div>
          </div>
        </div>}
        <div className="section shortcut-section">
          <div className="section-title">候选操作</div>
          <small>输入和选取候选词时使用</small>
          <div className="shortcut-list">
            <div className="shortcut-row"><span>选择候选</span><kbd>Space 或 1–9</kbd></div>
            {(draft.navigation ?? defaultNavigation).minus_equal && <div className="shortcut-row"><span>向前 / 向后翻页</span><kbd>- / =</kbd></div>}
            {(draft.navigation ?? defaultNavigation).comma_period && <div className="shortcut-row"><span>向前 / 向后翻页</span><kbd>, / .</kbd></div>}
            {(draft.navigation ?? defaultNavigation).tab && <div className="shortcut-row"><span>向前 / 向后翻页</span><kbd>Shift+Tab / Tab</kbd></div>}
            {(draft.navigation ?? defaultNavigation).page_up_down && <div className="shortcut-row"><span>向前 / 向后翻页</span><kbd>Page Up / Page Down</kbd></div>}
            {(draft.navigation ?? defaultNavigation).arrows && <div className="shortcut-row"><span>移动候选项</span><kbd>↑ / ↓</kbd></div>}
            <div className="shortcut-row"><span>编辑输入串</span><kbd>← / → / Backspace</kbd></div>
            <div className="shortcut-row"><span>提交原始输入 / 取消输入</span><kbd>Enter / Esc</kbd></div>
          </div>
        </div>
        {showDesktopMaintenanceShortcuts && <div className="section shortcut-section">
          <div className="section-title">全局维护快捷键</div>
          <small>{linuxPlatform ? "当前 IBus 会话中的候选维护与服务重启" : "程序运行时全局生效；用于维护与调试"}</small>
          <div className="shortcut-list">
            <div className="shortcut-row"><span>删除当前候选窗口中的第 1–8 项</span><kbd>Ctrl+Shift+Alt+1–8</kbd></div>
            {linuxPlatform && <>
              <div className="shortcut-row"><span>清除当前输入法会话的 Engine 缓存</span><kbd>Ctrl+Shift+Alt+C</kbd></div>
              <div className="shortcut-row"><span>重启输入法服务</span><kbd>Ctrl+Shift+Alt+R</kbd></div>
            </>}
            {!linuxPlatform && <>
              <div className="shortcut-row"><span>清除输入法引擎缓存</span><kbd>Ctrl+Shift+Alt+C</kbd></div>
              <div className="shortcut-row"><span>重启输入法服务</span><kbd>Ctrl+Shift+Alt+R</kbd></div>
              <div className="shortcut-row shortcut-row-danger"><span>立即退出输入法服务</span><kbd>Ctrl+Shift+Alt+T</kbd></div>
            </>}
          </div>
        </div>}
        {showRestartInputMethod && <div className="section shortcut-section">
          <div className="section-title">输入法服务</div>
          <small>IBus 配置支持热重载；需要重新启动输入法服务时可使用此按钮。</small>
          <div className="service-action-row">
            <span>立即重启输入法服务</span>
            <HostActionButton action={client.restartInputMethod} label="重启" success="已发送重启请求。" error="重启输入法服务失败，请稍后重试。" />
          </div>
        </div>}
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "tools"} aria-label="实用功能">
        <div className="section"><label className="section-header"><span className="section-title">剪贴板管理<small>开启后记录复制的文本；保存关闭设置后清空已保存记录，且只记录文本类型。</small></span><input aria-label="剪贴板管理" className="toggle" type="checkbox" checked={clipboardHistory} onChange={event => setDraft({ ...draft, clipboard_history: event.target.checked })} /></label>
          {client.clipboard?.sync && <button type="button" className="secondary" disabled={!clipboardHistory || !snapshot?.preferences.clipboard_history} onClick={() => void client.clipboard!.sync!().then(setClipboardEntries).catch(() => setError("无法同步剪贴板历史"))}>从系统剪贴板同步</button>}
          {clipboardHistory && client.clipboard?.list && <div className="clipboard-list" aria-label="剪贴板历史">{clipboardEntries.length === 0 ? <small>暂无历史记录</small> : clipboardEntries.map(entry => <div className="clipboard-row" key={entry}><span>{entry}</span>{client.clipboard?.copy && <button type="button" className="secondary" onClick={() => void client.clipboard!.copy!(entry)}>重新复制</button>}</div>)}</div>}
          {client.openCloudClipboard && <button type="button" className="secondary" onClick={() => void openPanel(client.openCloudClipboard)}>打开云剪贴板</button>}
          {client.openCloudDictionary && <button type="button" className="secondary" onClick={() => void openPanel(client.openCloudDictionary)}>打开云词典</button>}
        </div>
        {localModeRows.map(([key, label, description]) => <div className="section" key={key}>
          <label className="section-header"><span className="section-title">{label}<small>{description}</small></span><input className="toggle" type="checkbox" checked={localModes[key]} onChange={event => setDraft({ ...draft, local_modes: { ...localModes, [key]: event.target.checked } })} /></label>
        </div>)}
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "help"} aria-label="帮助">
        <div className="section document-page help-document">
          <p>{androidPlatform ? "水杉输入法是一款 Android 平台的中文输入法，通过系统输入法服务接入应用。" : linuxPlatform ? "水杉输入法是一款 Linux 桌面环境下的中文输入法，通过 IBus 接入 GTK、Qt 等应用。" : "水杉输入法是一款 Windows 平台的中文输入法。目前支持 Windows 11/Windows 10 平台。"}</p>
          <div className="document-subsection"><div className="section-title">快速上手</div><p>{androidPlatform ? "在系统设置的“语言和输入法”或“屏幕键盘”中启用并选择水杉输入法，也可以从首次启动页打开这些入口。默认是全拼输入法。" : linuxPlatform ? "安装并启动 IBus 宿主后，在系统设置的输入法列表中添加水杉输入法，再使用桌面环境提供的输入法切换快捷键切换。默认是全拼输入法。" : "安装输入法后，可以使用 Win + Space 快捷键切换到水杉输入法。默认是全拼输入法。"}</p></div>
          <div className="document-subsection"><div className="section-title">基本功能</div>
            <p>支持全拼、双拼和五笔。可以在设置窗口下的输入功能分区进行切换。全拼和双拼均支持辅助码，辅助码方案目前支持自然码辅助码、蓝天小雨点、首右 2.0、首右 plus 和小鹤。</p>
            <p>{androidPlatform ? "语音输入会调用设备上的系统语音识别服务，识别结果回到键盘后需确认才会插入；AI 功能按需配置。日常拼音输入无需联网。" : linuxPlatform ? "语音识别和云联想由用户自行管理的 provider 提供，设置页只保存行为选项，不保存或转发 provider 的凭据。" : "语音识别和 AI 联想需要自行填入 API 和 token。云联想目前支持谷歌的云接口，请注意网络问题。"}</p>
            <p>更多功能欢迎自由探索～</p>
          </div>
        </div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "about"} aria-label="关于">
        <div className="section document-hero about-hero"><div className="about-mark"><img src={logo} alt="水杉 IME" /></div><div><div className="document-eyebrow">Metasequoia IME</div><div className="document-hero-title">水杉 IME</div><p>{androidPlatform ? "为 Android 触屏输入体验打造的开放中文输入法。" : linuxPlatform ? "为 Linux 桌面输入体验打造的开放中文输入法。" : "为现代 Windows 桌面体验打造的开放中文输入法。"}</p></div></div>
        <div className="section about-links">
          <div className="about-link-row about-version-row"><div><div className="about-link-title">当前版本</div><div className="about-version">v{appVersion}</div>{updateStatus && <p className="about-update-status" role="status">{updateStatus}</p>}</div><button type="button" className="secondary about-update-button" disabled={updateBusy} onClick={() => void checkForUpdate()}>{updateBusy ? "正在检查…" : "检查更新"}</button></div>
          {availableUpdate && <div className="about-update-result"><p>水杉 IME v{availableUpdate.version.display} 已发布。</p>{installerTrust?.warning && <p className="about-update-warning">{installerTrust.warning}</p>}{installerTrust?.verify && <p>下载后请核对 SHA256：<code>{installerTrust.verify.sha256}</code></p>}<button type="button" className="secondary" onClick={() => void openExternalUrl(availableUpdate.releaseUrl)}>前往下载</button></div>}
          <button type="button" className="about-link-row about-document-link" onClick={() => void openExternalUrl(platformLicenseUrl)}><span className="about-link-title">开源许可协议</span><span aria-hidden="true">↗</span></button>
        {!linuxPlatform && <button type="button" className="about-link-row about-document-link" onClick={() => void openExternalUrl(androidPlatform ? androidPrivacyUrl : privacyUrl)}><span className="about-link-title">隐私政策</span><span aria-hidden="true">↗</span></button>}
        </div>
        {!androidPlatform && <div className="section" role="group" aria-label="诊断日志">
          <label className="section-header"><span className="section-title">Server 端日志<small>排查 Server 通信和输入延迟时开启。记录慢请求阶段、候选窗、悬浮工具栏、菜单、焦点会话和通信状态，不记录按键、输入内容或候选文本。</small></span><input aria-label="Server 端日志" className="toggle" type="checkbox" checked={diagnosticLog.server} onChange={event => setDraft({ ...draft, diagnostic_log: { ...diagnosticLog, server: event.target.checked } })} /></label>
          <div className="input-option-divider" />
          <label className="section-header"><span className="section-title">TSF 端日志<small>排查应用内预编辑和输入延迟时开启。日志在内存中限量缓冲，并通过独立管道批量汇总，不记录按键、输入内容或候选文本。</small></span><input aria-label="TSF 端日志" className="toggle" type="checkbox" checked={diagnosticLog.tsf} onChange={event => setDraft({ ...draft, diagnostic_log: { ...diagnosticLog, tsf: event.target.checked } })} /></label>
        </div>}
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "screen-keyboard"} aria-label="屏幕键盘">
        <div className="section"><label className="section-header"><span className="section-title">屏幕键盘主题<small>覆盖全局主题；桌面屏幕键盘支持此设置</small></span><select aria-label="屏幕键盘主题" value={draft.screen_keyboard_theme ?? "follow"} onChange={event => setDraft({ ...draft, screen_keyboard_theme: event.target.value as SurfaceTheme })}><option value="follow">跟随全局</option><option value="dark">深色</option><option value="light">浅色</option></select></label></div>
        <div className="section touch-keyboard-skin-section" role="group" aria-labelledby="touch-keyboard-skin-title">
          <div className="section-title" id="touch-keyboard-skin-title">键盘皮肤<small>与 Apple 内置皮肤一致；独立于桌面候选窗皮肤</small></div>
          <div className="touch-keyboard-skin-grid">
            {touchKeyboardSkinOptions.map(option => <article className={`touch-keyboard-skin-card${touchKeyboardSkin === option.id ? " selected" : ""}`} key={option.id}>
              <button type="button" role="switch" aria-label={`屏幕键盘皮肤 ${option.title}`} aria-checked={touchKeyboardSkin === option.id} onClick={() => setDraft({ ...draft, touch_keyboard_skin: option.id })}>
                <ScreenKeyboardPreview theme={keyboardPreviewTheme} skin={option.id} compact />
                <span className="touch-keyboard-skin-copy"><strong>{option.title}</strong><small>{option.description}</small></span>
                <span className="touch-keyboard-skin-check" aria-hidden="true">{touchKeyboardSkin === option.id ? "✓" : ""}</span>
              </button>
            </article>)}
            {client.customTouchKeyboardSkins && <article className={`touch-keyboard-skin-card${touchKeyboardSkin === "custom" ? " selected" : ""}`}>
              <button type="button" role="switch" aria-label="屏幕键盘皮肤 我的皮肤" aria-checked={touchKeyboardSkin === "custom"} onClick={() => setDraft({ ...draft, touch_keyboard_skin: "custom" })}>
                <ScreenKeyboardPreview theme={keyboardPreviewTheme} skin="custom" customDesign={customTouchKeyboardSkin} compact />
                <span className="touch-keyboard-skin-copy"><strong>我的皮肤</strong><small>自由配色 · 自定义键帽</small></span>
                <span className="touch-keyboard-skin-check" aria-hidden="true">{touchKeyboardSkin === "custom" ? "✓" : ""}</span>
              </button>
            </article>}
          </div>
          {client.customTouchKeyboardSkins && <button type="button" className="secondary touch-skin-editor-open" aria-expanded={showTouchSkinEditor} onClick={() => setShowTouchSkinEditor(value => !value)}>{showTouchSkinEditor ? "收起自定义编辑器" : "设计我的皮肤"}</button>}
        </div>
        {client.customTouchKeyboardSkins && showTouchSkinEditor && <div className="section"><TouchKeyboardSkinEditor design={customTouchKeyboardSkin} selected={touchKeyboardSkin === "custom"} theme={keyboardPreviewTheme} disabled={busy} library={client.customSkinLibrary} aiSkins={client.aiSkins} communitySkins={client.communitySkins} onChange={design => setDraft(current => current ? { ...current, custom_touch_keyboard_skin: design } : current)} onUse={() => setDraft(current => current ? { ...current, touch_keyboard_skin: "custom" } : current)} onClose={() => setShowTouchSkinEditor(false)} /></div>}
        <div className="section" role="group" aria-labelledby="touch-keyboard-geometry-title">
          <div className="section-title" id="touch-keyboard-geometry-title">触屏键盘尺寸<small>与 Apple 键盘一致，只改变触屏键位外观，不改变输入方案或 Engine 组合状态</small></div>
          <label className="section-header"><span className="section-title">键盘高度 <small>{touchKeyboardHeightAdjustment > 0 ? "+" : ""}{touchKeyboardHeightAdjustment} dp</small></span><input aria-label="键盘高度" type="range" min="-12" max="48" step="1" value={touchKeyboardHeightAdjustment} onChange={event => setDraft({ ...draft, touch_keyboard_height_adjustment: Number(event.target.value) })} /></label>
          <div className="input-option-divider" />
          <label className="section-header"><span className="section-title">按键间距 <small>{(touchKeySpacingTenths / 10).toFixed(1)} dp</small></span><input aria-label="按键间距" type="range" min="30" max="60" step="1" value={touchKeySpacingTenths} onChange={event => setDraft({ ...draft, touch_key_spacing_tenths: Number(event.target.value) })} /></label>
          <div className="input-option-divider" />
          <label className="section-header"><span className="section-title">行间距 <small>{(touchRowSpacingTenths / 10).toFixed(1)} dp</small></span><input aria-label="行间距" type="range" min="40" max="100" step="1" value={touchRowSpacingTenths} onChange={event => setDraft({ ...draft, touch_row_spacing_tenths: Number(event.target.value) })} /></label>
          <div className="input-option-divider" />
          <label className="section-header"><span className="section-title">顶部语音入口 <small>在触屏键盘工具栏直接打开最近一次语音结果</small></span><input aria-label="顶部语音入口" className="toggle" type="checkbox" checked={draft.touch_voice_shortcut ?? false} onChange={event => setDraft({ ...draft, touch_voice_shortcut: event.target.checked })} /></label>
          <button type="button" className="danger-text" aria-label="恢复屏幕键盘默认设置" onClick={resetTouchKeyboardSettings}>恢复默认</button>
        </div>
        <div className="section panel-launch-card">
          <div className="section-header panel-launch-row"><span className="section-title">打开屏幕键盘<small>使用鼠标或触控方式输入文字与快捷按键</small></span><button type="button" className="secondary panel-open-button" disabled={!client.openScreenKeyboard} onClick={() => void openPanel(client.openScreenKeyboard)}>打开</button></div>
          <div className="panel-preview screen-keyboard-preview" aria-label="屏幕键盘预览"><div className="panel-preview-label">预览</div><ScreenKeyboardPreview theme={keyboardPreviewTheme} skin={touchKeyboardSkin} customDesign={customTouchKeyboardSkin} /></div>
        </div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "handwriting"} aria-label="手写识别板">
        <div className="section panel-launch-card">
          <div className="section-header panel-launch-row"><span className="section-title">打开手写识别板<small>使用鼠标或触控方式手写输入，自动识别候选汉字</small></span><button type="button" className="secondary panel-open-button" disabled={!client.openHandwriting} onClick={() => void openPanel(client.openHandwriting)}>打开</button></div>
          <div className="panel-preview handwriting-preview" aria-label="手写识别板预览"><div className="panel-preview-label">预览</div><div className="handwriting-mock"><div className="handwriting-canvas"><span className="handwriting-stroke">水</span></div><div className="handwriting-candidates"><span>水</span><span>永</span><span>木</span><span>未</span></div></div></div>
        </div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "voice"} aria-label="语音输入">
        {androidPlatform ? <div className="section panel-launch-card"><div className="section-title">Android 系统语音</div><p className="panel-inline-note">从键盘工具栏的“语音”入口调用设备上的系统语音识别服务。识别结果会回到键盘，确认后才插入当前输入框。</p></div> : <div className="section panel-launch-card"><div className="section-header panel-launch-row"><span className="section-title">打开语音输入<small>{linuxPlatform ? "录音和识别由已配置的 provider 服务完成" : "录音和识别在本机完成"}</small></span><button type="button" className="secondary panel-open-button" disabled={!client.openVoice} onClick={() => void openPanel(client.openVoice)}>打开</button></div>{linuxPlatform && <p className="panel-inline-note">没有 provider 时可继续使用 IBus 属性中的入口；服务负责录音、模型和凭据。</p>}</div>}
        <div className="section"><label className="section-header"><span className="section-title">语音输入<small>使用语音识别将录音转换为文字</small></span><input aria-label="启用语音输入" className="toggle" type="checkbox" checked={voiceInput.enabled} onChange={event => updateVoice({ enabled: event.target.checked })} /></label></div>
        {!androidPlatform && <div className="section"><label className="section-header"><span className="section-title">识别服务</span><select aria-label="识别服务" value={String(voiceInput.asr_provider)} onChange={event => updateVoice({ ...asrProviderUpdate(event.target.value, voiceInput), ...(linuxPlatform ? { asr_resource_id: "", doubao_boosting_table_id: "" } : {}) })}><option value="doubao">豆包</option><option value="siliconflow">SiliconFlow</option><option value="openai">OpenAI</option><option value="groq">Groq</option></select></label></div>}
        <div className="section"><label className="section-header"><span className="section-title">识别语言</span><input aria-label="识别语言" maxLength={64} list="settings-voice-language-options" value={voiceInput.language} onChange={event => updateVoice({ language: event.target.value })} /><datalist id="settings-voice-language-options"><option value="zh-cn">中文（普通话）</option><option value="en">English</option><option value="ja">日本語</option><option value="auto">自动识别</option></datalist></label></div>
        {!androidPlatform && <div className="section"><label className="section-header"><span className="section-title">识别模型<small>由 provider 服务选择对应模型</small></span><input aria-label="识别模型" value={voiceInput.asr_model ?? ""} onChange={event => updateVoice({ asr_model: event.target.value })} /></label></div>}
        {!androidPlatform && !linuxPlatform && <>
          <div className="section"><label className="section-header"><span className="section-title">识别接口地址<small>留空使用当前 provider 默认地址</small></span><input aria-label="识别接口地址" type="url" value={voiceInput.asr_endpoint ?? ""} onChange={event => updateVoice({ asr_endpoint: event.target.value })} /></label></div>
          <div className="section"><label className="section-header"><span className="section-title">识别 API Token<small>仅保存在本机设置中</small></span><SecretInput label="识别 API Token" value={voiceInput.asr_token ?? ""} onChange={value => updateVoice({ asr_token: value })} /></label></div>
          {voiceInput.asr_provider === "doubao" && <div className="section"><label className="section-header"><span className="section-title">Doubao App Key<small>旧版控制台鉴权可选</small></span><SecretInput label="Doubao App Key" value={voiceInput.asr_app_key ?? ""} onChange={value => updateVoice({ asr_app_key: value })} /></label></div>}
        </>}
        {!androidPlatform && <div className="section"><label className="section-header"><span className="section-title">Doubao 资源 ID<small>仅由 Doubao provider 使用</small></span><input aria-label="Doubao 资源 ID" value={voiceInput.asr_resource_id ?? ""} onChange={event => updateVoice({ asr_resource_id: event.target.value })} /></label></div>}
        {!androidPlatform && <div className="section"><label className="section-header"><span className="section-title">流式预编辑<small>provider 支持时显示实时识别片段</small></span><input aria-label="流式预编辑" className="toggle" type="checkbox" checked={voiceInput.stream_inline_preedit === true} onChange={event => updateVoice({ stream_inline_preedit: event.target.checked })} /></label></div>}
        {!androidPlatform && <div className="section"><label className="section-header"><span className="section-title">结果提交策略<small>由当前桌面宿主决定如何把识别结果交给前台窗口</small></span><select aria-label="结果提交策略" value={voiceInput.commit_mode ?? "tsf"} onChange={event => updateVoice({ commit_mode: event.target.value as VoiceInputPreferences["commit_mode"] })}><option value="tsf">输入法会话</option><option value="sendinput">系统按键</option><option value="ctrl_v">剪贴板粘贴</option></select></label></div>}
        {showVoiceCaptureDevices && <div className="section"><div className="section-title">录音设备<small>保存后从下一次录音生效，不打断当前录音</small></div>
          <label className="section-header"><span className="section-title">录音后端</span><select aria-label="录音后端" value={voiceInput.capture_backend ?? ""} onChange={event => updateVoice({ capture_backend: event.target.value as VoiceInputPreferences["capture_backend"], capture_device: "" })}><option value="">沿用服务设置</option><option value="auto">自动选择</option><option value="pulse">PulseAudio</option><option value="pipewire">PipeWire</option><option value="alsa">ALSA</option></select></label>
          {client.listVoiceCaptureDevices && <VoiceDevicePicker read={client.listVoiceCaptureDevices} backend={voiceInput.capture_backend ?? ""} device={voiceInput.capture_device ?? ""} choose={(capture_backend, capture_device) => updateVoice({ capture_backend, capture_device })} />}
          <label className="section-header"><span className="section-title">麦克风设备<small>填写 PulseAudio source、PipeWire 节点名称或序号、ALSA PCM 名称。选择后端后留空使用系统默认设备；沿用服务设置时留空使用服务设备。</small></span><input aria-label="麦克风设备" maxLength={128} value={voiceInput.capture_device ?? ""} onChange={event => updateVoice({ capture_device: event.target.value })} /></label>
        </div>}
        {!androidPlatform && <div className="section"><div className="section-title">{linuxPlatform ? "Linux provider 行为" : "录音行为"}<small>{linuxPlatform ? "这些选项会随请求传给用户管理的语音服务，不包含凭据" : "录音期间的提示音与静音由输入法在本机处理"}</small></div>
          {([[
            "sound_enabled", "语音提示音", true,
          ], [
            "start_sound", "开始录音提示音", true,
          ], [
            "end_sound", "结束录音提示音", true,
          ], [
            "mute_system_audio", "录音时静音其他音频", false,
          ]] as const).map(([key, label, enabledByDefault]) => <label className="section-header" key={key}><span className="section-title">{label}</span><input aria-label={label} className="toggle" type="checkbox" checked={enabledByDefault ? voiceInput[key] !== false : voiceInput[key] === true} onChange={event => updateVoice({ [key]: event.target.checked })} /></label>)}
        </div>}
        {!androidPlatform && voiceInput.asr_provider === "doubao" && <div className="section"><div className="section-title">豆包识别选项<small>{linuxPlatform ? "由 provider 服务应用" : "随识别请求发送给豆包"}</small></div>
          {([['doubao_enable_itn', '数字格式化', true], ['doubao_enable_punc', '标点预测', true], ['doubao_enable_ddc', '语义顺滑', false]] as const).map(([key, label, enabledByDefault]) => <label className="section-header" key={key}><span className="section-title">{label}</span><input aria-label={label} className="toggle" type="checkbox" checked={enabledByDefault ? voiceInput[key] !== false : voiceInput[key] === true} onChange={event => updateVoice({ [key]: event.target.checked })} /></label>)}
          <label className="section-header"><span className="section-title">热词表 ID</span><input aria-label="热词表 ID" value={voiceInput.doubao_boosting_table_id ?? ""} onChange={event => updateVoice({ doubao_boosting_table_id: event.target.value })} /></label>
        </div>}
        {!androidPlatform && <div className="section"><div className="section-title">文本润色 provider<small>识别结果可交给用户管理的服务润色</small></div>
          <label className="section-header"><span className="section-title">启用润色</span><input aria-label="启用文本润色" className="toggle" type="checkbox" checked={voiceInput.polish_text === true || voiceInput.polish_enabled === true} onChange={event => updateVoice({ polish_text: event.target.checked, polish_enabled: event.target.checked })} /></label>
          <label className="section-header"><span className="section-title">服务提供商</span><select aria-label="文本润色服务提供商" value={voiceInput.polish_provider ?? "siliconflow"} onChange={event => updateVoice(polishProviderUpdate(event.target.value, voiceInput))}><option value="siliconflow">SiliconFlow</option><option value="openai">OpenAI</option><option value="deepseek">DeepSeek</option><option value="groq">Groq</option></select></label>
          <label className="section-header"><span className="section-title">模型</span><input aria-label="文本润色模型" value={voiceInput.polish_model ?? ""} onChange={event => updateVoice({ polish_model: event.target.value })} /></label>
          {!linuxPlatform && <>
            <label className="section-header"><span className="section-title">润色接口地址<small>留空使用当前 provider 默认地址</small></span><input aria-label="润色接口地址" type="url" value={voiceInput.polish_endpoint ?? ""} onChange={event => updateVoice({ polish_endpoint: event.target.value })} /></label>
            <label className="section-header"><span className="section-title">润色 API Token<small>仅保存在本机设置中</small></span><SecretInput label="润色 API Token" value={voiceInput.polish_token ?? ""} onChange={value => updateVoice({ polish_token: value })} /></label>
          </>}
          <label className="section-header"><span className="section-title">润色方案</span><select aria-label="润色方案" value={polishSlot} onChange={event => updateVoice({ polish_prompt_id: event.target.value, polish_prompt: polishPromptFor(event.target.value, voiceInput) })}>{POLISH_PRESET_IDS.map(id => <option key={id} value={id}>{POLISH_PRESET_NAMES[id]}</option>)}<option value="custom_1">自定义一</option><option value="custom_2">自定义二</option><option value="custom_3">自定义三</option></select></label>
          <label className="section-header polish-prompt-row"><span className="section-title">润色提示词<small>{isPolishCustomSlot(polishSlot) ? "这一段会保存到所选的自定义方案" : "内置方案的完整提示词，可以就地修改"}</small></span><textarea aria-label="润色提示词" value={voiceInput.polish_prompt ?? ""} onChange={event => updateVoice({ polish_prompt: event.target.value, ...(polishSlotField(polishSlot) ? { [polishSlotField(polishSlot) as string]: event.target.value } : {}) })} /></label>
          <button type="button" className="secondary" disabled={(voiceInput.polish_prompt ?? "") === polishPromptFor(polishSlot, voiceInput)} onClick={() => updateVoice({ polish_prompt: polishPromptFor(polishSlot, voiceInput) })}>恢复默认</button>
        </div>}
        {!androidPlatform && <div className="section"><div className="section-title">{linuxPlatform ? "Linux IBus 快捷键" : "语音快捷键"}<small>{linuxPlatform ? "在当前输入上下文中切换语音录音；没有 provider 时快捷键不会拦截编辑器输入" : "输入法运行时全局生效，用于开始和结束语音录音"}</small></div>
          {([[
            "hotkey_ctrl_f9", "Ctrl+F9 切换语音",
          ], [
            "hotkey_ralt", "右 Alt 切换语音",
          ], [
            "hotkey_rctrl_ralt", "Ctrl+右 Alt 切换语音",
          ], [
            "hotkey_ctrl_win", "Ctrl+Win 切换语音",
          ], [
            "hotkey_hold_space_lock", "空格锁定语音",
          ]] as const).map(([key, label]) => <label className="section-header" key={key}><span className="section-title">{label}</span><input aria-label={label} className="toggle" type="checkbox" checked={draft.voice_input?.[key] !== false} onChange={event => setDraft({ ...draft, voice_input: { ...(draft.voice_input ?? {}), enabled: draft.voice_input?.enabled ?? true, language: draft.voice_input?.language ?? "zh-CN", [key]: event.target.checked } })} /></label>)}
        </div>}
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "ai"} aria-label="AI 辅助">
        <div className="section"><label className="section-header"><span className="section-title">启用 AI 辅助<small>为拼音联想和 Android 选中文字润色提供共享配置</small></span><input aria-label="启用 AI 辅助" className="toggle" type="checkbox" checked={ai.enabled} onChange={event => updateAi({ enabled: event.target.checked })} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">服务提供商</span><select aria-label="AI 服务提供商" value={ai.provider} onChange={event => updateAi({ provider: event.target.value })}><option value="deepseek">DeepSeek</option><option value="openai">OpenAI</option><option value="siliconflow">SiliconFlow</option><option value="groq">Groq</option></select></label></div>
        <div className="section"><label className="section-header"><span className="section-title">模型</span><input aria-label="AI 模型" value={ai.model} onChange={event => updateAi({ model: event.target.value })} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">接口地址</span><input aria-label="AI 接口地址" type="url" value={ai.endpoint} onChange={event => updateAi({ endpoint: event.target.value })} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">API Token<small>{aiOrigin ? `只用于 ${aiOrigin}` : "请先填写有效的 HTTPS 接口地址"}</small></span><input aria-label="AI API Token" type="password" autoComplete="off" disabled={!aiOrigin} value={aiToken} onChange={event => updateAiToken(event.target.value)} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">候选数量</span><input aria-label="AI 候选数量" type="number" min="1" max="10" value={ai.candidate_limit} onChange={event => updateAi({ candidate_limit: Math.max(1, Math.min(10, Number(event.target.value) || 3)) })} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">AI 联想提示词方案<small>使用选中的独立槽位；槽位留空时使用兼容提示词</small></span><select aria-label="AI 联想提示词方案" value={ai.prompt_id === "custom" ? "custom_1" : ai.prompt_id || "custom_1"} onChange={event => updateAi({ prompt_id: event.target.value })}><option value="custom_1">自定义一</option><option value="custom_2">自定义二</option><option value="custom_3">自定义三</option></select></label></div>
        <div className="section"><label className="section-title">兼容提示词<small>旧版提示词，所选自定义槽位留空时使用</small></label><textarea aria-label="AI 润色提示词" value={ai.prompt ?? defaultAiAssistant.prompt} onChange={event => updateAi({ prompt: event.target.value })} /></div>
        <div className="section"><label className="section-title">自定义提示词一<small>发送给 AI 联想服务的额外提示词</small></label><textarea aria-label="自定义提示词一" value={ai.prompt_custom_1} onChange={event => updateAi({ prompt_custom_1: event.target.value })} /></div>
        <div className="section"><label className="section-title">自定义提示词二</label><textarea aria-label="自定义提示词二" value={ai.prompt_custom_2} onChange={event => updateAi({ prompt_custom_2: event.target.value })} /></div>
        <div className="section"><label className="section-title">自定义提示词三</label><textarea aria-label="自定义提示词三" value={ai.prompt_custom_3} onChange={event => updateAi({ prompt_custom_3: event.target.value })} /></div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "feedback"} aria-label="反馈">
        <div className="section document-hero"><div className="document-eyebrow">反馈与交流</div><div className="document-hero-title">告诉我们你的想法</div><p>遇到问题或有功能建议时，可以通过以下渠道提交和交流。</p></div>
        <div className="feedback-list">
          <div className="section feedback-card"><div className="feedback-icon">GH</div><div className="feedback-body"><div className="feedback-title">GitHub Issues</div><p>适合提交可复现的问题、功能建议和开发讨论。</p><code>{platformIssuesUrl.replace("https://", "")}</code></div><button type="button" className="secondary" onClick={() => void openExternalUrl(platformIssuesUrl)}>查看 Issues</button></div>
          <div className="section feedback-card"><div className="feedback-icon">QQ</div><div className="feedback-body"><div className="feedback-title">QQ 交流群</div><p>适合中文用户进行日常交流、测试反馈和使用讨论。</p><code>群号：829919142</code></div><button type="button" className="secondary" onClick={() => { if (!client.copyText) return; void client.copyText("829919142").then(() => { setFeedbackCopied(true); window.setTimeout(() => setFeedbackCopied(false), 1600); }); }}>{feedbackCopied ? "已复制" : "复制群号"}</button></div>
          <div className="section feedback-card"><div className="feedback-icon">TG</div><div className="feedback-body"><div className="feedback-title">Telegram 群组</div><p>面向国际用户和开发者的即时讨论频道。</p><code>t.me/msimegroup</code></div><button type="button" className="secondary" onClick={() => void openExternalUrl("https://t.me/msimegroup")}>打开群组</button></div>
        </div>
        <div className="section document-note"><strong>提交问题时建议附上</strong><span>系统版本、输入方案、复现步骤、相关截图，以及 Debug 输出中的关键日志。</span></div>
      </fieldset>
      {!validCandidateFonts(draft) && <p role="alert">请在外观页修正字体：名称不能为空或超过 128 个 UTF-8 字节，补充字体最多 32 项。</p>}
      <footer className="settings-actions"><span>{dirty ? "有未保存的修改" : ""}</span><button type="submit" disabled={busy || !dirty || !validCandidateFonts(draft)}>{busy ? "处理中…" : "保存设置"}</button></footer>
    </form>}
    {page !== "typing-statistics" && page !== "account" && page !== "chat" && page !== "community" && <button className="secondary" disabled={busy} onClick={() => {
      if (!dirty || window.confirm("重新读取会放弃尚未保存的修改，是否继续？")) void reload();
    }}>重新读取</button>}
  </div></main></div></div>;
}
