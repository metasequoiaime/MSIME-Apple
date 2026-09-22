import { useConfirm } from "./core/confirm";
import { VoiceDevicePicker, type VoiceDeviceReader } from "./voice/voice-device-picker";
import {
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type PointerEvent as ReactPointerEvent,
} from "react";
import { HostActionButton } from "./keyboard/HostActionButton";
import {
  DICTIONARY_PAGE_SIZE,
  dictionaryPageStatus,
  parsePersonalDictionaryImport,
  personalDictionaryExample,
  readDictionaryFile,
  type PersonalDictionaryImportEntry,
} from "./dictionary/dictionary-file";
import { SkinCandidatePreview } from "./skin/skin-candidate-preview";
import { AppearanceCandidatePreview } from "./candidate/appearance-candidate-preview";
import {
  candidateFontSize,
  candidateFontSizes,
  candidatePreeditFontSize,
} from "./candidate/candidate-font-size";
import { candidateTextColor } from "./candidate/candidate-text-color";
import { useCandidatePreviewTheme } from "./candidate/candidate-preview-theme";
import { CandidateFontControls } from "./candidate/candidate-font-controls";
import { validCandidateFonts } from "./candidate/candidate-font-family";
import type { FontCatalogReader } from "./candidate/font-catalog";
import { SecretInput } from "./core/secret-input";
import {
  asrProviderUpdate,
  polishProviderUpdate,
  ASR_PROVIDER_DEFAULTS,
  DOUBAO_STREAM_ENDPOINTS,
  POLISH_PROVIDER_DEFAULTS,
} from "./voice/voice-providers";
import {
  POLISH_PRESET_IDS,
  POLISH_PRESET_NAMES,
  isPolishCustomSlot,
  normalizePolishSlot,
  polishPresetPrompt,
} from "./voice/polish-presets";
import { SkinToolbarPreview } from "./skin/skin-toolbar-preview";
import {
  ScreenKeyboardPreview,
  touchKeyboardSkinOptions,
} from "./keyboard/screen-keyboard-preview";
import type { TouchKeyboardSkin } from "./keyboard/screen-keyboard-preview";
import { TouchKeyboardSkinEditor } from "./keyboard/touch-keyboard-skin-editor";
import * as skin from "./keyboard/touch-skin-style";
import {
  defaultTouchKeyboardSkinDesign,
  type AiSkinClient,
  type CustomSkinLibraryClient,
  type TouchKeyboardSkinDesign,
} from "./keyboard/touch-keyboard-skin-design";
export type {
  AiSkinClient,
  AiSkinProposal,
  AiSkinProgress,
  CustomSkinLibraryAction,
  CustomSkinLibraryClient,
  SavedTouchKeyboardSkin,
  TouchKeyboardSkinDesign,
} from "./keyboard/touch-keyboard-skin-design";
import { ExternalSkins, type SkinCatalog } from "./skin/external-skins";
import { TypingStatisticsPage, type TypingStatisticsClient } from "./settings/typing-statistics";
import * as surface from "./keyboard/panel-surface-style";
import * as settings from "./settings/settings-style";
import * as doc from "./settings/document-style";
import {
  AccountPage,
  type AccountClient,
  type AccountCommunityDestination,
  type AppIconClient,
} from "./account/account-page";
import { ChatPage, type ChatClient } from "./chat/chat-page";
import { HomePage, type HomePageActions } from "./keyboard/home-page";
import { CommunitySkinsPage, type CommunitySkinClient } from "./community/community-skins";
import { candidateSkinPalette } from "./skin/skin-preview-palette";
import {
  CommunityHomePage,
  CommunityResourcesPage,
  type CommunityResourceClient,
} from "./community/community-resources";
export { useConfirm, type ConfirmRequest } from "./core/confirm";
export { decodeDictionaryBytes, readDictionaryFile } from "./dictionary/dictionary-file";
export {
  TypingStatisticsPage,
  retentionChoices,
  type StatisticsRetention,
  activityMetrics,
  addDays,
  currentStreak,
  formatActiveTime,
  longestStreak,
  type ActivityMetrics,
  type TypingBreakdown,
  type TypingStatistics,
  type TypingStatisticsClient,
  type TypingStatisticsStatus,
} from "./settings/typing-statistics";
export {
  AccountPage,
  type AccountChallenge,
  type AccountClient,
  type AccountCommunityDestination,
  type AccountPreferenceSchema,
  type AccountPreferences,
  type AccountPreferenceValue,
  type AccountProfile,
  type AccountProviders,
  type AccountUser,
  type AppIconClient,
  type AppIconInfo,
  type SettingsSyncClient,
} from "./account/account-page";
export {
  ChatPage,
  type ChatClient,
  type ChatMessage,
  type ChatModel,
  type ChatModels,
} from "./chat/chat-page";
export { HomePage, type HomePageActions } from "./keyboard/home-page";
export {
  WelcomeFlowPage,
  type OnboardingActions,
  type OnboardingInputScheme,
} from "./account/onboarding-page";
export { SettingsStartupPage } from "./settings/settings-startup-page";
export {
  CommunitySkinsPage,
  type CommunitySkin,
  type CommunitySkinClient,
  type CommunitySkinDownload,
  type CommunitySkinPage,
  type CommunitySkinTrial,
} from "./community/community-skins";
export {
  CommunityHomePage,
  CommunityResourcesPage,
  type CommunityLocalDictionaryClient,
  type CommunityResource,
  type CommunityResourceApplication,
  type CommunityResourceClient,
  type CommunityResourceContent,
  type CommunityResourceKind,
  type CommunityResourcePage,
  type CommunityResourceScope,
  type CommunitySharedWord,
} from "./community/community-resources";
export type { SkinCatalog, ExternalSkin } from "./skin/external-skins";
import type { SkinImageReader } from "./skin/skin-image";
export type { SkinImage, SkinImageReader } from "./skin/skin-image";
import type { SkinFontReader } from "./skin/skin-font";
export type { SkinFont, SkinFontReader } from "./skin/skin-font";
export {
  POLISH_CUSTOM_IDS,
  POLISH_PRESETS,
  POLISH_PRESET_IDS,
  POLISH_PRESET_NAMES,
  isPolishCustomSlot,
  normalizePolishSlot,
  polishPresetPrompt,
  type PolishPresetId,
} from "./voice/polish-presets";
export {
  ASR_PROVIDER_DEFAULTS,
  POLISH_PROVIDER_DEFAULTS,
  asrProviderUpdate,
  polishProviderUpdate,
  type ProviderDefaults,
} from "./voice/voice-providers";
export {
  candidateTemplate,
  candidateThemeStylesheet,
  type CandidateAppearance,
  type CandidateOrientation,
  type CandidateTheme,
} from "./candidate/candidate-themes";
import {
  compareVersions,
  describeInstallerTrust,
  parseVersion,
  validateGitHubRelease,
  validateManifest,
  type GitHubRelease,
  type UpdateManifest,
  type ValidatedUpdate,
} from "./settings/update-manifest";
export {
  serializeWindowHostMessage,
  type WindowControl,
  type WindowHostMessage,
  type WindowResizeEdge,
} from "./keyboard/window-host";
export { emojiDisplayName } from "./keyboard/panels";
export type { TouchKeyboardSkin } from "./keyboard/screen-keyboard-preview";
export {
  CloudCandidatesPanel,
  CloudClipboardPanel,
  CloudDictionaryApplyPanel,
  CloudDictionaryCatalogPanel,
  CloudDictionaryFilesPanel,
  CloudDictionaryPanel,
  EmojiPanel,
  HandwritingPanel,
  KeyboardPanel,
  VoicePanel,
  type CloudCandidate,
  type CloudCandidateKind,
  type CloudClipboardAction,
  type CloudClipboardPanelClient,
  type CloudDictionaryAction,
  type CloudDictionaryCatalogEntry,
  type CloudDictionaryEntry,
  type CloudDictionaryFileFormat,
  type CloudDictionaryKind,
  type CloudDictionaryPanelClient,
  type CloudDictionarySnapshotMetadata,
  type CloudDictionarySnapshotRequest,
  type CloudFixedPosition,
  type CloudRankingMode,
  type EmojiPanelClient,
  type PanelClient,
  type VoicePanelClient,
} from "./keyboard/panels";
export type { EmojiCatalogGroup } from "./emoji/emoji-catalog";
import {
  customTranslationsExample,
  customTranslationsWithinBounds,
  parseCustomTranslations,
} from "./dictionary/custom-translations";
export {
  customTranslationsExample,
  customTranslationsWithinBounds,
  parseCustomTranslations,
  type CustomTranslationEntry,
  type CustomTranslationReport,
} from "./dictionary/custom-translations";
export type { VoiceCaptureDevice, VoiceDeviceReader } from "./voice/voice-device-picker";

export type HelpcodeSchema =
  | "lantian"
  | "ziranma"
  | "shouyou2_0"
  | "shouyouplus"
  | "xiaohe"
  | "jiajia";
export type HelpcodePreferences = {
  enabled: boolean;
  schema: HelpcodeSchema;
  show_in_candidate_window?: boolean;
};
const defaultHelpcode: Record<"quanpin_helpcode" | "shuangpin_helpcode", HelpcodePreferences> = {
  quanpin_helpcode: { enabled: true, schema: "ziranma", show_in_candidate_window: false },
  shuangpin_helpcode: { enabled: true, schema: "lantian", show_in_candidate_window: true },
};
export type KeybindingPreferences = {
  switch_language_shift: boolean;
  switch_language_ctrl: boolean;
  switch_language_ctrl_alt_space: boolean;
  toggle_character_set_ctrl_shift_f: boolean;
  toggle_fullwidth_option_shift_h: boolean;
};
const defaultKeybindings: KeybindingPreferences = {
  switch_language_shift: true,
  switch_language_ctrl: false,
  switch_language_ctrl_alt_space: true,
  toggle_character_set_ctrl_shift_f: true,
  toggle_fullwidth_option_shift_h: true,
};
export type FuzzyPinyinPreferences = { enabled: boolean; rules: string[]; seeded?: boolean };
const defaultFuzzyPinyin: FuzzyPinyinPreferences = { enabled: false, rules: [] };
const fuzzyPinyinGroups: [string, [string, string][]][] = [
  [
    "平翘舌",
    [
      ["z-zh", "z ↔ zh"],
      ["c-ch", "c ↔ ch"],
      ["s-sh", "s ↔ sh"],
    ],
  ],
  [
    "声母",
    [
      ["n-l", "n ↔ l"],
      ["f-h", "f ↔ h"],
      ["r-l", "r ↔ l"],
    ],
  ],
  [
    "前后鼻音",
    [
      ["an-ang", "an ↔ ang"],
      ["en-eng", "en ↔ eng"],
      ["in-ing", "in ↔ ing"],
    ],
  ],
  [
    "其他韵母",
    [
      ["ian-iang", "ian ↔ iang"],
      ["uan-uang", "uan ↔ uang"],
    ],
  ],
];
const fuzzyPinyinRuleIds = fuzzyPinyinGroups.flatMap(([, rules]) => rules.map(([id]) => id));
export type TouchKeyboardScheme =
  | "quanpin"
  | "nine_key"
  | "xiaohe"
  | "ziranma"
  | "microsoft"
  | "shoudao"
  | "wubi"
  | "japanese_nine_key"
  | "japanese"
  | "handwriting"
  | "thoughtful_reply";
export type TouchKeyboardSchemePreferences = {
  enabled: TouchKeyboardScheme[];
  selected?: TouchKeyboardScheme;
};
const touchKeyboardSchemeOptions: [TouchKeyboardScheme, string][] = [
  ["quanpin", "全拼 26 键"],
  ["nine_key", "全拼 9 键"],
  ["xiaohe", "小鹤双拼"],
  ["ziranma", "自然码双拼"],
  ["microsoft", "微软双拼"],
  ["shoudao", "首道双拼"],
  ["wubi", "86 五笔"],
  ["japanese_nine_key", "日语 9 键"],
  ["japanese", "日语 26 键"],
  ["handwriting", "手写"],
  ["thoughtful_reply", "高情商回复"],
];
const allTouchKeyboardSchemes = touchKeyboardSchemeOptions.map(([scheme]) => scheme);

function inferredTouchKeyboardScheme(preferences: Preferences): TouchKeyboardScheme {
  const enabled = preferences.touch_keyboard_schemes?.enabled ?? allTouchKeyboardSchemes;
  const selected = preferences.touch_keyboard_schemes?.selected;
  if (selected && enabled.includes(selected)) return selected;
  let inferred: TouchKeyboardScheme =
    preferences.scheme === "shuangpin" ? preferences.shuangpin_profile : preferences.scheme;
  if (preferences.touch_keyboard_layout === "handwriting" && preferences.scheme === "quanpin")
    inferred = "handwriting";
  else if (preferences.touch_keyboard_layout === "nine_key")
    inferred = preferences.scheme === "japanese" ? "japanese_nine_key" : "nine_key";
  return enabled.includes(inferred) ? inferred : (enabled[0] ?? "quanpin");
}

function selectTouchKeyboardScheme(
  preferences: Preferences,
  selected: TouchKeyboardScheme,
): Preferences {
  const touch_keyboard_schemes = {
    enabled: preferences.touch_keyboard_schemes?.enabled ?? allTouchKeyboardSchemes,
    selected,
  };
  if (["xiaohe", "ziranma", "microsoft", "shoudao"].includes(selected))
    return {
      ...preferences,
      scheme: "shuangpin",
      last_chinese_scheme: "shuangpin",
      shuangpin_profile: selected as Preferences["shuangpin_profile"],
      touch_keyboard_layout: "twenty_six_key",
      touch_keyboard_schemes,
    };
  if (selected === "japanese" || selected === "japanese_nine_key")
    return {
      ...preferences,
      scheme: "japanese",
      last_chinese_scheme:
        preferences.scheme === "japanese" ? preferences.last_chinese_scheme : preferences.scheme,
      touch_keyboard_layout: selected === "japanese_nine_key" ? "nine_key" : "twenty_six_key",
      touch_keyboard_schemes,
    };
  if (selected === "wubi")
    return {
      ...preferences,
      scheme: "wubi",
      last_chinese_scheme: "wubi",
      touch_keyboard_layout: "twenty_six_key",
      touch_keyboard_schemes,
    };
  return {
    ...preferences,
    scheme: "quanpin",
    last_chinese_scheme: "quanpin",
    touch_keyboard_layout:
      selected === "nine_key"
        ? "nine_key"
        : selected === "handwriting"
          ? "handwriting"
          : "twenty_six_key",
    touch_keyboard_schemes,
  };
}
const helpcodeSchemas: [HelpcodeSchema, string][] = [
  ["lantian", "蓝天小雨点"],
  ["ziranma", "自然码"],
  ["shouyou2_0", "首右2.0"],
  ["shouyouplus", "首右plus"],
  ["xiaohe", "小鹤"],
  ["jiajia", "加加"],
];
/**
 * The sidebar, in the reference window's order.
 *
 * Everything from 外观 down is the reference's own list, item for item and in its sequence, so a
 * user who knows that window finds the same page in the same place here. The pages this client has
 * and that window does not -- the account, the AI conversation, the community and the typing
 * statistics -- sit ahead of it as a block of their own rather than being interleaved, which is
 * also the group the mobile hosts promote. macOS reorders this into `macosSidebarGroups`, because
 * its own reference window groups rather than lists.
 */
const pages = [
  { id: "home", title: "首页", icon: new URL("./assets/msime.svg", import.meta.url).href },
  { id: "account", title: "我的", icon: new URL("./assets/account.svg", import.meta.url).href },
  { id: "chat", title: "AI 对话", icon: new URL("./assets/help.svg", import.meta.url).href },
  { id: "community", title: "社区", icon: new URL("./assets/community.svg", import.meta.url).href },
  {
    id: "typing-statistics",
    title: "打字统计",
    icon: new URL("./assets/statistics.svg", import.meta.url).href,
  },
  {
    id: "appearance",
    title: "外观",
    icon: new URL("./assets/appearance.svg", import.meta.url).href,
  },
  { id: "input", title: "输入", icon: new URL("./assets/input.svg", import.meta.url).href },
  { id: "helpcode", title: "辅助码", icon: new URL("./assets/helpcode.svg", import.meta.url).href },
  {
    id: "shortcuts",
    title: "快捷键",
    icon: new URL("./assets/shortcut.svg", import.meta.url).href,
  },
  {
    id: "dictionary",
    title: "词库",
    icon: new URL("./assets/dictionary.svg", import.meta.url).href,
  },
  { id: "skin", title: "皮肤", icon: new URL("./assets/skin.svg", import.meta.url).href },
  {
    id: "voice",
    title: "语音输入",
    icon: new URL("./assets/voice-input.svg", import.meta.url).href,
  },
  {
    id: "screen-keyboard",
    title: "屏幕键盘",
    icon: new URL("./assets/screen-keyboard.svg", import.meta.url).href,
  },
  {
    id: "handwriting",
    title: "手写识别板",
    icon: new URL("./assets/handwriting.svg", import.meta.url).href,
  },
  { id: "tools", title: "实用功能", icon: new URL("./assets/utilities.svg", import.meta.url).href },
  { id: "ai", title: "AI 辅助", icon: new URL("./assets/ai.svg", import.meta.url).href },
  {
    id: "floating-toolbar",
    title: "悬浮工具栏",
    icon: new URL("./assets/floating-toolbar.svg", import.meta.url).href,
  },
  { id: "help", title: "帮助", icon: new URL("./assets/help.svg", import.meta.url).href },
  { id: "about", title: "关于", icon: new URL("./assets/about.svg", import.meta.url).href },
  { id: "feedback", title: "反馈", icon: new URL("./assets/feedback.svg", import.meta.url).href },
] as const;
/**
 * macOS groups its sidebar the way the reference window does: what you type with, what it looks
 * like, what it stores, then where to get help. Pages the reference has no counterpart for keep
 * their place in a group of their own rather than disappearing -- they are features this client
 * has and that window does not.
 */
const macosSidebarGroups = [
  ["input", "helpcode", "shortcuts", "tools", "voice"],
  ["appearance", "skin", "floating-toolbar"],
  ["dictionary", "account"],
  ["help", "feedback", "about"],
] as const satisfies readonly (readonly SettingsPageId[])[];
/**
 * The macOS help page. The reference window answers the three questions a new user actually has --
 * how do I type, why is there English next to the candidates, and why is it not in my input menu --
 * as term/description rows rather than prose, so each answer is findable without reading the page.
 */
const macosHelpCards = [
  {
    title: "开始输入",
    rows: [
      {
        term: "Shift",
        text: "在中文和英文之间切换。切换时光标下方会短暂显示「中」或「英」，可以在快捷键里关掉。",
      },
      { term: "数字键 1–9", text: "选中候选栏里对应位置的词，空格上屏第一个。" },
      {
        term: "翻页",
        text: "默认是减号和等号（- / =）。在快捷键页可以换成逗号句号（, / .）或方括号（[ / ]）。",
      },
      { term: "Option+Shift+H", text: "切换全角与半角。" },
    ],
  },
  {
    title: "候选词释义",
    rows: [
      {
        term: "离线优先",
        text: "常见词直接用本机词典，不联网、没有延迟。词典没收录的才会去问在线服务，所以生僻字和多字词可能要等半秒左右才出现。",
      },
      {
        term: "需要账号",
        text: "在线那部分走水杉账号。安装时会自动创建一个本机账号，通常不需要你做任何事。",
      },
      { term: "两种语言", text: "可以同时显示两种语言的释义，在输入页的候选词翻译里设置。" },
      {
        term: "Tab",
        text: "在候选词和它的释义之间切换要上屏的那一列，Shift+Tab 反向。切到哪一列，那一列就会加下划线，数字键、空格和点击上屏的都是它。",
      },
      {
        term: "Option / Control + 数字",
        text: "不切换，直接上屏那一格的释义：Option 是目标语言，Control 是第二语言。",
      },
    ],
  },
  {
    title: "遇到问题",
    rows: [
      {
        term: "输入菜单里没有",
        text: "到「系统设置 › 键盘 › 文字输入 › 输入法」里添加水杉输入法。刚安装或刚更新过时，可能需要在输入菜单里切走再切回来。",
      },
      {
        term: "候选旁没有释义",
        text: "先确认输入页的候选词翻译是开着的。词典没收录的词要联网查询，断网时只会显示词典里有的那些。",
      },
      { term: "词库没有更新", text: "词库更新随版本发布。在「关于」页检查更新。" },
    ],
  },
] as const;
const logo = new URL("./assets/msime.svg", import.meta.url).href;
const windowIcons = {
  minimize: new URL("./assets/minimize.svg", import.meta.url).href,
  maximize: new URL("./assets/maximize.svg", import.meta.url).href,
  restore: new URL("./assets/restore.svg", import.meta.url).href,
  close: new URL("./assets/close.svg", import.meta.url).href,
};
const fallbackAppVersion = "0.1.0";
const releasesPageUrl = "https://github.com/metasequoiaime/msime/releases";
const linuxReleasesPageUrl = "https://github.com/metasequoiaime/msime/releases";
const updateManifestUrl = "https://msime.app/update.json";
const clientLatestReleaseUrl = "https://api.github.com/repos/metasequoiaime/msime/releases/latest";
const licenseUrl = "https://github.com/metasequoiaime/msime/blob/develop/LICENSE";
const privacyUrl = "https://msime.app/privacy/";
const androidPrivacyUrl = "https://msime.app/privacy/";
const linuxLicenseUrl = "https://github.com/metasequoiaime/msime/blob/develop/LICENSE";
const linuxIssuesUrl = "https://github.com/metasequoiaime/msime/issues";
const desktopDownloadUrl = "https://msime.app/download/";
const documentationUrl = "https://msime.app/docs/";
const handwritingSdkPrivacyUrl = "https://developers.google.com/ml-kit/terms";

export type HostPlatform = "windows" | "macos" | "linux" | "android" | "ios" | "harmony";
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
  floating_toolbar_components: boolean;
  /** The toolbar carries a handwriting panel button, which only this client's macOS toolbar does. */
  floating_toolbar_handwriting?: boolean;
  /** The toolbar carries a voice input button, for the same reason. */
  floating_toolbar_voice?: boolean;
  mode_switch_shortcuts: boolean;
  panel_shortcuts: boolean;
  number_row_selection?: boolean;
  voice_capture_devices: boolean;
  candidate_font_controls: boolean;
  candidate_row_colors: boolean;
  candidate_selection_appearance: boolean;
  candidate_follow_cursor: boolean;
  input_mode_hud?: boolean;
  candidate_english_font?: boolean;
  english_suggestions?: boolean;
  helpcode_shift_entry?: boolean;
  skin_directory_import?: boolean;
  shuangpin_preedit?: boolean;
  ai_provider_credentials?: boolean;
  voice_commit_mode?: boolean;
  /** The OS release the host is running on, for the feedback page to attach. */
  os_version?: string;
}

/** Superseded by the host-provided capabilities; used only when a host predates them. */
function isLinuxDesktop(): boolean {
  if (typeof navigator === "undefined") return false;
  const userAgent = navigator.userAgent;
  return /\bLinux\b/i.test(userAgent) && !/\bjsdom\b/i.test(userAgent);
}

export type ThemeMode = "dark" | "light" | "system";
export type SurfaceTheme = "follow" | "dark" | "light";
export { useCandidatePreviewTheme } from "./candidate/candidate-preview-theme";

function resolveSettingsTheme(theme: ThemeMode, surface: SurfaceTheme): "dark" | "light" {
  if (surface !== "follow") return surface;
  if (theme !== "system") return theme;
  return typeof window !== "undefined" &&
    typeof window.matchMedia === "function" &&
    window.matchMedia("(prefers-color-scheme: light)").matches
    ? "light"
    : "dark";
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
  menu_theme?: SurfaceTheme;
  ai_assistant?: AiAssistantPreferences;
  custom_translation?: { enabled: boolean; endpoint: string; api_key: string };
  tencent_tmt?: { enabled: boolean; secret_id: string; secret_key: string; region: string };
  niutrans?: { enabled: boolean; app_id: string; apikey: string };
  voice_input?: VoiceInputPreferences;
  local_modes?: LocalModePreferences;
  clipboard_history?: boolean;
  cloud_candidates?: boolean;
  candidate_translations?: boolean;
  candidate_english_gloss?: boolean;
  english_suggestions?: boolean;
  translation_target_language?: "en" | "fr" | "ja" | "es" | "ru" | "de" | "ko";
  /** Optional second candidate-translation language; null/absent keeps one gloss row. */
  translation_secondary_language?: "en" | "fr" | "ja" | "es" | "ru" | "de" | "ko" | null;
  floating_toolbar?: FloatingToolbarPreferences;
  mixed_input?: MixedInputPreferences;
  fuzzy_pinyin?: FuzzyPinyinPreferences;
  frequency?: FrequencyPreferences;
  word_character?: { enabled: boolean; keys: "brackets" | "minus_equal" };
  navigation?: NavigationPreferences;
  keybindings?: KeybindingPreferences;
  scheme: "quanpin" | "shuangpin" | "wubi" | "japanese";
  /** Width used when desktop hosts commit printable ASCII characters. */
  character_width?: "halfwidth" | "fullwidth";
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
  /** macOS exposes the native shuangpin preedit presentation in the appearance page. */
  shuangpin_preedit_uses_raw?: boolean;
  wubi_mixed_pinyin?: boolean;
  candidate_page_size: number;
  number_row_selection?: boolean;
  candidate_font_size?: number;
  candidate_preedit_font_size?: number;
  candidate_text_color?: string | null;
  candidate_follow_cursor?: boolean;
  /** macOS-only non-activating badge shown after switching Chinese/English input. */
  input_mode_hud?: boolean;
  candidate_number_color?: string | null;
  candidate_accent_color?: string | null;
  candidate_selected_color?: string | null;
  candidate_hover_color?: string | null;
  candidate_surface_color?: string | null;
  candidate_border_color?: string | null;
  candidate_font_family?: string;
  candidate_english_font?: string | null;
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
  smart_punctuation_space_convert?: boolean;
  smart_punctuation_direct_digit?: boolean;
  smart_punctuation_direct_letter?: boolean;
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
export type AiAssistantClient = {
  // `provider` is for the hosts whose provider service holds the credential: it
  // is what that service checks its private configuration against. The hosts that
  // hold the token themselves ignore it and authenticate with `token`.
  fetchModels(configuration: {
    endpoint: string;
    token: string;
    provider: string;
  }): Promise<string[]>;
  test(configuration: {
    endpoint: string;
    model: string;
    prompt: string;
    token: string;
    text: string;
    provider: string;
  }): Promise<string>;
};
export type ApiCredentialTestService =
  | "translation.tencent"
  | "translation.niutrans"
  | "translation.custom"
  | "voice.asr"
  | "voice.polish"
  | "ai.assistant";
export type ApiCredentialTestResult = { ok: boolean; message: string };
export type VoiceInputPreferences = {
  enabled: boolean;
  language: string;
  capture_backend?: "" | "auto" | "pulse" | "pipewire" | "alsa" | "windows" | "macos" | "harmony";
  capture_device?: string;
  asr_provider?: string;
  asr_endpoint?: string;
  asr_token?: string;
  asr_tokens?: Record<string, string>;
  asr_app_key?: string;
  doubao_auth_mode?: "api_key" | "legacy";
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
  /** Absolute path to a local Whisper model file; only the `local` provider reads it. */
  asr_model_path?: string;
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
/**
 * `models` are the models the provider is known to accept and `documentation`
 * is where it explains the endpoint and how to obtain an API key, both taken
 * from the Apple `AIProviderPreset`. They are presentation only: the request
 * still sends whatever model preferences hold, and 自定义 has neither.
 */
export const AI_PROVIDER_OPTIONS: readonly {
  id: string;
  title: string;
  endpoint: string;
  model: string;
  models?: readonly string[];
  documentation?: string;
}[] = [
  {
    id: "everyapi",
    title: "EveryAPI",
    endpoint: "https://api.everyapi.ai/v1/chat/completions",
    model: "deepseek-v4-flash",
    models: ["deepseek-v4-flash", "deepseek-v4-pro", "claude-sonnet-5", "glm-5.3-flash"],
    documentation: "https://everyapi.ai/models",
  },
  {
    id: "openai",
    title: "OpenAI",
    endpoint: "https://api.openai.com/v1/chat/completions",
    model: "gpt-4.1-mini",
    models: ["gpt-4.1-mini"],
    documentation: "https://developers.openai.com/api/docs/models/gpt-4.1-mini",
  },
  {
    id: "anthropic",
    title: "Anthropic · Claude",
    endpoint: "https://api.anthropic.com/v1/chat/completions",
    model: "claude-sonnet-4-6",
    models: ["claude-sonnet-4-6", "claude-opus-5"],
    documentation: "https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/openai-sdk",
  },
  {
    id: "gemini",
    title: "Google · Gemini",
    endpoint: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
    model: "gemini-3.8-flash",
    models: ["gemini-3.8-flash", "gemini-2.5-flash"],
    documentation: "https://ai.google.dev/gemini-api/docs/openai",
  },
  {
    id: "deepseek",
    title: "DeepSeek",
    endpoint: "https://api.deepseek.com/chat/completions",
    model: "deepseek-v4-flash",
    models: ["deepseek-v4-flash", "deepseek-v4-pro"],
    documentation: "https://api-docs.deepseek.com/",
  },
  {
    id: "qwen",
    title: "通义千问 · 阿里云百炼",
    endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
    model: "qwen-plus",
    models: ["qwen-plus"],
    documentation: "https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope",
  },
  {
    id: "kimi",
    title: "Kimi · 月之暗面",
    endpoint: "https://api.moonshot.cn/v1/chat/completions",
    model: "kimi-k2.6",
    models: ["kimi-k2.6", "kimi-k2.5"],
    documentation: "https://platform.kimi.com/docs/api/chat",
  },
  {
    id: "zhipu",
    title: "智谱 · GLM",
    endpoint: "https://open.bigmodel.cn/api/paas/v4/chat/completions",
    model: "glm-4.7",
    models: ["glm-4.7", "glm-4.7-flashx"],
    documentation: "https://docs.bigmodel.cn/cn/guide/models/text/glm-4.7",
  },
  {
    id: "siliconflow",
    title: "硅基流动",
    endpoint: "https://api.siliconflow.cn/v1/chat/completions",
    model: "Qwen/Qwen3.6-27B",
    models: ["Qwen/Qwen3.6-27B"],
    documentation: "https://docs.siliconflow.cn/docs/userguide/capabilities/text-generation",
  },
  {
    id: "groq",
    title: "Groq",
    endpoint: "https://api.groq.com/openai/v1/chat/completions",
    model: "llama-3.3-70b-versatile",
    models: ["llama-3.3-70b-versatile", "llama-3.1-8b-instant"],
    documentation: "https://console.groq.com/docs/quickstart",
  },
  {
    id: "openrouter",
    title: "OpenRouter",
    endpoint: "https://openrouter.ai/api/v1/chat/completions",
    model: "openrouter/auto",
    models: ["openrouter/auto"],
    documentation: "https://openrouter.ai/docs/quickstart",
  },
  { id: "custom", title: "自定义", endpoint: "", model: "" },
];
const defaultAiAssistant: AiAssistantPreferences = {
  enabled: false,
  provider: "deepseek",
  model: "deepseek-v4-flash",
  endpoint: "https://api.deepseek.com/chat/completions",
  candidate_limit: 3,
  token: "",
  tokens: {},
  prompt_id: "custom_1",
  prompt: "请润色以下文字，保持原意，只返回修改后的文字。",
  prompt_custom_1: "",
  prompt_custom_2: "",
  prompt_custom_3: "",
};

/** Switch providers like the Apple settings page: preset values follow the
 * provider, while a deliberately edited custom endpoint/model are preserved. */
export function aiProviderUpdate(
  provider: string,
  current: AiAssistantPreferences,
): Partial<AiAssistantPreferences> {
  const next =
    AI_PROVIDER_OPTIONS.find((option) => option.id === provider) ??
    AI_PROVIDER_OPTIONS[AI_PROVIDER_OPTIONS.length - 1];
  const previous = AI_PROVIDER_OPTIONS.find((option) => option.id === current.provider);
  return {
    provider: next.id,
    endpoint:
      !current.endpoint.trim() || current.endpoint === previous?.endpoint
        ? next.endpoint
        : current.endpoint,
    model: !current.model.trim() || current.model === previous?.model ? next.model : current.model,
  };
}
// asr_provider mirrors client-core's default; the two disagreeing meant a host
// wrote a provider no backend implements.
const defaultVoiceInput: VoiceInputPreferences = {
  enabled: true,
  language: "zh-CN",
  asr_provider: "doubao",
  doubao_auth_mode: "api_key",
  asr_resource_id: "volc.seedasr.sauc.duration",
};

export function aiCredentialOrigin(endpoint: string): string | null {
  if (!endpoint || endpoint.length > 2048 || /[\u0000-\u001f\u007f]/.test(endpoint)) return null;
  try {
    const url = new URL(endpoint.trim());
    if (url.protocol !== "https:" || !url.hostname || url.username || url.password || url.hash)
      return null;
    return `https://${url.hostname.toLowerCase()}:${url.port || "443"}`;
  } catch {
    return null;
  }
}

const defaultCustomTranslation = { enabled: false, endpoint: "", api_key: "" };
const defaultTencentTranslation = {
  enabled: true,
  secret_id: "",
  secret_key: "",
  region: "ap-guangzhou",
};
const defaultNiuTrans = { enabled: false, app_id: "", apikey: "" };
export type ExternalSkinCatalog = {
  scanned: boolean;
  directory?: string;
  revision?: number;
  packages: Array<{ id: string; title: string; description?: string; valid?: boolean }>;
  issues?: string[];
};
export type Snapshot = {
  format_version: number;
  revision: number;
  preferences: Preferences;
  candidate_skin_catalog?: ExternalSkinCatalog;
};
export type LocalDictionaryKind = "pinyin" | "wubi" | "quick_phrase" | "english";
export type LocalDictionaryFormat = "standard" | "windows" | "rime" | "hans";
export type DictionaryEntry = {
  kind: LocalDictionaryKind;
  key: string;
  value: string;
  weight: number;
};
export type DictionaryFailure = { request_id: string; label: string; error: string };
/** Mirrors the import response from `client-core::dictionary_import`. */
export interface DictionaryImportResult {
  applied: number;
  /** Rows examined and skipped. Absent from hosts that predate the report. */
  failed?: number;
  /** Rows beyond the per-file cap were not examined. */
  truncated?: boolean;
  /** The file was read with its two columns the other way round from the format chosen. */
  swapped?: boolean;
  first_failures?: { line: number; issue: string }[];
}

/** A short account of an import the user can act on. */
export function describeImportResult(kind: string, result: DictionaryImportResult): string {
  const parts = [`${kind}导入完成，共 ${result.applied} 条。`];
  if (result.failed) {
    const failures = result.first_failures ?? [];
    const lines = failures.map((failure) => failure.line).join("、");
    parts.push(
      lines ? `跳过 ${result.failed} 行，首先出现在第 ${lines} 行。` : `跳过 ${result.failed} 行。`,
    );
    // "rejected" means the row parsed but the engine refused it, which is a
    // different thing for the user to fix than a malformed line.
    if (failures.some((failure) => failure.issue === "rejected")) {
      parts.push("其中部分行的编码与词不匹配，例如简拼、或音节数与汉字数不一致。");
    }
  }
  if (result.truncated) parts.push("文件过长，仅导入了前一部分。");
  // Said rather than done quietly: which column holds the code is the one thing about the file the
  // reader may want to check, and the same settings page in the Windows version exports the two
  // orders for different dictionaries.
  if (result.swapped) parts.push("该文件的两列与所选格式相反，已按文件本身的顺序读取。");
  return parts.join("");
}

/** What the packaged dictionary is: the specification it was built to, and where it came from. */
export type DictionaryManifest = { profile: string; sourceCommit: string };

export interface DictionaryClient {
  list(
    offset: number,
    limit: number,
    kind?: LocalDictionaryKind,
    query?: string,
  ): Promise<{
    entries: DictionaryEntry[];
    has_more: boolean;
    pending_count?: number;
    failed_requests?: DictionaryFailure[];
    snapshot_error?: string | null;
    page_offset?: number;
    requested_page_offset?: number;
  }>;
  edit(
    previous: DictionaryEntry | null,
    replacement: DictionaryEntry | null,
    request_id: string,
  ): Promise<void>;
  import?(
    kind: LocalDictionaryKind,
    format: LocalDictionaryFormat,
    text: string,
    request_id: string,
  ): Promise<DictionaryImportResult>;
  importPersonal?(
    text: string,
    request_id: string,
  ): Promise<{ queued: boolean; pending_count: number }>;
  export?(
    kind: LocalDictionaryKind,
    format: Exclude<LocalDictionaryFormat, "rime" | "hans">,
    offset: number,
    limit: number,
  ): Promise<{ text: string; has_more: boolean }>;
  retry?(request_id: string): Promise<void>;
  dismissFailure?(request_id: string): Promise<void>;
}
const personalDictionaryExportKinds: [LocalDictionaryKind, string][] = [
  ["pinyin", "拼音"],
  ["wubi", "五笔"],
  ["quick_phrase", "快捷短语"],
  ["english", "英文"],
];

/** The encoding rules shown beside the Apple personal-dictionary editor. */
export function dictionaryKindKeyHint(kind: LocalDictionaryKind): string {
  switch (kind) {
    case "wubi":
      return "1–4 个字母";
    case "quick_phrase":
      return "1–32 个字母或数字";
    case "english":
      return "1–64 个字母";
    case "pinyin":
      return "完整音节，用 ' 分隔，如 ni'hao";
  }
}

/** The single-file name and layout used by the macOS personal dictionary. */
export function personalDictionaryExportName(): string {
  return "水杉用户词库.txt";
}

export function personalDictionaryExportPayload(entries: DictionaryEntry[]): {
  body: string;
  rows: number;
} {
  const rows = personalDictionaryExportKinds.flatMap(([kind, label]) =>
    entries
      .filter((entry) => entry.kind === kind)
      .map((entry) => `${label}\t${entry.key}\t${entry.value}\t${entry.weight}`),
  );
  return {
    body: `# 类别\t编码\t词条\t权重\n${rows.length ? `${rows.join("\n")}\n` : ""}`,
    rows: rows.length,
  };
}

/** Read every dictionary kind in bounded pages, preserving host ordering. */
export async function loadAllPersonalDictionaryEntries(
  dictionary: Pick<DictionaryClient, "list">,
): Promise<DictionaryEntry[]> {
  const entries: DictionaryEntry[] = [];
  for (const [kind] of personalDictionaryExportKinds) {
    let offset = 0;
    let hasMore = true;
    while (hasMore && offset <= 1_000_000) {
      const page = await dictionary.list(offset, DICTIONARY_PAGE_SIZE, kind, "");
      const pageEntries = page.entries.filter((entry) => entry.kind === kind);
      entries.push(...pageEntries);
      if (!page.entries.length) break;
      offset += page.entries.length;
      hasMore = page.has_more;
    }
    if (hasMore) throw new Error("dictionary_export_limit");
  }
  return entries;
}
export type LocalModePreferences = {
  unicode: boolean;
  date_time: boolean;
  quick_phrase: boolean;
  emoji: boolean;
  kaomoji: boolean;
  super_jianpin: boolean;
  temporary_english: boolean;
  temporary_japanese: boolean;
};
const defaultLocalModes: LocalModePreferences = {
  unicode: true,
  date_time: true,
  quick_phrase: true,
  emoji: true,
  kaomoji: true,
  super_jianpin: true,
  temporary_english: true,
  temporary_japanese: true,
};
const localModeRows = [
  ["quick_phrase", "快捷短语(K 模式)", "中文模式下按 Shift+K，再输入编码即可调用快捷短语"],
  [
    "date_time",
    "日期与时间快捷输入(T 模式)",
    "中文模式下按 Shift+T，再输入 rq / riqi / date 输入日期，sj / shijian / time 输入时间，xq / xingqi / week 输入星期",
  ],
  [
    "unicode",
    "Unicode 便捷录入(U 模式)",
    "中文模式下按 Shift+U，再输入十六进制码位（如 4e00 / +1f600）。空格上屏；Shift+数字选词",
  ],
  [
    "emoji",
    "Emoji 快捷输入(E 模式)",
    "中文模式下按 Shift+E，再输入全拼 / 简拼 / 双拼 / 英文关键词。空格上屏；数字选词",
  ],
  [
    "kaomoji",
    "颜文字快捷输入(M 模式)",
    "中文模式下按 Shift+M，再输入全拼 / 简拼 / 双拼 / 英文关键词。空格上屏；数字选词",
  ],
  [
    "super_jianpin",
    "超级简拼(J 模式)",
    "中文模式下按 Shift+J，每个字母作为简拼；双拼按当前方案转换声母。空格上屏；数字选词",
  ],
  [
    "temporary_english",
    "临时英文(Y 模式)",
    "中文模式下按 Shift+Y，之后按英文处理。空格上屏当前输入；数字选词；上屏后回到中文",
  ],
  [
    "temporary_japanese",
    "临时日语(R 模式)",
    "中文模式下按 Shift+R，之后按日语罗马字处理。空格上屏首选；数字选词；上屏后回到中文",
  ],
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
  const code =
    typeof error === "object" && error !== null && "code" in error
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
    case "dictionary_reset_rejected":
      return "清除学习数据失败，请关闭正在使用输入法的程序后重试。";
    case "dictionary_unavailable":
      return "无法打开用户词库，请检查输入法是否正在运行。";
    default:
      return fallback;
  }
}

function importFailureMessage(kind: string, error: unknown): string {
  const reason =
    error instanceof Error
      ? error.message
      : typeof error === "string"
        ? error
        : typeof error === "object" && error !== null && "error" in error
          ? String((error as { error: unknown }).error)
          : "";
  // A host code is more specific than a free-text reason, so try it first.
  const coded = dictionaryErrorMessage(error, "");
  if (coded) return `${kind}导入失败：${coded}`;
  return reason ? `${kind}导入失败：${reason}` : `${kind}导入失败，请检查文本格式。`;
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
  const lines = text.split("\n").filter((line) => line.trim().length > 0);
  // Windows exports put the code first; every other format puts the word first.
  const wordColumn = format === "windows" ? 1 : 0;
  const kept =
    kind === "pinyin"
      ? lines.filter((line) => {
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

export type MixedInputPreferences = {
  english: boolean;
  minimum_prefix: number;
  emoji: boolean;
  kaomoji: boolean;
};
const defaultMixedInput: MixedInputPreferences = {
  english: true,
  minimum_prefix: 5,
  emoji: false,
  kaomoji: false,
};
export type FrequencyPreferences = {
  mode: "disabled" | "pin" | "halve" | "linear" | "promote";
  trigger_count: number;
  linear_step: number;
};
const defaultFrequency: FrequencyPreferences = {
  mode: "promote",
  trigger_count: 1,
  linear_step: 1,
};
export type NavigationPreferences = {
  minus_equal: boolean;
  comma_period: boolean;
  brackets: boolean;
  tab: boolean;
  page_up_down: boolean;
  mouse_wheel?: boolean;
  arrows: boolean;
};
const defaultNavigation: NavigationPreferences = {
  minus_equal: true,
  comma_period: true,
  brackets: false,
  tab: true,
  page_up_down: true,
  arrows: true,
};
const translationLanguages: [NonNullable<Preferences["translation_target_language"]>, string][] = [
  ["en", "英语"],
  ["fr", "法语"],
  ["ja", "日语"],
  ["es", "西班牙语"],
  ["ru", "俄语"],
  ["de", "德语"],
  ["ko", "韩语"],
];
const translationSecondaryLanguages: [
  "" | NonNullable<Preferences["translation_target_language"]>,
  string,
][] = [["", "不显示第二种语言"], ...translationLanguages];
const mobileTranslationLanguages = translationLanguages.filter(([value]) => value !== "ru");
const defaultWordCharacter = { enabled: true, keys: "brackets" as const };
const navigationOptions: [keyof NavigationPreferences, string][] = [
  ["minus_equal", "- / ="],
  ["comma_period", ", / ."],
  ["brackets", "[ / ]"],
  ["tab", "Shift+Tab / Tab"],
  ["page_up_down", "PageUp / PageDown"],
  ["mouse_wheel", "鼠标滚轮（候选面板支持时翻页）"],
  ["arrows", "上 / 下（移动候选项）"],
];
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
  handwriting: boolean;
  screen_keyboard: boolean;
  voice: boolean;
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
  handwriting: true,
  screen_keyboard: false,
  voice: true,
  settings: true,
  scale_percent: 100,
  font_size: 24,
};
type FloatingToolbarOptionKey = keyof Pick<
  FloatingToolbarPreferences,
  | "english_mode"
  | "fullwidth"
  | "punctuation"
  | "character_set"
  | "emoji"
  | "handwriting"
  | "screen_keyboard"
  | "voice"
  | "settings"
>;
/// In the order the buttons sit on the toolbar. The third entry names the capability a host must
/// report for the switch to be offered at all: the handwriting and voice buttons are this client's
/// own additions and only one host draws them, so a switch for them elsewhere would turn off
/// something that is not there.
const floatingToolbarOptions: [
  FloatingToolbarOptionKey,
  string,
  keyof Pick<HostCapabilities, "floating_toolbar_handwriting" | "floating_toolbar_voice"> | null,
][] = [
  ["english_mode", "英文输入模式", null],
  ["fullwidth", "全角 / 半角", null],
  ["punctuation", "中英文标点", null],
  ["character_set", "简繁切换", null],
  ["emoji", "表情与符号", null],
  ["handwriting", "手写识别板", "floating_toolbar_handwriting"],
  ["screen_keyboard", "屏幕键盘", null],
  ["voice", "语音输入", "floating_toolbar_voice"],
  ["settings", "设置", null],
];
const floatingToolbarScales: FloatingToolbarPreferences["scale_percent"][] = [75, 100, 125, 150];
const floatingToolbarFontSizes: FloatingToolbarPreferences["font_size"][] = [
  16, 18, 20, 22, 24, 26, 28,
];
export type ClipboardHistoryEntry = { text: string; timestampMs: number; pinned: boolean };
export type MobileKeyboardFeedback = {
  soundEnabled: boolean;
  hapticsEnabled: boolean;
  hapticStrength: "light" | "medium" | "strong";
  /** iOS keeps this Apple keyboard preference in the native App Group store. */
  englishSuggestions?: boolean;
};
export type MobileKeyboardFeedbackClient = {
  load(): Promise<MobileKeyboardFeedback>;
  save(settings: MobileKeyboardFeedback): Promise<MobileKeyboardFeedback>;
  preview?(strength: MobileKeyboardFeedback["hapticStrength"]): Promise<void>;
};
export interface SettingsClient {
  /** What the surrounding host can do. Absent hosts fall back to user-agent detection. */
  host?: HostCapabilities;
  /** Android's platform-adapted Apple-style keyboard home surface. */
  home?: HomePageActions;
  /** Mobile account commands expose user/profile DTOs but never session tokens. */
  account?: AccountClient;
  /** Mobile hosts expose platform-native launcher or alternate icon selection. */
  appIcon?: AppIconClient;
  /** Mobile account commands expose the authenticated EveryAPI chat surface. */
  chat?: ChatClient;
  /** Android performs user-configured AI service requests in its native host. */
  aiAssistant?: AiAssistantClient;
  /** Native hosts test credentials without exposing private provider secrets to the webview. */
  testApiCredential?: (
    service: ApiCredentialTestService,
    config: Record<string, unknown>,
  ) => Promise<ApiCredentialTestResult>;
  /** Android community commands expose bounded public skin metadata and designs. */
  communitySkins?: CommunitySkinClient;
  /** Android community commands expose dictionaries and reply templates. */
  communityResources?: CommunityResourceClient;
  listVoiceCaptureDevices?: VoiceDeviceReader;
  /**
   * The user's own candidate glosses. Windows delivers these as a file dropped in the profile
   * directory; a host whose user data lives in an app sandbox has to offer a way in instead.
   */
  customTranslations?: { load(): Promise<string>; save(text: string): Promise<void> };
  listFontFamilies?: FontCatalogReader;
  resolveFontFamilies?: (names: string[]) => Promise<string[]>;
  scanSkinCatalog?: () => Promise<SkinCatalog>;
  readSkinImage?: SkinImageReader;
  readSkinFont?: SkinFontReader;
  readSkinToolbarCss?: (id: string, relative?: string) => Promise<string | null>;
  openSkinDirectory?: () => Promise<void>;
  load(): Promise<Snapshot>;
  save(revision: number, preferences: Preferences): Promise<Snapshot>;
  onPreferencesChanged?(listener: (snapshot: Snapshot) => void): Promise<() => void>;
  dictionary?: DictionaryClient;
  /** macOS can atomically restore packaged dictionaries and clear all learning state. */
  resetLearnedData?: () => Promise<void>;
  /**
   * What a restore-to-defaults would write, without writing it. The host decides what survives --
   * the credentials, and the endpoint and model that address the same service -- because that rule
   * belongs with the document, not with this page.
   */
  loadDefaultPreferences?: () => Promise<Preferences>;
  readAppVersion?: () => Promise<string>;
  openExternalUrl?: (url: string) => Promise<void>;
  /** macOS opens the versioned third-party notices shipped with the app bundle. */
  openThirdPartyLicenses?: () => Promise<void>;
  /** macOS keeps the native shuangpin keymap panel preference outside shared Engine preferences. */
  loadMacosShuangpinKeymap?: () => Promise<boolean>;
  saveMacosShuangpinKeymap?: (enabled: boolean) => Promise<void>;
  /** macOS keeps Wubi unique-candidate auto-commit in the native input-method defaults domain. */
  loadMacosWubiAutoCommitUnique?: () => Promise<boolean>;
  saveMacosWubiAutoCommitUnique?: (enabled: boolean) => Promise<void>;
  copyText?: (text: string) => Promise<void>;
  /** Mobile hosts can open the platform keyboard/input-method settings. */
  openSystemKeyboardSettings?: () => Promise<void>;
  /** Mobile hosts persist keyboard sound and haptic feedback in native preferences. */
  mobileKeyboardFeedback?: MobileKeyboardFeedbackClient;
  openScreenKeyboard?: () => Promise<void>;
  openHandwriting?: () => Promise<void>;
  openVoice?: () => Promise<void>;
  openCloudClipboard?: () => Promise<void>;
  openCloudDictionary?: () => Promise<void>;
  restartInputMethod?: () => Promise<void>;
  /** macOS installs/updates the separate InputMethodKit bundle before registering it. */
  installInputSource?: () => Promise<void>;
  /** macOS moves the installed input source to Trash; data removal is explicit. */
  uninstallInputSource?: (removeUserData: boolean) => Promise<void>;
  /** macOS keeps small fixed locators while the state root itself may move to another volume. */
  dataDirectory?: {
    status(): Promise<{ path: string; isDefault: boolean }>;
    pick(): Promise<string | null>;
    move(): Promise<{ path: string; isDefault: boolean; retainedOldData: boolean }>;
  };
  /**
   * Ask the host for a file path, resolving to null when the user cancels. A local speech model is loaded
   * by path and a file input hands back contents instead, so only the host can answer this.
   */
  pickVoiceModelPath?: () => Promise<string | null>;
  windowControl?: (action: "minimize" | "maximize" | "restore" | "close") => Promise<void>;
  beginWindowDrag?: () => Promise<void>;
  resizeWindow?: (edge: "n" | "s" | "e" | "w" | "ne" | "nw" | "se" | "sw") => Promise<void>;
  onWindowStateChanged?: (
    listener: (maximized: boolean) => void,
    onError?: () => void,
  ) => Promise<() => void>;
  clipboard?: {
    clear(): Promise<void>;
    list?(): Promise<ClipboardHistoryEntry[]>;
    sync?(): Promise<ClipboardHistoryEntry[]>;
    copy?(text: string): Promise<void>;
    remove?(text: string): Promise<void>;
    setPinned?(text: string, pinned: boolean): Promise<void>;
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
  /** Mobile and desktop hosts can show packaged offline English glosses without changing candidate identity. */
  candidateEnglishGloss?: boolean;
  /**
   * Which packaged dictionary is installed, for the dictionary page to state.
   *
   * A host that stages its resources into a sandbox is the only thing that knows where the
   * manifest ended up, and the path is not something this page should be told. Absent means the
   * host cannot answer, and the section is not drawn: a dictionary version stated wrongly is worse
   * than one not stated at all.
   */
  dictionaryManifest?: () => Promise<DictionaryManifest>;
}

function message(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === "object" && error !== null && "code" in error) {
    switch (error.code) {
      case "conflict":
        return "设置已在其他窗口修改。请重新读取后再保存。";
      case "invalid":
        return "候选数量必须为 1 到 9。";
      case "frequency_invalid":
        return "调频触发频次和步长必须为 1 到 10。";
      case "mixed_input_invalid":
        return "中英混输触发字符数必须为 1 到 8。";
      case "key_conflict":
        return "以词定字和翻页不能使用同一组快捷键。";
      case "format":
        return "配置文件无法读取或版本较新，原文件已保留。";
    }
  }
  return "无法访问设置，请重试。原有设置不会被自动重置。";
}

type SettingsPageId = (typeof pages)[number]["id"];
// A host can ask for the section its menu entry names. An unknown id keeps the
// default page rather than opening an empty one.
function requestedPage(value: string | undefined): SettingsPageId {
  return pages.some((page) => page.id === value) ? (value as SettingsPageId) : "appearance";
}

/** What the platform calls itself, for text a person reads rather than a switch the code takes. */
function platformOsName(platform: HostPlatform): string {
  return platform === "macos"
    ? "macOS"
    : platform === "windows"
      ? "Windows"
      : platform === "harmony"
        ? "HarmonyOS"
        : platform === "ios"
          ? "iOS"
          : platform === "android"
            ? "Android"
            : "Linux";
}

function schemeTitle(scheme: Preferences["scheme"]): string {
  return scheme === "quanpin"
    ? "全拼"
    : scheme === "shuangpin"
      ? "双拼"
      : scheme === "wubi"
        ? "五笔"
        : "日语";
}

function personalDictionaryKindTitle(kind: PersonalDictionaryImportEntry["kind"]): string {
  return kind === "pinyin"
    ? "拼音"
    : kind === "wubi"
      ? "五笔"
      : kind === "quickPhrase"
        ? "快捷短语"
        : "英文";
}

/**
 * Which dictionary is installed, as the dictionary page's first statement.
 *
 * The packaged dictionary is the one thing on this page the user cannot change and may well want
 * to check: it is what every candidate comes out of, it updates with the application rather than
 * on its own, and when something looks wrong the specification and the upstream commit are the
 * two facts worth having.
 *
 * A host that cannot answer does not render this at all, rather than rendering an empty row. The
 * manifest is packaged, so failing to read it means the installation is not what it should be —
 * which is worth saying plainly instead of leaving a blank where a version belongs.
 */
function DictionaryManifestCard({ read }: { read: () => Promise<DictionaryManifest> }) {
  const [manifest, setManifest] = useState<DictionaryManifest | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let active = true;
    void read()
      .then((value) => {
        if (active) setManifest(value);
      })
      .catch(() => {
        if (active) setFailed(true);
      });
    return () => {
      active = false;
    };
  }, [read]);

  if (failed) {
    return (
      <div className="section" role="region" aria-label="词库信息">
        <div className="section-header">
          <span className="section-title">
            词库信息
            <small>无法读取随应用安装的词库清单，请重新安装后再试。</small>
          </span>
        </div>
      </div>
    );
  }
  if (!manifest) return null;
  return (
    <div className="section" role="region" aria-label="词库信息">
      <div className="section-header">
        <span className="section-title">
          词库信息
          <small>词库保存在设备上，日常输入不需要联网；它随应用更新，不单独下载。</small>
        </span>
      </div>
      <p>
        规格 <code>{manifest.profile}</code>
      </p>
      <p>
        {/* Twelve characters is what the source shows: enough to identify the build, short enough
            to read back over the phone. */}
        词库版本 <code>{manifest.sourceCommit.slice(0, 12)}</code>
      </p>
    </div>
  );
}

// The card is shown on every mobile host, so it must not name one of them. The queue it
// feeds is the platform's own keyboard: on iOS the App Group queue the extension drains,
// on Android the sync queue the input-method service drains.
function PersonalDictionaryImportCard({
  dictionary,
  platform,
}: {
  dictionary: DictionaryClient;
  platform?: string;
}) {
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
      setNotice(
        `已加入本机同步队列，共 ${entries.length} 条；当前等待同步 ${result.pending_count} 条。`,
      );
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

  const countByKind = entries
    ? Array.from(new Set(entries.map((entry) => entry.kind)))
        .map(
          (kind) =>
            `${personalDictionaryKindTitle(kind)} ${entries.filter((entry) => entry.kind === kind).length} 条`,
        )
        .join(" · ")
    : "";

  return (
    <div
      className={`section ${settings.importSection}`}
      role="region"
      aria-label="个人词库文件导入"
    >
      <div className="section-header">
        <span className="section-title">
          个人词库文件
          <small>
            导入 Apple 兼容的 JSON 词条，确认后加入
            {platform === "ios" ? " iOS " : platform === "android" ? " Android " : ""}
            键盘同步队列；文件内容不会上传。
          </small>
        </span>
        <span>
          <button
            type="button"
            className="secondary"
            disabled={busy}
            onClick={() => input.current?.click()}
          >
            选择 JSON 文件
          </button>{" "}
          <button type="button" className="secondary" disabled={busy} onClick={saveExample}>
            保存示例文件
          </button>
          <input
            ref={input}
            hidden
            type="file"
            aria-label="选择个人词库 JSON 文件"
            accept=".json,application/json"
            onChange={(event) => {
              void chooseFile(event.currentTarget.files?.[0]);
              event.currentTarget.value = "";
            }}
          />
        </span>
      </div>
      {busy && <p role="status">正在读取或加入同步队列…</p>}
      {fileName && entries && (
        <div className={settings.importPreview}>
          <strong>{fileName}</strong>
          <span>
            已校验 {entries.length} 条（{countByKind}），确认后逐条同步。
          </span>
          {entries.map((entry, index) => (
            <div key={`${entry.kind}-${entry.key}-${index}`}>
              <span>{entry.value}</span>
              <code>
                {personalDictionaryKindTitle(entry.kind)} · {entry.key}
              </code>
            </div>
          ))}
        </div>
      )}
      {error && (
        <p role="alert" className="error">
          {error}
        </p>
      )}
      {notice && (
        <p role="status" className="notice">
          {notice}
        </p>
      )}
      {entries && (
        <button
          type="button"
          className="primary"
          disabled={busy}
          onClick={() => void importEntries()}
        >
          确认导入
        </button>
      )}
    </div>
  );
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
export function tencentCredentialIssue(
  secretId: string,
  secretKey: string,
  region: string,
): string {
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

export function SettingsPage({
  client,
  initialPage,
  onReplayOnboarding,
}: {
  client: SettingsClient;
  initialPage?: string;
  onReplayOnboarding?: () => void;
}) {
  const { confirm, confirmation } = useConfirm();
  // Hosts that report capabilities are authoritative; the user-agent probe stays
  // only so a host that predates the contract keeps its current behaviour.
  const linuxPlatform = client.host ? client.host.platform === "linux" : isLinuxDesktop();
  const androidPlatform = client.host?.platform === "android";
  const iosPlatform = client.host?.platform === "ios";
  // This repository ships the HarmonyOS host too, so its release, license and issue links follow the client-hosted set rather than the Windows ones.
  const harmonyPlatform = client.host?.platform === "harmony";
  // Ctrl+Space belongs to Windows, not to us, so only that host gets the note
  // explaining where to change it.
  const windowsPlatform = client.host?.platform === "windows";
  const macosPlatform = client.host?.platform === "macos";
  const nativeVoicePlatform = macosPlatform || harmonyPlatform;
  // One list for every host. macOS used to be given 5, 7 and 9 - the Apple reference's set - while its
  // own normalisation rewrote anything else to 9, so the shared default of six displayed and saved as
  // nine on that platform alone.
  const candidatePageSizes = Array.from({ length: 9 }, (_, index) => index + 1);
  // Functional controls follow what the host declares it can do. Only the prose
  // below still varies by platform name. A host that predates the contract keeps
  // the previous Linux-only behaviour.
  const host = client.host;
  const showModeScope = host ? host.ime_mode_scope : linuxPlatform;
  const showModeSwitchShortcuts = host ? host.mode_switch_shortcuts : linuxPlatform;
  // Named for the keys the user is actually looking at: macOS calls them Control and Option.
  const modeSwitchShortcutRows: [keyof KeybindingPreferences, string][] = [
    ["switch_language_shift", "Shift 切换中英文"],
    ["switch_language_ctrl", macosPlatform ? "单击 Control 切换中英文" : "单击 Ctrl 切换中英文"],
    [
      "switch_language_ctrl_alt_space",
      macosPlatform ? "Control+Option+Space 切换中英文" : "Ctrl+Alt+Space 切换中英文",
    ],
    [
      "toggle_character_set_ctrl_shift_f",
      macosPlatform ? "Control+Shift+F 切换简繁" : "Ctrl+Shift+F 切换简繁",
    ],
  ];
  const showPanelShortcuts = host ? host.panel_shortcuts : linuxPlatform;
  const showNumberRowSelection = host ? host.number_row_selection === true : linuxPlatform;
  const showRestartInputMethod =
    (host ? host.restart_input_method : linuxPlatform) && client.restartInputMethod;
  const showInstallInputSource = macosPlatform && client.installInputSource;
  const showFloatingToolbar = host ? host.floating_toolbar : true;
  // An IBus property menu has no scale or icon size to apply, but it can
  // expose component visibility as individual menu entries.
  const showToolbarAppearance = host ? host.floating_toolbar_appearance : true;
  const showToolbarComponents = host ? host.floating_toolbar_components : true;
  const showCandidateFontControls = host ? host.candidate_font_controls : true;
  // Was a list of platform names, which is how HarmonyOS came to consume the preference without
  // anyone being able to set it. A host that predates the capability keeps the old reading.
  const showCandidateEnglishFont =
    host?.candidate_english_font ?? (windowsPlatform || macosPlatform || androidPlatform);
  // iOS shows its own switch for the same surface, from the native store, so it is not here.
  const showEnglishSuggestions = host?.english_suggestions ?? androidPlatform;
  // Which hosts mark a helper code with Shift rather than appending it to a finished spelling.
  // Was a platform name, which is how HarmonyOS came to run the same ported policy and show the
  // page without the one sentence that says how to type one.
  const showHelpcodeShiftEntry = host?.helpcode_shift_entry ?? androidPlatform;
  // Every host's Engine honours the preference; this is about which of them draw the composition
  // themselves, and so show the user a difference between the raw keys and the expanded pinyin.
  const showShuangpinPreedit = host?.shuangpin_preedit ?? macosPlatform;
  // The host's provider holds the AI credential, so the page does not ask for a token and does not
  // withhold the service controls for want of one. Reaching the service still works - through that
  // provider - which is why these controls are offered rather than hidden.
  const aiProviderCredentials = host?.ai_provider_credentials ?? linuxPlatform;
  // A host with one way to commit a recognized result has nothing to choose between, and a select
  // with one outcome reads as a setting being ignored.
  const showVoiceCommitMode = host?.voice_commit_mode ?? !androidPlatform;
  const showCandidateRowColors = host ? host.candidate_row_colors : true;
  const showCandidateSelectionAppearance = host ? host.candidate_selection_appearance : true;
  const showCandidateFollowCursor = host ? host.candidate_follow_cursor : false;
  // Was written as "macOS only" when macOS was the only host that drew the badge. A host that
  // predates the capability keeps that reading rather than losing a control it does honour; one
  // that declares it decides for itself, which is how HarmonyOS's 2in1 badge reaches the page.
  const showInputModeHUD = host?.input_mode_hud ?? macosPlatform;
  const showVoiceCaptureDevices =
    !androidPlatform &&
    (host ? host.voice_capture_devices : linuxPlatform) &&
    client.listVoiceCaptureDevices;
  // panel_windows is the injected projection of host_surface::is_desktop, so this follows the capability instead of listing the mobile hosts by name and missing the next one.
  const showDesktopMaintenanceShortcuts = !host || host.panel_windows;
  const maintenanceChord = macosPlatform ? "Ctrl+Shift+Option" : "Ctrl+Shift+Alt";
  const clientHostedPlatform =
    linuxPlatform ||
    androidPlatform ||
    macosPlatform ||
    harmonyPlatform ||
    host?.platform === "ios";
  const platformReleasesPageUrl = clientHostedPlatform ? linuxReleasesPageUrl : releasesPageUrl;
  const platformLicenseUrl = clientHostedPlatform ? linuxLicenseUrl : licenseUrl;
  const platformIssuesUrl = linuxIssuesUrl;
  const captureBackendOptions: readonly (readonly [
    NonNullable<VoiceInputPreferences["capture_backend"]>,
    string,
  ])[] = [
    ["auto", "自动选择"],
    ...(linuxPlatform
      ? ([
          ["pulse", "PulseAudio"],
          ["pipewire", "PipeWire"],
          ["alsa", "ALSA"],
        ] as const)
      : []),
    ...(macosPlatform ? ([["macos", "CoreAudio"]] as const) : []),
    ...(windowsPlatform ? ([["windows", "Windows Audio"]] as const) : []),
    ...(harmonyPlatform ? ([["harmony", "HarmonyOS 音频"]] as const) : []),
  ];
  const platformHelpIntro = androidPlatform
    ? "水杉输入法是一款 Android 平台的中文输入法，通过系统输入法服务接入应用。"
    : linuxPlatform
      ? "水杉输入法是一款 Linux 桌面环境下的中文输入法，通过 IBus 接入 GTK、Qt 等应用。"
      : macosPlatform
        ? "水杉输入法是一款 macOS 平台的中文输入法，通过系统输入法组件接入应用。"
        : harmonyPlatform
          ? "水杉输入法是一款 HarmonyOS 平台的中文输入法，通过系统输入法服务接入应用。"
          : iosPlatform
            ? "水杉输入法是一款 iOS 平台的中文输入法，通过键盘扩展接入应用。"
            : "水杉输入法是一款 Windows 平台的中文输入法。目前支持 Windows 11/Windows 10 平台。";
  const platformQuickStart = androidPlatform
    ? "在系统设置的“语言和输入法”或“屏幕键盘”中启用并选择水杉输入法，也可以从首次启动页打开这些入口。默认是全拼输入法。"
    : linuxPlatform
      ? "安装并启动 IBus 宿主后，在系统设置的输入法列表中添加水杉输入法，再使用桌面环境提供的输入法切换快捷键切换。默认是全拼输入法。"
      : macosPlatform
        ? "在系统设置的键盘输入法中启用水杉输入法，再使用系统配置的输入法切换快捷键。默认是全拼输入法。"
        : harmonyPlatform
          ? "在系统设置中启用并选择水杉输入法，再从输入法键盘使用语音和触屏输入。默认是全拼输入法。"
          : iosPlatform
            ? "在系统设置中启用水杉键盘，再从应用的输入源按钮切换使用。默认是全拼输入法。"
            : "安装输入法后，可以使用 Win + Space 快捷键切换到水杉输入法。默认是全拼输入法。";
  const platformNetworkDescription = androidPlatform
    ? "语音输入会调用设备上的系统语音识别服务，识别结果回到键盘后需确认才会插入；AI 功能按需配置。日常拼音输入无需联网。"
    : linuxPlatform
      ? "语音识别和云候选由用户自行管理的 provider 提供，设置页只保存行为选项，不保存或转发 provider 的凭据。"
      : macosPlatform
        ? "语音识别、候选词翻译和 AI 功能仅在用户配置并启用对应服务时联网；日常拼音输入无需联网。"
        : harmonyPlatform
          ? "豆包语音识别仅在用户配置并启用时联网；也可使用 HarmonyOS 系统语音识别。原始音频只在本次识别期间处理。"
          : iosPlatform
            ? "键盘扩展的日常拼音输入无需联网；账号、云同步、AI 和语音功能仅在用户启用时联网。"
            : "语音识别和 AI 联想需要自行填入 API 和 token。云候选目前支持谷歌的云接口，请注意网络问题。";
  const platformAboutDescription = androidPlatform
    ? "为 Android 触屏输入体验打造的开放中文输入法。"
    : linuxPlatform
      ? "为 Linux 桌面输入体验打造的开放中文输入法。"
      : macosPlatform
        ? "为现代 macOS 桌面体验打造的开放中文输入法。"
        : harmonyPlatform
          ? "为 HarmonyOS 触屏输入体验打造的开放中文输入法。"
          : iosPlatform
            ? "为 iPhone 与 iPad 触屏输入体验打造的开放中文输入法。"
            : "为现代 Windows 桌面体验打造的开放中文输入法。";
  const mobilePlatform = iosPlatform || androidPlatform || harmonyPlatform;
  const [snapshot, setSnapshot] = useState<Snapshot>();
  const [draft, setDraft] = useState<Preferences>();
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [removeUserDataOnUninstall, setRemoveUserDataOnUninstall] = useState(false);
  const [uninstallConfirmation, setUninstallConfirmation] = useState(false);
  const [uninstallBusy, setUninstallBusy] = useState(false);
  const [uninstallResult, setUninstallResult] = useState<"success" | "error" | null>(null);
  const [dataDirectory, setDataDirectory] = useState<{ path: string; isDefault: boolean }>();
  const [dataDirectoryBusy, setDataDirectoryBusy] = useState(false);
  const [dataDirectoryResult, setDataDirectoryResult] = useState("");
  const [page, setPage] = useState<SettingsPageId>(() =>
    requestedPage(initialPage ?? (client.home ? "home" : undefined)),
  );
  const settingsContentRef = useRef<HTMLElement>(null);
  // Every settings category shares this one scrolling surface. Reset it after
  // the new category is committed so sidebar clicks, in-page links and mobile
  // back navigation all open the destination at its beginning.
  useLayoutEffect(() => {
    if (settingsContentRef.current) settingsContentRef.current.scrollTop = 0;
  }, [page]);
  // Mobile hosts use the WebView history stack for the system back gesture. The
  // native activity can therefore dismiss a nested page without the shared UI
  // having to know which Android/iOS navigation API is in use.
  useEffect(() => {
    if (!mobilePlatform || typeof window === "undefined") return;
    const current = window.history.state;
    if (!current || current.msimeSettings !== true) {
      window.history.replaceState(
        { ...(current && typeof current === "object" ? current : {}), msimeSettings: true, page },
        "",
      );
    }
    const onPopState = (event: PopStateEvent) => {
      const state = event.state;
      if (state?.msimeSettings === true && typeof state.page === "string") {
        setPage(requestedPage(state.page));
      }
    };
    window.addEventListener("popstate", onPopState);
    return () => window.removeEventListener("popstate", onPopState);
  }, [mobilePlatform]);
  const [communityDestination, setCommunityDestination] = useState<
    AccountCommunityDestination | "all"
  >("all");
  const [updateStatus, setUpdateStatus] = useState("");
  const [updateBusy, setUpdateBusy] = useState(false);
  const [availableUpdate, setAvailableUpdate] = useState<ValidatedUpdate | null>(null);
  const [currentAppVersion, setCurrentAppVersion] = useState(fallbackAppVersion);
  const [feedbackCopied, setFeedbackCopied] = useState(false);
  const [feedbackKind, setFeedbackKind] = useState("功能异常");
  const [feedbackDetail, setFeedbackDetail] = useState("");
  const [feedbackReportCopied, setFeedbackReportCopied] = useState(false);
  const [mobileKeyboardFeedback, setMobileKeyboardFeedback] = useState<MobileKeyboardFeedback>();
  const [mobileKeyboardFeedbackBusy, setMobileKeyboardFeedbackBusy] = useState(false);
  const [customTranslationsText, setCustomTranslationsText] = useState("");
  const [customTranslationsNotice, setCustomTranslationsNotice] = useState("");
  const [customTranslationsBusy, setCustomTranslationsBusy] = useState(false);
  const customTranslationsReport = useMemo(
    () => parseCustomTranslations(customTranslationsText),
    [customTranslationsText],
  );
  const customTranslationsSummary = customTranslationsText.trim()
    ? `${customTranslationsReport.entries.length} 条释义` +
      (customTranslationsReport.skipped ? `，${customTranslationsReport.skipped} 行无法识别` : "")
    : "还没有自定义释义。";
  const [macosShuangpinKeymap, setMacosShuangpinKeymap] = useState<boolean>();
  const [macosWubiAutoCommitUnique, setMacosWubiAutoCommitUnique] = useState<boolean>();
  const [savedMacosWubiAutoCommitUnique, setSavedMacosWubiAutoCommitUnique] = useState<boolean>();
  const [phrases, setPhrases] = useState<DictionaryEntry[]>([]);
  const [phrasePage, setPhrasePage] = useState({ offset: 0, hasMore: false, status: "" });
  const [phraseBusy, setPhraseBusy] = useState(false);
  const [phraseError, setPhraseError] = useState("");
  const [dictionaryPendingCount, setDictionaryPendingCount] = useState(0);
  const [dictionaryFailures, setDictionaryFailures] = useState<DictionaryFailure[]>([]);
  const [dictionarySnapshotError, setDictionarySnapshotError] = useState("");
  const [phraseNotice, setPhraseNotice] = useState("");
  const [phraseSearch, setPhraseSearch] = useState("");
  const [phraseForm, setPhraseForm] = useState<{
    key: string;
    value: string;
    weight: number;
    previous: DictionaryEntry | null;
  } | null>(null);
  const [dictionaryKind, setDictionaryKind] = useState<LocalDictionaryKind>("quick_phrase");
  const [dictionaryFormat, setDictionaryFormat] = useState<LocalDictionaryFormat>("standard");
  const phraseRequestGeneration = useRef(0);
  const phraseListRef = useRef<HTMLUListElement>(null);
  const [windowMaximized, setWindowMaximized] = useState(false);
  const [skinPreviewThemes, setSkinPreviewThemes] = useState<
    Partial<Record<NonNullable<Preferences["candidate_skin"]>, "light" | "dark">>
  >({});
  const [showTouchSkinEditor, setShowTouchSkinEditor] = useState(false);
  const touchGeometryDrag = useRef<{
    pointerId: number;
    x: number;
    y: number;
    key: number;
    row: number;
    axis: "key" | "row" | null;
  } | null>(null);
  const [aiModels, setAiModels] = useState<string[] | null>(null);
  const [aiModelsStatus, setAiModelsStatus] = useState("");
  const [aiModelsBusy, setAiModelsBusy] = useState(false);
  const [aiTestInput, setAiTestInput] = useState("");
  const [aiTestOutput, setAiTestOutput] = useState("");
  const [aiTestStatus, setAiTestStatus] = useState("");
  const [aiTestBusy, setAiTestBusy] = useState(false);
  const aiRequestGeneration = useRef(0);
  const [credentialTests, setCredentialTests] = useState<
    Partial<
      Record<
        ApiCredentialTestService,
        {
          signature: string;
          busy: boolean;
          ok?: boolean;
          message: string;
        }
      >
    >
  >({});
  const credentialTestGeneration = useRef<Partial<Record<ApiCredentialTestService, number>>>({});
  // What a report needs first is the release and the scheme, because that is what a repro is
  // written against. The user agent only says which web view drew this window, so it is the
  // fallback for a host that cannot name its own OS rather than a line of its own.
  const supportDiagnostics = [
    `水杉 IME ${currentAppVersion}`,
    host?.os_version
      ? `${platformOsName(host.platform)} ${host.os_version}`
      : `平台：${host?.platform ?? (androidPlatform ? "android" : iosPlatform ? "ios" : "desktop")}`,
    draft ? `输入方案：${schemeTitle(draft.scheme)}` : "",
    host?.os_version || typeof navigator === "undefined"
      ? ""
      : `User-Agent：${navigator.userAgent.slice(0, 256)}`,
  ]
    .filter(Boolean)
    .join("\n");
  const feedbackReport = `### 类型\n${feedbackKind}\n\n### 描述\n${feedbackDetail}\n\n### 环境\n${supportDiagnostics}\n`;
  const submitFeedback = () => {
    if (!client.openExternalUrl) return;
    const body = feedbackReport.slice(0, 4000);
    const query = new URLSearchParams({ title: feedbackKind, body });
    void client.openExternalUrl(`${platformIssuesUrl}/new?${query.toString()}`);
  };
  const pendingTitlebarDrag = useRef<{ x: number; y: number; pointerId: number } | null>(null);
  useEffect(() => {
    const clear = () => {
      pendingTitlebarDrag.current = null;
    };
    window.addEventListener("blur", clear);
    return () => {
      clear();
      window.removeEventListener("blur", clear);
    };
  }, [client]);

  useEffect(() => {
    if (!macosPlatform || !client.dataDirectory) return;
    let active = true;
    client.dataDirectory
      .status()
      .then((value) => {
        if (active) setDataDirectory(value);
      })
      .catch(() => {
        if (active) setDataDirectoryResult("无法读取当前数据目录。");
      });
    return () => {
      active = false;
    };
  }, [client, macosPlatform]);
  useEffect(() => {
    let active = true;
    let unsubscribe: (() => void) | undefined;
    setWindowMaximized(false);
    const subscribe = client.onWindowStateChanged;
    if (subscribe) {
      void Promise.resolve()
        .then(() => {
          if (!active) return;
          return subscribe(
            (maximized) => {
              if (active) setWindowMaximized(maximized);
            },
            () => {
              if (active) setError("无法读取窗口状态，请重试。");
            },
          );
        })
        .then((value) => {
          if (active) unsubscribe = value;
          else value?.();
        })
        .catch(() => {
          if (active) setError("无法读取窗口状态，请重试。");
        });
    }
    return () => {
      active = false;
      unsubscribe?.();
    };
  }, [client]);
  useEffect(() => {
    let active = true;
    setCurrentAppVersion(fallbackAppVersion);
    if (client.readAppVersion) {
      void client
        .readAppVersion()
        .then((value) => {
          const version = parseVersion(value);
          if (active && version) setCurrentAppVersion(version.display);
        })
        .catch(() => undefined);
    }
    return () => {
      active = false;
    };
  }, [client]);

  useEffect(() => {
    const custom = client.customTranslations;
    if (!custom) return;
    let active = true;
    void custom
      .load()
      .then((text) => {
        if (active) setCustomTranslationsText(text);
      })
      .catch(() => {
        // An unreadable overlay is not an error worth a dialog: the field stays empty and saving
        // it would simply write a new one.
      });
    return () => {
      active = false;
    };
  }, [client.customTranslations]);

  async function saveCustomTranslations() {
    const custom = client.customTranslations;
    if (!custom || customTranslationsBusy) return;
    if (!customTranslationsWithinBounds(customTranslationsText)) {
      setCustomTranslationsNotice("自定义释义过大，请精简后再保存。");
      return;
    }
    setCustomTranslationsBusy(true);
    try {
      await custom.save(customTranslationsText);
      setCustomTranslationsNotice(
        `已保存 ${customTranslationsReport.entries.length} 条释义，重新启动输入法后生效。`,
      );
    } catch (error) {
      setCustomTranslationsNotice(message(error));
    } finally {
      setCustomTranslationsBusy(false);
    }
  }

  useEffect(() => {
    if (!mobilePlatform || !client.mobileKeyboardFeedback) {
      setMobileKeyboardFeedback(undefined);
      return;
    }
    let active = true;
    void client.mobileKeyboardFeedback
      .load()
      .then((value) => {
        if (active) setMobileKeyboardFeedback(value);
      })
      .catch(() => {
        if (active) setError("无法读取按键反馈设置，请重试。");
      });
    return () => {
      active = false;
    };
  }, [client, mobilePlatform]);

  useEffect(() => {
    if (!macosPlatform || !client.loadMacosShuangpinKeymap) {
      setMacosShuangpinKeymap(undefined);
      return;
    }
    let active = true;
    void client
      .loadMacosShuangpinKeymap()
      .then((value) => {
        if (active) setMacosShuangpinKeymap(value);
      })
      .catch(() => {
        if (active) setError("无法读取双拼键位提示设置，请重试。");
      });
    return () => {
      active = false;
    };
  }, [client, macosPlatform]);
  useEffect(() => {
    if (!macosPlatform || !client.loadMacosWubiAutoCommitUnique) {
      setMacosWubiAutoCommitUnique(undefined);
      setSavedMacosWubiAutoCommitUnique(undefined);
      return;
    }
    let active = true;
    void client
      .loadMacosWubiAutoCommitUnique()
      .then((value) => {
        if (!active) return;
        setMacosWubiAutoCommitUnique(value);
        setSavedMacosWubiAutoCommitUnique(value);
      })
      .catch(() => {
        if (active) setError("无法读取五笔自动上屏设置，请重试。");
      });
    return () => {
      active = false;
    };
  }, [client, macosPlatform]);
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
    void client
      .onPreferencesChanged((value) => {
        if (!active) return;
        const currentSnapshot = snapshotRef.current;
        const currentDraft = draftRef.current;
        const dirty =
          !!currentSnapshot &&
          !!currentDraft &&
          JSON.stringify(currentDraft) !== JSON.stringify(currentSnapshot.preferences);
        if (dirty) {
          setNotice("设置已被其他窗口修改。请重新读取后再保存。");
          return;
        }
        setSnapshot(value);
        setDraft(value.preferences);
        setError("");
        setNotice("设置已从其他窗口更新。");
      })
      .then((value) => {
        if (active) unsubscribe = value;
        else value();
      })
      .catch(() => undefined);
    return () => {
      active = false;
      unsubscribe?.();
    };
  }, [client]);

  useEffect(() => {
    let active = true;
    client
      .load()
      .then((value) => {
        if (active) {
          setSnapshot(value);
          setDraft(value.preferences);
        }
      })
      .catch((reason) => {
        if (active) setError(message(reason));
      })
      .finally(() => {
        if (active) setBusy(false);
      });
    return () => {
      active = false;
    };
  }, [client]);

  async function reload() {
    setBusy(true);
    setError("");
    setNotice("");
    try {
      const value = await client.load();
      setSnapshot(value);
      setDraft(value.preferences);
    } catch (reason) {
      setError(message(reason));
    } finally {
      setBusy(false);
    }
  }

  useEffect(() => {
    if (!mobilePlatform || typeof document === "undefined") return;
    let hidden = document.hidden;
    const onVisibilityChange = () => {
      const nextHidden = document.hidden;
      const resumed = hidden && !nextHidden;
      hidden = nextHidden;
      if (!resumed) return;
      const currentSnapshot = snapshotRef.current;
      const currentDraft = draftRef.current;
      const dirty =
        !!currentSnapshot &&
        !!currentDraft &&
        JSON.stringify(currentDraft) !== JSON.stringify(currentSnapshot.preferences);
      if (dirty) {
        setNotice("设置已被其他窗口修改。请重新读取后再保存。");
        return;
      }
      void reload();
    };
    document.addEventListener("visibilitychange", onVisibilityChange);
    return () => document.removeEventListener("visibilitychange", onVisibilityChange);
  }, [client, mobilePlatform]);

  async function save() {
    if (!draft || !snapshot || !validCandidateFonts(draft)) return;
    setBusy(true);
    setError("");
    setNotice("");
    try {
      const value = await client.save(snapshot.revision, draft);
      if (macosPlatform && client.saveMacosShuangpinKeymap && macosShuangpinKeymap !== undefined) {
        await client.saveMacosShuangpinKeymap(macosShuangpinKeymap);
      }
      if (
        macosPlatform &&
        client.saveMacosWubiAutoCommitUnique &&
        macosWubiAutoCommitUnique !== undefined
      ) {
        await client.saveMacosWubiAutoCommitUnique(macosWubiAutoCommitUnique);
        setSavedMacosWubiAutoCommitUnique(macosWubiAutoCommitUnique);
      }
      setSnapshot(value);
      setDraft(value.preferences);
      setNotice("设置已保存。");
    } catch (reason) {
      setError(message(reason));
    } finally {
      setBusy(false);
    }
  }

  async function saveMobileKeyboardFeedback(next: MobileKeyboardFeedback) {
    const feedback = client.mobileKeyboardFeedback;
    if (!feedback) return;
    const previous = mobileKeyboardFeedback;
    setMobileKeyboardFeedback(next);
    setMobileKeyboardFeedbackBusy(true);
    setError("");
    try {
      setMobileKeyboardFeedback(await feedback.save(next));
    } catch {
      if (previous) setMobileKeyboardFeedback(previous);
      setError("无法保存按键反馈设置，请重试。");
    } finally {
      setMobileKeyboardFeedbackBusy(false);
    }
  }

  async function uninstallInputSource() {
    if (!client.uninstallInputSource || uninstallBusy) return;
    setUninstallBusy(true);
    setUninstallResult(null);
    try {
      await client.uninstallInputSource(removeUserDataOnUninstall);
      setUninstallConfirmation(false);
      setUninstallResult("success");
    } catch {
      setUninstallResult("error");
    } finally {
      setUninstallBusy(false);
    }
  }

  async function chooseDataDirectory() {
    if (!client.dataDirectory || dataDirectoryBusy) return;
    setDataDirectoryBusy(true);
    setDataDirectoryResult("");
    try {
      const target = await client.dataDirectory.pick();
      if (!target) return;
      const confirmed = await confirm({
        title: "移动输入法数据？",
        message: `词库、学习记录、皮肤、剪贴板历史和设置将移动到“${target}”。移动期间输入法会短暂退出；完成后设置窗口会关闭。`,
        confirmLabel: "移动",
      });
      if (!confirmed) return;
      const result = await client.dataDirectory.move();
      setDataDirectory({ path: result.path, isDefault: result.isDefault });
      setDataDirectoryResult(
        result.retainedOldData
          ? "数据已切换到新目录；旧目录不属于水杉输入法，已为安全起见保留。设置窗口即将关闭。"
          : "数据已移动。设置窗口即将关闭，请重新打开后继续使用。",
      );
    } catch (reason) {
      const code =
        typeof reason === "object" && reason !== null && "code" in reason
          ? String(reason.code)
          : "";
      setDataDirectoryResult(
        code === "data_directory_not_empty"
          ? "请选择空文件夹；现有文件不会被覆盖。"
          : code === "data_directory_invalid"
            ? "该位置不能作为数据目录，请选择其他空文件夹。"
            : code === "data_directory_busy"
              ? "输入法仍在使用数据目录，请稍后重试。"
              : "移动失败，仍在使用原目录，原有数据未被删除。",
      );
    } finally {
      setDataDirectoryBusy(false);
    }
  }

  async function previewMobileKeyboardHaptics() {
    const feedback = client.mobileKeyboardFeedback;
    if (!feedback?.preview || !mobileKeyboardFeedback?.hapticsEnabled) return;
    setError("");
    try {
      await feedback.preview(mobileKeyboardFeedback.hapticStrength);
    } catch {
      setError("无法预览按键振动，请重试。");
    }
  }

  async function resetTouchKeyboardSettings() {
    if (!draft) return;
    const confirmed = await confirm({
      title: "恢复屏幕键盘默认值",
      message: "高度、间距和顶部语音入口都会回到默认。",
      confirmLabel: "恢复",
    });
    if (!confirmed || !draft) return;
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

  function beginTouchGeometryDrag(event: ReactPointerEvent<HTMLDivElement>) {
    if (!draft || (event.pointerType === "mouse" && event.button !== 0)) return;
    touchGeometryDrag.current = {
      pointerId: event.pointerId,
      x: event.clientX,
      y: event.clientY,
      key: draft.touch_key_spacing_tenths ?? 60,
      row: draft.touch_row_spacing_tenths ?? 70,
      axis: null,
    };
    event.currentTarget.setPointerCapture?.(event.pointerId);
  }

  function updateTouchGeometryDrag(event: ReactPointerEvent<HTMLDivElement>) {
    const drag = touchGeometryDrag.current;
    if (!drag || drag.pointerId !== event.pointerId || !draft) return;
    const dx = event.clientX - drag.x;
    const dy = event.clientY - drag.y;
    if (!drag.axis && Math.abs(dx) + Math.abs(dy) < 4) return;
    drag.axis ??= Math.abs(dy) >= Math.abs(dx) ? "row" : "key";
    const delta = drag.axis === "row" ? dy : dx;
    const value = Math.round((drag.axis === "row" ? drag.row : drag.key) + (delta * 10) / 18);
    setDraft((current) =>
      current
        ? {
            ...current,
            ...(drag.axis === "row"
              ? { touch_row_spacing_tenths: Math.min(100, Math.max(40, value)) }
              : { touch_key_spacing_tenths: Math.min(60, Math.max(30, value)) }),
          }
        : current,
    );
  }

  function endTouchGeometryDrag(event: ReactPointerEvent<HTMLDivElement>) {
    const drag = touchGeometryDrag.current;
    if (!drag || drag.pointerId !== event.pointerId) return;
    touchGeometryDrag.current = null;
    if (event.currentTarget.hasPointerCapture?.(event.pointerId))
      event.currentTarget.releasePointerCapture(event.pointerId);
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
    setUpdateBusy(true);
    setUpdateStatus("");
    setAvailableUpdate(null);
    try {
      const endpoint = clientHostedPlatform ? clientLatestReleaseUrl : updateManifestUrl;
      const response = await fetch(`${endpoint}?t=${Date.now()}`, { cache: "no-store" });
      if (clientHostedPlatform && response.status === 404) {
        setUpdateStatus("暂无可用发行版");
        return;
      }
      if (!response.ok) throw new Error(`update manifest returned ${response.status}`);
      const manifest = (await response.json()) as UpdateManifest | GitHubRelease;
      const update = clientHostedPlatform
        ? validateGitHubRelease(manifest as GitHubRelease, platformReleasesPageUrl)
        : validateManifest(manifest as UpdateManifest, platformReleasesPageUrl);
      const current = parseVersion(currentAppVersion);
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
    try {
      await action();
    } catch {
      setError("无法打开原生面板，请稍后重试。");
    }
  }

  const requestId = (prefix: string) =>
    `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  // One page per request: a real dictionary is far too large to pull into the
  // page before showing anything.
  async function loadPhrases(kind: LocalDictionaryKind = dictionaryKind, offset = 0) {
    if (!client.dictionary) return;
    const generation = ++phraseRequestGeneration.current;
    setPhraseBusy(true);
    setPhraseError("");
    setPhraseNotice("");
    setPhrasePage((current) => ({ ...current, status: "查询中…" }));
    try {
      // Ask the host for this kind and code prefix. Filtering a page the host
      // had already chosen meant a user with more than a page of pinyin words
      // saw an empty list when they picked another dictionary, and the status
      // line counted the filtered rows against the unfiltered page.
      const page = await client.dictionary.list(
        offset,
        DICTIONARY_PAGE_SIZE,
        kind,
        phraseSearch.trim(),
      );
      if (generation !== phraseRequestGeneration.current) return;
      // Older hosts ignore the extra arguments, so keep filtering defensively.
      const entries = page.entries.filter((entry) => entry.kind === kind);
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
      if (generation !== phraseRequestGeneration.current) return;
      setPhraseError("无法读取词库。");
      setPhrasePage((current) => ({ ...current, status: "查询失败，请重试" }));
    } finally {
      if (generation === phraseRequestGeneration.current) setPhraseBusy(false);
    }
  }
  function turnPhrasePage(offset: number) {
    // The list is its own scrolling surface. A page turn must reveal the new
    // page's first entry instead of preserving the previous page's bottom.
    if (phraseListRef.current) phraseListRef.current.scrollTop = 0;
    void loadPhrases(dictionaryKind, offset);
  }
  async function removePhrase(entry: DictionaryEntry) {
    if (!client.dictionary) return;
    // Deletion is not undoable and the row is one click away from 编辑.
    const confirmed = await confirm({
      title: "删除词条",
      message: `“${entry.value}”（${entry.key}）将被删除，此操作无法撤销。`,
      confirmLabel: "删除",
      danger: true,
    });
    if (!confirmed || !client.dictionary) return;
    setPhraseBusy(true);
    setPhraseError("");
    setPhraseNotice("");
    try {
      await client.dictionary.edit(entry, null, requestId("ui-remove"));
      // Stay on the page the user was reading; deleting the last row on a page
      // would otherwise leave them looking at an empty one.
      const remaining = phrases.length - 1;
      const offset =
        remaining === 0 && phrasePage.offset > 0
          ? Math.max(0, phrasePage.offset - DICTIONARY_PAGE_SIZE)
          : phrasePage.offset;
      await loadPhrases(dictionaryKind, offset);
    } catch (error) {
      setPhraseError(
        dictionaryErrorMessage(
          error,
          `${dictionaryKindLabel(dictionaryKind)}删除失败，请稍后重试。`,
        ),
      );
    } finally {
      setPhraseBusy(false);
    }
  }
  async function savePhrase() {
    if (!client.dictionary || !phraseForm) return;
    const replacement: DictionaryEntry = {
      kind: dictionaryKind,
      key: phraseForm.key.trim(),
      value: phraseForm.value,
      weight: phraseForm.weight,
    };
    if (!replacement.key || !replacement.value) {
      setPhraseError("编码和短语不能为空。");
      return;
    }
    setPhraseBusy(true);
    setPhraseError("");
    setPhraseNotice("");
    try {
      await client.dictionary.edit(
        phraseForm.previous,
        replacement,
        requestId(phraseForm.previous ? "ui-edit" : "ui-add"),
      );
      setPhraseForm(null);
      // An edit keeps the reader where they were; only a new entry returns to
      // the first page, where the shared runtime lists it.
      await loadPhrases(dictionaryKind, phraseForm.previous ? phrasePage.offset : 0);
    } catch (error) {
      setPhraseError(
        dictionaryErrorMessage(
          error,
          `${dictionaryKindLabel(dictionaryKind)}保存失败，请稍后重试。`,
        ),
      );
    } finally {
      setPhraseBusy(false);
    }
  }
  async function importPhrases(file: File) {
    if (!client.dictionary) return;
    setPhraseBusy(true);
    setPhraseError("");
    setPhraseNotice("");
    try {
      const text = await readDictionaryFile(file);
      let imported: DictionaryImportResult | null = null;
      if (client.dictionary.import) {
        imported = await client.dictionary.import(
          dictionaryKind,
          dictionaryFormat,
          text,
          requestId("ui-import"),
        );
      } else {
        if (dictionaryFormat === "hans") throw new Error("hans format requires batch import");
        const lines = text.split(/\r?\n/).filter(Boolean);
        for (const line of lines) {
          const [first, second, weight = "10000"] = line.split("\t");
          if (!first || !second) continue;
          const [value, key] = dictionaryFormat === "windows" ? [second, first] : [first, second];
          const parsedWeight = Number(weight);
          const normalizedWeight =
            weight.trim() !== "" && Number.isSafeInteger(parsedWeight) && parsedWeight >= 0
              ? parsedWeight
              : 10000;
          await client.dictionary.edit(
            null,
            { kind: dictionaryKind, key: key.trim(), value, weight: normalizedWeight },
            requestId("ui-import"),
          );
        }
      }
      await loadPhrases(dictionaryKind);
      // The host reports what it skipped; saying nothing reads as a clean import.
      if (imported)
        setPhraseNotice(describeImportResult(dictionaryKindLabel(dictionaryKind), imported));
    } catch (error) {
      setPhraseError(importFailureMessage(dictionaryKindLabel(dictionaryKind), error));
    } finally {
      setPhraseBusy(false);
    }
  }
  async function retryDictionaryFailure(requestId: string) {
    if (!client.dictionary?.retry) return;
    setPhraseBusy(true);
    setPhraseError("");
    try {
      await client.dictionary.retry(requestId);
      await loadPhrases(dictionaryKind, phrasePage.offset);
    } catch {
      setPhraseError("词条重试失败，请稍后重试。");
    } finally {
      setPhraseBusy(false);
    }
  }
  async function dismissDictionaryFailure(requestId: string) {
    if (!client.dictionary?.dismissFailure) return;
    setPhraseBusy(true);
    setPhraseError("");
    try {
      await client.dictionary.dismissFailure(requestId);
      await loadPhrases(dictionaryKind, phrasePage.offset);
    } catch {
      setPhraseError("移除失败记录失败，请稍后重试。");
    } finally {
      setPhraseBusy(false);
    }
  }
  async function exportPhrases() {
    if (!client.dictionary) return;
    if (dictionaryFormat === "hans") {
      setPhraseError("汉字自动注音格式仅支持导入。");
      return;
    }
    setPhraseBusy(true);
    setPhraseError("");
    setPhraseNotice("");
    try {
      let text = "";
      if (client.dictionary.export) {
        let offset = 0;
        let hasMore = true;
        while (hasMore && offset <= 1000000) {
          const page = await client.dictionary.export(
            dictionaryKind,
            dictionaryFormat === "rime" ? "standard" : dictionaryFormat,
            offset,
            1000,
          );
          text += page.text;
          const count = page.text ? page.text.trimEnd().split("\n").length : 0;
          offset += count;
          hasMore = page.has_more && count > 0;
        }
      } else {
        text = phrases
          .map((entry) =>
            dictionaryFormat === "windows"
              ? `${entry.key}\t${entry.value}\t${entry.weight}`
              : `${entry.value}\t${entry.key}\t${entry.weight}`,
          )
          .join("\n");
      }
      const payload = dictionaryExportPayload(dictionaryKind, dictionaryFormat, text);
      if (!payload.rows) {
        setPhraseError("当前没有可导出的用户新增词条。");
        return;
      }
      const url = URL.createObjectURL(
        new Blob([payload.body], { type: "text/plain;charset=utf-8" }),
      );
      const anchor = document.createElement("a");
      anchor.href = url;
      anchor.download = dictionaryExportName(dictionaryKind);
      anchor.click();
      URL.revokeObjectURL(url);
      setPhraseNotice(`已导出 ${payload.rows} 条用户词条。`);
    } catch (error) {
      setPhraseError(dictionaryErrorMessage(error, "词库导出失败，请稍后重试。"));
    } finally {
      setPhraseBusy(false);
    }
  }
  async function exportAllPhrases() {
    if (!client.dictionary) return;
    setPhraseBusy(true);
    setPhraseError("");
    setPhraseNotice("正在读取全部用户词库…");
    try {
      const payload = personalDictionaryExportPayload(
        await loadAllPersonalDictionaryEntries(client.dictionary),
      );
      if (!payload.rows) {
        setPhraseNotice("当前没有可导出的用户词条。");
        return;
      }
      const url = URL.createObjectURL(
        new Blob([payload.body], { type: "text/plain;charset=utf-8" }),
      );
      const anchor = document.createElement("a");
      anchor.href = url;
      anchor.download = personalDictionaryExportName();
      anchor.click();
      URL.revokeObjectURL(url);
      setPhraseNotice(`已导出全部 ${payload.rows} 条用户词条。`);
    } catch (error) {
      setPhraseError(dictionaryErrorMessage(error, "全部词库导出失败，请稍后重试。"));
    } finally {
      setPhraseBusy(false);
    }
  }

  /**
   * Put every setting back to its default, as a draft.
   *
   * The source window writes the defaults the moment the button is clicked. Here the result goes
   * into the draft instead and the user saves it like any other edit, because this page has an
   * explicit save and a dirty marker -- writing behind them would be the one action on the page
   * that does not work the way the rest of it does. It also means a misclick costs nothing.
   */
  async function restoreDefaults() {
    if (!client.loadDefaultPreferences || busy) return;
    const confirmed = await confirm({
      title: "恢复默认设置",
      message: "语音和翻译服务的密钥、词库和学习数据都不会改变。恢复后需要点击保存设置才会生效。",
      confirmLabel: "恢复",
    });
    if (!confirmed || !client.loadDefaultPreferences || busy) return;
    setError("");
    setNotice("");
    try {
      setDraft(await client.loadDefaultPreferences());
      setNotice("所有设置已恢复默认，请点击保存设置。");
    } catch {
      setError("无法读取默认设置，请重试。原有设置不会被自动重置。");
    }
  }

  async function resetLearnedData() {
    if (!client.resetLearnedData || phraseBusy) return;
    const confirmed = await confirm({
      title: "清除学习数据",
      message:
        "候选词频、用户词典和拼音学习记录将永久删除，此操作无法撤销。输入方案等设置不会改变。",
      confirmLabel: "清除",
      danger: true,
    });
    if (!confirmed || !client.resetLearnedData || phraseBusy) return;
    setPhraseBusy(true);
    setPhraseError("");
    setPhraseNotice("");
    try {
      await client.resetLearnedData();
      setPhrases([]);
      setPhrasePage({ offset: 0, hasMore: false, status: "已清除学习数据" });
      setDictionaryPendingCount(0);
      setDictionaryFailures([]);
      setDictionarySnapshotError("");
      setPhraseNotice("已清除所有学习数据；输入方案和设置保持不变。");
    } catch (error) {
      setPhraseError(
        dictionaryErrorMessage(error, "清除学习数据失败，请关闭正在使用输入法的程序后重试。"),
      );
    } finally {
      setPhraseBusy(false);
    }
  }

  const dirty =
    (!!draft && !!snapshot && JSON.stringify(draft) !== JSON.stringify(snapshot.preferences)) ||
    (macosWubiAutoCommitUnique !== undefined &&
      macosWubiAutoCommitUnique !== savedMacosWubiAutoCommitUnique);
  const ai = draft?.ai_assistant ?? defaultAiAssistant;
  const aiOrigin = aiCredentialOrigin(ai.endpoint);
  const aiToken = aiOrigin ? (ai.tokens?.[aiOrigin] ?? "") : "";
  const updateAi = (patch: Partial<AiAssistantPreferences>) => {
    aiRequestGeneration.current += 1;
    setAiModelsBusy(false);
    setAiTestBusy(false);
    setAiTestOutput("");
    setAiTestStatus("");
    if (patch.provider !== undefined || patch.endpoint !== undefined) {
      setAiModels(null);
      setAiModelsStatus("");
    }
    if (draft) setDraft({ ...draft, ai_assistant: { ...ai, ...patch } });
  };
  const updateAiToken = (value: string) => {
    aiRequestGeneration.current += 1;
    setAiModelsBusy(false);
    setAiTestBusy(false);
    setAiTestOutput("");
    setAiTestStatus("");
    if (aiOrigin) updateAi({ token: "", tokens: { ...ai.tokens, [aiOrigin]: value } });
  };
  const fetchAiModels = async () => {
    if (!client.aiAssistant) return;
    if (!aiOrigin) {
      setAiModelsStatus("请先填写完整的 HTTPS 接口地址。");
      return;
    }
    if (!aiProviderCredentials && !aiToken.trim()) {
      setAiModelsStatus("请先填写 API Token，或使用已保存的密钥。");
      return;
    }
    const generation = aiRequestGeneration.current;
    setAiModelsBusy(true);
    setAiModelsStatus("");
    try {
      const models = await client.aiAssistant.fetchModels({
        endpoint: ai.endpoint,
        token: aiToken,
        provider: ai.provider,
      });
      if (generation !== aiRequestGeneration.current) return;
      setAiModels(models);
      setAiModelsStatus(`已获取 ${models.length} 个可用模型。`);
      if (models.length && !models.includes(ai.model)) updateAi({ model: models[0] });
    } catch (cause) {
      setAiModelsStatus(
        cause instanceof Error ? cause.message : "获取模型失败，请检查地址、密钥和网络。",
      );
    } finally {
      if (generation === aiRequestGeneration.current) setAiModelsBusy(false);
    }
  };
  const testAi = async () => {
    if (!client.aiAssistant) return;
    const text = aiTestInput;
    if (!text.trim()) {
      setAiTestStatus("请先输入待润色文字。");
      return;
    }
    if (!aiOrigin || (!aiProviderCredentials && !aiToken.trim())) {
      setAiTestStatus(
        aiProviderCredentials
          ? "请先填写有效的 HTTPS 接口地址。"
          : "请先填写有效的 HTTPS 接口地址和 API Token。",
      );
      return;
    }
    const generation = ++aiRequestGeneration.current;
    setAiTestBusy(true);
    setAiTestStatus("");
    setAiTestOutput("");
    try {
      const result = await client.aiAssistant.test({
        endpoint: ai.endpoint,
        model: ai.model,
        provider: ai.provider,
        prompt:
          ai.prompt ??
          defaultAiAssistant.prompt ??
          "请润色以下文字，保持原意，只返回修改后的文字。",
        token: aiToken,
        text,
      });
      if (generation !== aiRequestGeneration.current) return;
      setAiTestOutput(result);
      setAiTestStatus("已完成");
    } catch (cause) {
      setAiTestStatus(
        cause instanceof Error ? cause.message : "AI 请求失败，请检查地址、模型、密钥和网络。",
      );
    } finally {
      if (generation === aiRequestGeneration.current) setAiTestBusy(false);
    }
  };
  const wordCharacter = draft?.word_character ?? defaultWordCharacter;
  const keybindings = draft?.keybindings ?? defaultKeybindings;
  const frequency = draft?.frequency ?? defaultFrequency;
  const mixedInput = draft?.mixed_input ?? defaultMixedInput;
  const fuzzyPinyin = draft?.fuzzy_pinyin ?? defaultFuzzyPinyin;
  const touchKeyboardSchemes = draft?.touch_keyboard_schemes ?? {
    enabled: allTouchKeyboardSchemes,
  };
  const selectedTouchKeyboardScheme = draft ? inferredTouchKeyboardScheme(draft) : "quanpin";
  const setTouchKeyboardSchemeEnabled = (scheme: TouchKeyboardScheme, enabled: boolean) => {
    if (!draft) return;
    const visible = new Set(touchKeyboardSchemes.enabled);
    if (enabled) visible.add(scheme);
    else visible.delete(scheme);
    if (visible.size === 0) return;
    const ordered = allTouchKeyboardSchemes.filter((value) => visible.has(value));
    const selected = visible.has(selectedTouchKeyboardScheme)
      ? selectedTouchKeyboardScheme
      : ordered[0];
    const next = selectTouchKeyboardScheme(draft, selected);
    setDraft({ ...next, touch_keyboard_schemes: { enabled: ordered, selected } });
  };
  const selectHomeScheme = (scheme: TouchKeyboardScheme) => {
    if (!draft) return;
    const visible = new Set(touchKeyboardSchemes.enabled);
    visible.add(scheme);
    const enabled = allTouchKeyboardSchemes.filter((value) => visible.has(value));
    const next = selectTouchKeyboardScheme(draft, scheme);
    setDraft({ ...next, touch_keyboard_schemes: { enabled, selected: scheme } });
  };
  const localModes = draft?.local_modes ?? defaultLocalModes;
  // Every platform sees every mode. macOS used to hide emoji, kaomoji and temporary Japanese on the
  // grounds that its bundle shipped only msime.db and english.db, but others.db and dict_japanese.dat have
  // been in resources/desktop-dictionary.lock.json since 780a9381b and tauri.macos.conf.json bundles the
  // whole verified set - so the switches were hidden for modes that worked. Temporary English, gated the
  // same way on english.db, was visible throughout, which is how inconsistent this had become.
  //
  // A host missing a catalog is still handled, and handled better than by hiding a switch: the runtime
  // turns that mode off when its resource is absent, so the trigger key inserts its capital instead of
  // being swallowed.
  const visibleLocalModeRows = localModeRows;
  const quanpinAutocorrect = {
    autocorrect_transposition: draft?.quanpin?.autocorrect_transposition ?? false,
    autocorrect_neighbor: draft?.quanpin?.autocorrect_neighbor ?? false,
  };
  const clipboardHistory = iosPlatform || (draft?.clipboard_history ?? false);
  function toggleClipboardHistory(enabled: boolean) {
    if (!draft) return;
    setDraft({ ...draft, clipboard_history: enabled });
    // Clearing on opt-out keeps the local history from lingering while the
    // draft is unsaved. Hosts may omit this capability, so the preference
    // still changes independently when no clear hook is available.
    if (!enabled && clipboardHistory && client.clipboard?.clear) {
      void client.clipboard.clear().catch(() => setError("无法清空剪贴板历史，请稍后重试。"));
      setClipboardEntries([]);
      setClipboardClearArmed(false);
    }
  }
  const diagnosticLog = {
    server: draft?.diagnostic_log?.server ?? false,
    tsf: draft?.diagnostic_log?.tsf ?? false,
  };
  const cloudCandidates = draft?.cloud_candidates ?? true;
  const candidateTranslations = draft?.candidate_translations ?? true;
  // Offline glosses are opt-in in client-core and in every native host. Keep
  // the settings view aligned when older snapshots omit the optional field.
  const candidateEnglishGloss = draft?.candidate_english_gloss ?? false;
  const englishSuggestions = draft?.english_suggestions ?? true;
  const candidateGlossLanguagesEnabled =
    candidateTranslations || Boolean(client.candidateEnglishGloss && candidateEnglishGloss);
  const translationTargetLanguage = draft?.translation_target_language ?? "en";
  const translationSecondaryLanguage = draft?.translation_secondary_language ?? "";
  const visibleTranslationLanguages = mobilePlatform
    ? [...mobileTranslationLanguages]
    : translationLanguages;
  const visibleSecondaryLanguages = mobilePlatform
    ? [
        ["", "不显示第二种语言"] as ["", string],
        ...mobileTranslationLanguages,
        ...(translationSecondaryLanguage === "ru"
          ? [["ru", "俄语（已保存）"] as ["ru", string]]
          : []),
      ]
    : translationSecondaryLanguages;
  if (
    mobilePlatform &&
    translationTargetLanguage === "ru" &&
    !visibleTranslationLanguages.some(([value]) => value === "ru")
  ) {
    visibleTranslationLanguages.push(["ru", "俄语（已保存）"]);
  }
  const voiceInput = { ...defaultVoiceInput, ...draft?.voice_input };
  const systemVoice = nativeVoicePlatform && voiceInput.asr_provider === "system";
  // On-device Whisper. Like the system recognizer it has no service behind it, so it hides the same endpoint, token and model rows - but unlike it, the user has to say which model file to load.
  const localVoice = macosPlatform && voiceInput.asr_provider === "local";
  const serviceVoice = !systemVoice && !localVoice;
  const harmonyUnsupportedAsr =
    harmonyPlatform && !["doubao", "system"].includes(String(voiceInput.asr_provider));
  const doubaoAuthMode =
    voiceInput.doubao_auth_mode ||
    (voiceInput.asr_app_key && !voiceInput.asr_app_key.startsWith("<") ? "legacy" : "api_key");
  const updateVoice = (patch: Partial<VoiceInputPreferences>) => {
    if (draft) setDraft({ ...draft, voice_input: { ...voiceInput, ...patch } });
  };
  const customTranslation = draft?.custom_translation ?? defaultCustomTranslation;
  const tencentTranslation = draft?.tencent_tmt ?? defaultTencentTranslation;
  const niutrans = draft?.niutrans ?? defaultNiuTrans;
  const translationProvider = niutrans.enabled
    ? "niutrans"
    : customTranslation.enabled
      ? "custom"
      : tencentTranslation.enabled
        ? "tencent"
        : "none";
  const setTranslationProvider = (provider: "none" | "custom" | "tencent" | "niutrans") => {
    if (!draft) return;
    setDraft({
      ...draft,
      custom_translation: { ...customTranslation, enabled: provider === "custom" },
      tencent_tmt: { ...tencentTranslation, enabled: provider === "tencent" },
      niutrans: { ...niutrans, enabled: provider === "niutrans" },
    });
  };
  const runCredentialTest = async (
    service: ApiCredentialTestService,
    config: Record<string, unknown>,
  ) => {
    if (!client.testApiCredential) return;
    const signature = JSON.stringify(config);
    const generation = (credentialTestGeneration.current[service] ?? 0) + 1;
    credentialTestGeneration.current[service] = generation;
    setCredentialTests((current) => ({
      ...current,
      [service]: { signature, busy: true, message: "" },
    }));
    try {
      const result = await client.testApiCredential(service, config);
      if (credentialTestGeneration.current[service] !== generation) return;
      setCredentialTests((current) => ({
        ...current,
        [service]: { signature, busy: false, ...result },
      }));
    } catch {
      if (credentialTestGeneration.current[service] !== generation) return;
      setCredentialTests((current) => ({
        ...current,
        [service]: {
          signature,
          busy: false,
          ok: false,
          message: "无法连接 provider，请确认服务已启动。",
        },
      }));
    }
  };
  const credentialTestControl = (
    service: ApiCredentialTestService,
    label: string,
    config: Record<string, unknown>,
    disabled = false,
  ) => {
    if (!client.testApiCredential) return null;
    const signature = JSON.stringify(config);
    const state = credentialTests[service];
    const visible = state?.signature === signature;
    return (
      <div className={settings.serviceRow}>
        <div>
          <button
            type="button"
            className="secondary"
            aria-label={label}
            disabled={disabled || (visible && state.busy)}
            onClick={() => void runCredentialTest(service, config)}
          >
            {visible && state.busy ? "测试中…" : "测试配置"}
          </button>
          {visible && state.message && (
            <span role={state.ok ? "status" : "alert"}>{state.message}</span>
          )}
        </div>
      </div>
    );
  };
  /**
   * The provider's known models and its own integration page.
   *
   * Apple's settings put both next to the provider row, and they are what makes
   * a freshly picked provider usable: the endpoint is filled in automatically,
   * but the model box is a free text field, and a user with no credential yet
   * has nowhere to learn which models that service accepts or where its API key
   * comes from. Selecting a preset only writes the model; 自定义模型 leaves
   * whatever the user typed alone.
   */
  const providerPresetControls = (
    label: string,
    preset: { models?: readonly string[]; documentation?: string } | undefined,
    model: string,
    onSelectModel: (model: string) => void,
    className = "section provider-preset-section",
  ) => {
    const models = preset?.models ?? [];
    const documentation = preset?.documentation;
    const linkable = documentation && client.openExternalUrl;
    if (models.length === 0 && !linkable) return null;
    return (
      <div className={className}>
        {models.length > 0 && (
          <label className="section-header">
            <span className="section-title">
              预置模型<small>服务商已知支持的模型；也可以在模型框中自行填写</small>
            </span>
            <select
              aria-label={`${label}预置模型`}
              value={models.includes(model) ? model : ""}
              onChange={(event) => {
                if (event.target.value) onSelectModel(event.target.value);
              }}
            >
              <option value="">自定义模型…</option>
              {models.map((entry) => (
                <option key={entry} value={entry}>
                  {entry}
                </option>
              ))}
            </select>
          </label>
        )}
        {linkable && (
          <button
            type="button"
            className="secondary"
            onClick={() => void openExternalUrl(documentation)}
          >
            {label}接入说明与 API Key
          </button>
        )}
      </div>
    );
  };
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
    return ((current as Record<string, unknown>)[field] as string) ?? "";
  };
  const smartPunctuation = draft?.smart_punctuation ?? false;
  const smartPunctuationRepeat = draft?.smart_punctuation_repeat ?? false;
  const smartPunctuationSpaceConvert = draft?.smart_punctuation_space_convert ?? false;
  const smartPunctuationDirectDigit = draft?.smart_punctuation_direct_digit ?? false;
  const smartPunctuationDirectLetter = draft?.smart_punctuation_direct_letter ?? false;
  const pairedPunctuation = draft?.paired_punctuation ?? true;
  const inputModeHUD = draft?.input_mode_hud ?? true;
  const punctuationLock = draft?.punctuation_lock ?? "follow";
  const floatingToolbar = { ...defaultFloatingToolbar, ...draft?.floating_toolbar };
  const themeMode = draft?.theme ?? "system";
  const settingsTheme = draft?.settings_theme ?? "follow";
  const candidatePreviewTheme = useCandidatePreviewTheme(themeMode, draft?.candidate_theme);
  const toolbarPreviewTheme = useCandidatePreviewTheme(themeMode, draft?.toolbar_theme);
  const keyboardPreviewTheme = useCandidatePreviewTheme(themeMode, draft?.screen_keyboard_theme);
  const touchKeyboardSkin = draft?.touch_keyboard_skin ?? "forest";
  const customTouchKeyboardSkin =
    draft?.custom_touch_keyboard_skin ?? defaultTouchKeyboardSkinDesign;
  useEffect(() => setSkinPreviewThemes({}), [candidatePreviewTheme]);
  const touchKeySpacingTenths = draft?.touch_key_spacing_tenths ?? 60;
  const touchRowSpacingTenths = draft?.touch_row_spacing_tenths ?? 70;
  const touchKeyboardHeightAdjustment = draft?.touch_keyboard_height_adjustment ?? 0;
  const installerTrust = availableUpdate ? describeInstallerTrust(availableUpdate) : null;
  const [clipboardEntries, setClipboardEntries] = useState<ClipboardHistoryEntry[]>([]);
  const [clipboardClearArmed, setClipboardClearArmed] = useState(false);
  const availablePages = pages.filter(
    (item) =>
      (item.id !== "home" || Boolean(client.home)) &&
      (item.id !== "typing-statistics" || Boolean(client.typingStatistics)) &&
      (item.id !== "account" || Boolean(client.account || client.appIcon)) &&
      (item.id !== "chat" || Boolean(client.chat)) &&
      (item.id !== "community" || Boolean(client.communitySkins || client.communityResources)) &&
      (item.id !== "floating-toolbar" || showFloatingToolbar),
  );
  const sidebarGroups = ((): (typeof availablePages)[] => {
    if (!macosPlatform) return [availablePages];
    const remaining = new Map(availablePages.map((item) => [item.id, item]));
    const groups = macosSidebarGroups
      .map((ids) =>
        ids.flatMap((id) => {
          const item = remaining.get(id);
          if (!item) return [];
          remaining.delete(id);
          return [item];
        }),
      )
      .filter((group) => group.length > 0);
    const extra = [...remaining.values()];
    if (extra.length > 0) groups.splice(Math.max(groups.length - 1, 0), 0, extra);
    return groups;
  })();
  const mobilePrimaryPageIds: readonly SettingsPageId[] = [
    "home",
    "community",
    "typing-statistics",
    "account",
  ];
  const mobilePrimaryPages = availablePages.filter((item) =>
    mobilePrimaryPageIds.includes(item.id),
  );
  // Physical-keyboard shortcuts and a desktop floating toolbar have no mobile
  // surface. HarmonyOS keeps its hardware shortcuts and keyboard toolbar in the
  // input-method panel, so neither is hidden there.
  //
  // Helper codes are per-host rather than per-form-factor. The Android keyboard
  // sends them: Shift during a quanpin or shuangpin composition passes the next
  // letter to the Engine as a helper code, and the Engine reads the schema and
  // the candidate-row hint from these very preferences. Hiding the page left
  // that shipping feature with no way to pick a schema or turn it off. The
  // Apple keyboard extension has no helper-code input at all, so iOS keeps the
  // page hidden.
  //
  // HarmonyOS was in the hidden list while shipping the same input: its
  // ChineseHelpcodePolicy is the Android one, ported, and the session calls it
  // on every shifted key. So it had the feature and no way to configure it —
  // the very state this comment already describes as the reason Android is not
  // in the list. It also keeps its hardware shortcuts and keyboard toolbar in
  // the input-method panel, so neither of those is hidden there either.
  const mobileHiddenPageIds: readonly SettingsPageId[] = harmonyPlatform
    ? []
    : androidPlatform
      ? ["shortcuts", "floating-toolbar"]
      : ["helpcode", "shortcuts", "floating-toolbar"];
  const mobileSecondaryPages = availablePages.filter(
    (item) => !mobilePrimaryPageIds.includes(item.id) && !mobileHiddenPageIds.includes(item.id),
  );
  const selectPage = (next: SettingsPageId) => {
    if (mobilePlatform && mobileHiddenPageIds.includes(next)) return;
    if (next === page) return;
    setPage(next);
    if (mobilePlatform && typeof window !== "undefined") {
      const current = window.history.state;
      const state = {
        ...(current && typeof current === "object" ? current : {}),
        msimeSettings: true,
        page: next,
      } as Record<string, unknown>;
      delete state.panel;
      window.history.pushState(state, "");
    }
    if (next === "community") setCommunityDestination("all");
  };
  useEffect(() => {
    const pageAvailable =
      availablePages.some((item) => item.id === page) &&
      (!mobilePlatform || !mobileHiddenPageIds.includes(page));
    if (!pageAvailable) setPage(mobilePlatform && client.home ? "home" : "appearance");
  }, [availablePages, client.home, mobilePlatform, page]);
  useEffect(() => {
    if (typeof document === "undefined") return;
    const apply = () => {
      document.documentElement.dataset.theme = resolveSettingsTheme(themeMode, settingsTheme);
    };
    apply();
    if (
      themeMode !== "system" ||
      settingsTheme !== "follow" ||
      typeof window === "undefined" ||
      typeof window.matchMedia !== "function"
    )
      return;
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
    if (!iosPlatform && !snapshot?.preferences.clipboard_history) {
      setClipboardEntries([]);
      return;
    }
    if (!client.clipboard?.list) return;
    void client.clipboard
      .list()
      .then((entries) => {
        if (active) {
          setClipboardEntries(entries);
          setClipboardClearArmed(false);
        }
      })
      .catch(() => undefined);
    return () => {
      active = false;
    };
  }, [client, iosPlatform, page, snapshot?.revision]);
  const mutateClipboardHistory = async (action: () => Promise<void>, failure: string) => {
    try {
      await action();
      setClipboardClearArmed(false);
      if (client.clipboard?.list) setClipboardEntries(await client.clipboard.list());
    } catch {
      setError(failure);
    }
  };
  const openLocalDesigns = () => {
    selectPage("appearance");
    setShowTouchSkinEditor(true);
  };
  const openCommunity = (destination: AccountCommunityDestination | "all") => {
    selectPage("community");
    setCommunityDestination(destination);
  };
  const initialCommunityCategory =
    communityDestination === "published-reply" || communityDestination === "saved-reply"
      ? "reply"
      : communityDestination === "published-dictionary" ||
          communityDestination === "saved-dictionary"
        ? "dictionary"
        : "skin";
  const initialCommunityScope =
    communityDestination === "published-dictionary" || communityDestination === "published-reply"
      ? "mine"
      : communityDestination === "saved-dictionary" || communityDestination === "saved-reply"
        ? "saved"
        : "";
  return (
    <div
      className={settings.shell}
      data-settings-shell=""
      onPointerDownCapture={(event) => {
        pendingTitlebarDrag.current = null;
        if (!client.resizeWindow || event.button !== 0 || windowMaximized) return;
        const rect = event.currentTarget.getBoundingClientRect();
        const edge = 8;
        const n = event.clientY - rect.top < edge,
          s = rect.bottom - event.clientY < edge;
        const w = event.clientX - rect.left < edge,
          e = rect.right - event.clientX < edge;
        const value =
          n && e
            ? "ne"
            : n && w
              ? "nw"
              : s && e
                ? "se"
                : s && w
                  ? "sw"
                  : n
                    ? "n"
                    : s
                      ? "s"
                      : e
                        ? "e"
                        : w
                          ? "w"
                          : null;
        if (value) {
          event.preventDefault();
          event.stopPropagation();
          void client.resizeWindow(value).catch(() => setError("无法调整窗口大小，请重试。"));
        }
      }}
    >
      {confirmation}
      {/* A phone has no window to minimise, maximise, close or drag: the OS owns the frame. The host
          still exposes the window commands on mobile because the same Tauri app binary backs both, so
          the presence of a command is not the question -- the platform is. */}
      {!mobilePlatform && (client.windowControl || client.beginWindowDrag) && (
        <header
          className={settings.titlebar}
          aria-label="窗口控制"
          onDoubleClick={(event) => {
            pendingTitlebarDrag.current = null;
            if (event.button !== 0 || !client.windowControl) return;
            const rect = event.currentTarget.parentElement!.getBoundingClientRect();
            if (
              !windowMaximized &&
              client.resizeWindow &&
              (event.clientX - rect.left < 8 ||
                rect.right - event.clientX < 8 ||
                event.clientY - rect.top < 8 ||
                rect.bottom - event.clientY < 8)
            )
              return;
            void client.windowControl(windowMaximized ? "restore" : "maximize");
          }}
          onPointerDown={(event) => {
            if (event.button === 0 && event.detail < 2 && client.beginWindowDrag)
              pendingTitlebarDrag.current = {
                x: event.clientX,
                y: event.clientY,
                pointerId: event.pointerId,
              };
          }}
          onPointerMove={(event) => {
            const pending = pendingTitlebarDrag.current;
            if (!pending || pending.pointerId !== event.pointerId) return;
            if (event.buttons !== 1) {
              pendingTitlebarDrag.current = null;
              return;
            }
            if (Math.abs(event.clientX - pending.x) + Math.abs(event.clientY - pending.y) < 2)
              return;
            pendingTitlebarDrag.current = null;
            // Invoke during the gesture; catch synchronous and asynchronous host failures.
            void (async () => {
              try {
                await client.beginWindowDrag?.();
              } catch {
                setError("无法移动窗口，请重试。");
              }
            })();
          }}
          onPointerUp={() => {
            pendingTitlebarDrag.current = null;
          }}
          onPointerCancel={() => {
            pendingTitlebarDrag.current = null;
          }}
          onPointerLeave={() => {
            pendingTitlebarDrag.current = null;
          }}
        >
          <span className={settings.title} data-window-title="">
            水杉 IME
          </span>
          {client.windowControl && (
            <span
              className={settings.windowControls}
              onPointerDown={(event) => event.stopPropagation()}
              onDoubleClick={(event) => event.stopPropagation()}
            >
              <button
                type="button"
                aria-label="最小化"
                onClick={() => void client.windowControl!("minimize")}
              >
                <img
                  className={settings.windowIcon}
                  src={windowIcons.minimize}
                  alt=""
                  draggable={false}
                />
              </button>
              <button
                type="button"
                aria-label={windowMaximized ? "还原" : "最大化"}
                onClick={() => void client.windowControl!(windowMaximized ? "restore" : "maximize")}
              >
                <img
                  className={settings.windowIcon}
                  src={windowMaximized ? windowIcons.restore : windowIcons.maximize}
                  alt=""
                  draggable={false}
                />
              </button>
              <button
                type="button"
                className={settings.windowClose}
                aria-label="关闭"
                onClick={() => void client.windowControl!("close")}
              >
                <img
                  className={settings.windowIcon}
                  src={windowIcons.close}
                  alt=""
                  draggable={false}
                />
              </button>
            </span>
          )}
        </header>
      )}
      <div
        className="flex min-h-0 min-w-0 flex-1 overflow-hidden max-phone:flex-col"
        data-settings-body=""
      >
        {/* A bottom tab bar. `order-2` seats it below the content while the DOM keeps it ahead, so
            assistive technology and keyboard focus still reach the navigation first, and the bottom
            padding clears the gesture inset. Hidden above phone width, where the sidebar serves. */}
        {mobilePlatform && (
          <nav
            className="hidden max-phone:order-2 max-phone:grid max-phone:grid-cols-5 max-phone:gap-1.5 max-phone:border-t max-phone:border-edge max-phone:bg-chrome max-phone:px-2 max-phone:pt-2 max-phone:pb-[calc(0.5rem+env(safe-area-inset-bottom,0px))]"
            aria-label="主要功能"
          >
            {mobilePrimaryPages.map((item) => (
              <button
                key={item.id}
                type="button"
                className={`min-h-[42px] min-w-0 cursor-pointer rounded-xl border bg-card text-[13px] ${
                  page === item.id
                    ? "border-accent font-semibold text-accent"
                    : "border-edge text-body"
                }`}
                aria-current={page === item.id ? "page" : undefined}
                onClick={() => selectPage(item.id)}
              >
                {item.id === "home"
                  ? "键盘"
                  : item.id === "typing-statistics"
                    ? "统计"
                    : item.id === "account"
                      ? "账号"
                      : item.title}
              </button>
            ))}
            <label className="flex min-h-[42px] min-w-0 flex-col justify-center gap-px rounded-xl border border-edge bg-card px-2 py-[3px] text-[10px] text-muted">
              更多设置
              <select
                className="min-w-0 border-0 bg-transparent text-xs text-body outline-none"
                aria-label="更多设置"
                value={mobileSecondaryPages.some((item) => item.id === page) ? page : ""}
                onChange={(event) => {
                  if (event.target.value) selectPage(event.target.value as SettingsPageId);
                }}
              >
                <option value="">选择页面</option>
                {mobileSecondaryPages.map((item) => (
                  <option key={item.id} value={item.id}>
                    {item.title}
                  </option>
                ))}
              </select>
            </label>
          </nav>
        )}
        <nav className={settings.sidebar} aria-label="设置分类">
          <div className={settings.sidebarHeader}>
            <img src={logo} alt="" />
            <span>水杉 IME</span>
          </div>
          {sidebarGroups.map((group, index) => (
            <div
              key={group[0].id}
              className={index > 0 ? `${settings.sidebarSection} mt-3.5` : settings.sidebarSection}
              data-sidebar-section=""
            >
              {group.map((item) => (
                <button
                  key={item.id}
                  type="button"
                  className={settings.sidebarItem(page === item.id)}
                  aria-current={page === item.id ? "page" : undefined}
                  aria-controls="settings-content"
                  onClick={() => selectPage(item.id)}
                >
                  <span className={settings.sidebarIcon}>
                    <img src={item.icon} alt="" />
                  </span>
                  {item.title}
                </button>
              ))}
            </div>
          ))}
          <p className={settings.previewLabel}>客户端预览版</p>
        </nav>
        <main
          ref={settingsContentRef}
          id="settings-content"
          className="min-h-0 min-w-0 flex-1 overflow-y-auto pt-0 pr-6 pb-0 pl-4 [scrollbar-gutter:stable] max-phone:px-2"
          aria-labelledby="page-title"
        >
          <div className="mx-auto mt-0.5 mb-0 w-full max-w-[900px] p-3 max-phone:px-1 max-phone:py-3">
            <header className="mb-2 flex items-center gap-2.5 pt-0 pr-6 pb-3 pl-[0.5em]">
              <h1 className="m-0 text-lg font-medium" id="page-title">
                {availablePages.find((item) => item.id === page)?.title ?? "外观"}
              </h1>
            </header>
            {error && (
              <p role="alert" className="error">
                {error}
              </p>
            )}
            {notice && (
              <p role="status" className="notice">
                {notice}
              </p>
            )}
            {busy && !draft && <p role="status">正在读取设置…</p>}
            {client.home && draft && page === "home" && (
              <HomePage
                preferences={draft}
                actions={client.home}
                onOpenPage={(value) => selectPage(value as SettingsPageId)}
                onSelectScheme={selectHomeScheme}
                onOpenChat={client.chat ? () => selectPage("chat") : undefined}
                touchLayout={mobilePlatform}
              />
            )}
            {(client.account || client.appIcon) && page === "account" && (
              <AccountPage
                client={client.account}
                appIcon={client.appIcon}
                platform={
                  androidPlatform ? "android" : client.host?.platform === "ios" ? "ios" : undefined
                }
                onOpenLocalDesigns={client.customTouchKeyboardSkins ? openLocalDesigns : undefined}
                onOpenCommunity={
                  client.communitySkins && client.communityResources ? openCommunity : undefined
                }
                onOpenCloudDictionary={
                  client.openCloudDictionary
                    ? () => {
                        void client.openCloudDictionary!().catch(() =>
                          setError("无法打开云词库，请重试。"),
                        );
                      }
                    : undefined
                }
                onOpenCloudClipboard={
                  client.openCloudClipboard
                    ? () => {
                        void client.openCloudClipboard!().catch(() =>
                          setError("无法打开云剪贴板，请重试。"),
                        );
                      }
                    : undefined
                }
                onOpenAbout={mobilePlatform ? () => selectPage("about") : undefined}
                onOpenDesktopDownload={
                  mobilePlatform && client.openExternalUrl
                    ? () => {
                        void openExternalUrl(desktopDownloadUrl);
                      }
                    : undefined
                }
                onReplayOnboarding={mobilePlatform ? onReplayOnboarding : undefined}
              />
            )}
            {client.chat && page === "chat" && (
              <ChatPage
                client={client.chat}
                autoFocus={iosPlatform}
                onLogin={() => selectPage("account")}
              />
            )}
            {client.communitySkins && client.communityResources && page === "community" && (
              <CommunityHomePage
                key={communityDestination}
                skins={client.communitySkins}
                resources={client.communityResources}
                theme={keyboardPreviewTheme}
                initialMine={communityDestination === "published-skins"}
                initialCategory={initialCommunityCategory}
                initialScope={initialCommunityScope}
                localDictionary={client.dictionary}
                localSkinLibrary={client.customSkinLibrary}
                mobile={mobilePlatform}
                onLogin={() => selectPage("account")}
              />
            )}
            {client.communitySkins && !client.communityResources && page === "community" && (
              <CommunitySkinsPage
                key={communityDestination}
                client={client.communitySkins}
                theme={keyboardPreviewTheme}
                localSkinLibrary={client.customSkinLibrary}
                initialMine={communityDestination === "published-skins"}
                mobile={mobilePlatform}
                onLogin={() => selectPage("account")}
              />
            )}
            {!client.communitySkins && client.communityResources && page === "community" && (
              <CommunityResourcesPage
                client={client.communityResources}
                kind={initialCommunityCategory === "reply" ? "reply" : "dictionary"}
                initialScope={initialCommunityScope}
                mobile={mobilePlatform}
              />
            )}
            {client.typingStatistics && page === "typing-statistics" && (
              <TypingStatisticsPage
                client={client.typingStatistics}
                mobile={mobilePlatform}
                platform={client.host?.platform}
                openSystemSettings={client.openSystemKeyboardSettings}
              />
            )}
            {draft &&
              page !== "typing-statistics" &&
              page !== "account" &&
              page !== "chat" &&
              page !== "community" && (
                <form
                  onSubmit={(event) => {
                    event.preventDefault();
                    void save();
                  }}
                >
                  <fieldset disabled={busy} hidden={page !== "appearance"} aria-label="外观">
                    <AppearanceCandidatePreview
                      preferences={{
                        ...draft,
                        candidate_english_font:
                          host?.platform === "windows"
                            ? (draft.candidate_english_font ?? "Segoe UI")
                            : draft.candidate_english_font,
                      }}
                      scan={client.scanSkinCatalog}
                      readImage={client.readSkinImage}
                      resolveFonts={client.resolveFontFamilies}
                      active={page === "appearance"}
                      revision={snapshot?.revision ?? 0}
                    />
                    {showCandidateFollowCursor && (
                      <div className="section">
                        <label className="section-header">
                          <span className="section-title">
                            候选窗口跟随光标
                            <small>关闭后保持首次出现的位置，直到候选窗口消失。</small>
                          </span>
                          <input
                            aria-label="候选窗口跟随光标"
                            className="toggle"
                            type="checkbox"
                            checked={draft.candidate_follow_cursor ?? true}
                            onChange={(event) =>
                              setDraft({ ...draft, candidate_follow_cursor: event.target.checked })
                            }
                          />
                        </label>
                      </div>
                    )}
                    {showCandidateFontControls ? (
                      <CandidateFontControls
                        value={draft}
                        onChange={(patch) => setDraft({ ...draft, ...patch })}
                        readFonts={client.listFontFamilies}
                        windows={host?.platform === "windows"}
                        englishFont={showCandidateEnglishFont}
                      />
                    ) : (
                      <div className="section">
                        <small>当前宿主的候选面板不支持自定义字体或字号。</small>
                      </div>
                    )}
                    {showCandidateFontControls && (
                      <div className="section">
                        <label className="section-header">
                          <span className="section-title">候选窗字号</span>
                          <select
                            aria-label="候选窗字号"
                            value={candidateFontSize(draft.candidate_font_size)}
                            onChange={(event) =>
                              setDraft({
                                ...draft,
                                candidate_font_size: Number(event.target.value),
                              })
                            }
                          >
                            {candidateFontSizes.map((size) => (
                              <option key={size} value={size}>
                                {size}
                              </option>
                            ))}
                          </select>
                        </label>
                      </div>
                    )}
                    {showCandidateFontControls && (
                      <div className="section">
                        <label className="section-header">
                          <span className="section-title">候选窗预编辑字号</span>
                          <select
                            aria-label="候选窗预编辑字号"
                            value={candidatePreeditFontSize(draft.candidate_preedit_font_size)}
                            onChange={(event) =>
                              setDraft({
                                ...draft,
                                candidate_preedit_font_size: Number(event.target.value),
                              })
                            }
                          >
                            {candidateFontSizes.map((size) => (
                              <option key={size} value={size}>
                                {size}
                              </option>
                            ))}
                          </select>
                        </label>
                      </div>
                    )}
                    <div className="section">
                      <div className="section-header">
                        <span className="section-title">候选文字颜色</span>
                        <div className="candidate-color-control">
                          <input
                            aria-label="候选文字颜色"
                            type="color"
                            value={
                              candidateTextColor(draft.candidate_text_color) ??
                              (candidatePreviewTheme === "light" ? "#1a1a1a" : "#e9e8e8")
                            }
                            onChange={(event) =>
                              setDraft({ ...draft, candidate_text_color: event.target.value })
                            }
                          />
                          <button
                            type="button"
                            className={`candidate-color-reset${candidateTextColor(draft.candidate_text_color) ? "" : " is-active"}`}
                            aria-pressed={!candidateTextColor(draft.candidate_text_color)}
                            onClick={() => {
                              if (candidateTextColor(draft.candidate_text_color))
                                setDraft({ ...draft, candidate_text_color: null });
                            }}
                          >
                            跟随主题
                          </button>
                        </div>
                      </div>
                    </div>
                    {!showCandidateRowColors && (
                      <div className="section">
                        <small>当前宿主的候选面板不支持强调或选中行颜色。</small>
                      </div>
                    )}
                    {!showCandidateSelectionAppearance && (
                      <div className="section">
                        <small>当前宿主的候选面板不支持悬停或边框颜色。</small>
                      </div>
                    )}
                    {showCandidateRowColors && (
                      <div className="section">
                        <div className="section-header">
                          <span className="section-title">候选强调色</span>
                          <div className="candidate-color-control">
                            <input
                              aria-label="候选强调色"
                              type="color"
                              value={
                                candidateTextColor(draft.candidate_accent_color) ??
                                (candidatePreviewTheme === "light" ? "#1a73e8" : "#8ab4f8")
                              }
                              onChange={(event) =>
                                setDraft({ ...draft, candidate_accent_color: event.target.value })
                              }
                            />
                            <button
                              type="button"
                              aria-label="候选强调色跟随主题"
                              className={`candidate-color-reset${candidateTextColor(draft.candidate_accent_color) ? "" : " is-active"}`}
                              aria-pressed={!candidateTextColor(draft.candidate_accent_color)}
                              onClick={() => {
                                if (candidateTextColor(draft.candidate_accent_color))
                                  setDraft({ ...draft, candidate_accent_color: null });
                              }}
                            >
                              跟随主题
                            </button>
                          </div>
                        </div>
                      </div>
                    )}
                    {showCandidateRowColors && (
                      <div className="section">
                        <div className="section-header">
                          <span className="section-title">候选选中色</span>
                          <div className="candidate-color-control">
                            <input
                              aria-label="候选选中色"
                              type="color"
                              value={
                                candidateTextColor(draft.candidate_selected_color) ??
                                (candidatePreviewTheme === "light" ? "#e8e8e8" : "#3e3e3e")
                              }
                              onChange={(event) =>
                                setDraft({ ...draft, candidate_selected_color: event.target.value })
                              }
                            />
                            <button
                              type="button"
                              aria-label="候选选中色跟随主题"
                              className={`candidate-color-reset${candidateTextColor(draft.candidate_selected_color) ? "" : " is-active"}`}
                              aria-pressed={!candidateTextColor(draft.candidate_selected_color)}
                              onClick={() => {
                                if (candidateTextColor(draft.candidate_selected_color))
                                  setDraft({ ...draft, candidate_selected_color: null });
                              }}
                            >
                              跟随主题
                            </button>
                          </div>
                        </div>
                      </div>
                    )}
                    {showCandidateSelectionAppearance && (
                      <div className="section">
                        <div className="section-header">
                          <span className="section-title">候选悬停色</span>
                          <div className="candidate-color-control">
                            <input
                              aria-label="候选悬停色"
                              type="color"
                              value={
                                candidateTextColor(draft.candidate_hover_color) ??
                                (candidatePreviewTheme === "light" ? "#ececec" : "#414141")
                              }
                              onChange={(event) =>
                                setDraft({ ...draft, candidate_hover_color: event.target.value })
                              }
                            />
                            <button
                              type="button"
                              aria-label="候选悬停色跟随主题"
                              className={`candidate-color-reset${candidateTextColor(draft.candidate_hover_color) ? "" : " is-active"}`}
                              aria-pressed={!candidateTextColor(draft.candidate_hover_color)}
                              onClick={() => {
                                if (candidateTextColor(draft.candidate_hover_color))
                                  setDraft({ ...draft, candidate_hover_color: null });
                              }}
                            >
                              跟随主题
                            </button>
                          </div>
                        </div>
                      </div>
                    )}
                    <div className="section">
                      <div className="section-header">
                        <span className="section-title">候选表面色</span>
                        <div className="candidate-color-control">
                          <input
                            aria-label="候选表面色"
                            type="color"
                            value={
                              candidateTextColor(draft.candidate_surface_color) ??
                              (candidatePreviewTheme === "light" ? "#ffffff" : "#202020")
                            }
                            onChange={(event) =>
                              setDraft({ ...draft, candidate_surface_color: event.target.value })
                            }
                          />
                          <button
                            type="button"
                            aria-label="候选表面色跟随主题"
                            className={`candidate-color-reset${candidateTextColor(draft.candidate_surface_color) ? "" : " is-active"}`}
                            onClick={() => setDraft({ ...draft, candidate_surface_color: null })}
                          >
                            跟随主题
                          </button>
                        </div>
                      </div>
                    </div>
                    {showCandidateSelectionAppearance && (
                      <div className="section">
                        <div className="section-header">
                          <span className="section-title">候选边框色</span>
                          <div className="candidate-color-control">
                            <input
                              aria-label="候选边框色"
                              type="color"
                              value={
                                candidateTextColor(draft.candidate_border_color) ??
                                (candidatePreviewTheme === "light" ? "#dedede" : "#303030")
                              }
                              onChange={(event) =>
                                setDraft({ ...draft, candidate_border_color: event.target.value })
                              }
                            />
                            <button
                              type="button"
                              aria-label="候选边框色跟随主题"
                              className={`candidate-color-reset${candidateTextColor(draft.candidate_border_color) ? "" : " is-active"}`}
                              onClick={() => setDraft({ ...draft, candidate_border_color: null })}
                            >
                              跟随主题
                            </button>
                          </div>
                        </div>
                      </div>
                    )}
                    <div className="section">
                      <div className="section-header">
                        <span className="section-title">候选编号颜色</span>
                        <div className="candidate-color-control">
                          <input
                            aria-label="候选编号颜色"
                            type="color"
                            value={
                              candidateTextColor(draft.candidate_number_color) ??
                              (candidatePreviewTheme === "light" ? "#5f6368" : "#bdc1c6")
                            }
                            onChange={(event) =>
                              setDraft({ ...draft, candidate_number_color: event.target.value })
                            }
                          />
                          <button
                            type="button"
                            aria-label="候选编号颜色跟随主题"
                            className={`candidate-color-reset${candidateTextColor(draft.candidate_number_color) ? "" : " is-active"}`}
                            aria-pressed={!candidateTextColor(draft.candidate_number_color)}
                            onClick={() => {
                              if (candidateTextColor(draft.candidate_number_color))
                                setDraft({ ...draft, candidate_number_color: null });
                            }}
                          >
                            跟随主题
                          </button>
                        </div>
                      </div>
                    </div>
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">每页候选项数量</span>
                        <select
                          aria-label="每页候选项数量"
                          value={draft.candidate_page_size}
                          onChange={(event) =>
                            setDraft({ ...draft, candidate_page_size: Number(event.target.value) })
                          }
                        >
                          {candidatePageSizes.map((size) => (
                            <option key={size} value={size}>
                              {size}
                            </option>
                          ))}
                        </select>
                      </label>
                    </div>
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">
                          主题模式<small>设置窗口和各界面的默认明暗模式</small>
                        </span>
                        <select
                          aria-label="主题模式"
                          value={themeMode}
                          onChange={(event) =>
                            setDraft({ ...draft, theme: event.target.value as ThemeMode })
                          }
                        >
                          <option value="dark">深色</option>
                          <option value="light">浅色</option>
                          <option value="system">跟随系统</option>
                        </select>
                      </label>
                    </div>
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">
                          设置界面主题<small>覆盖主题模式，仅影响当前设置窗口</small>
                        </span>
                        <select
                          aria-label="设置界面主题"
                          value={settingsTheme}
                          onChange={(event) =>
                            setDraft({
                              ...draft,
                              settings_theme: event.target.value as SurfaceTheme,
                            })
                          }
                        >
                          <option value="follow">跟随全局</option>
                          <option value="dark">深色</option>
                          <option value="light">浅色</option>
                        </select>
                      </label>
                    </div>
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">
                          候选窗口主题
                          <small>
                            预览跟随主题模式；Linux IBus panel 支持时使用，跟随时由桌面主题决定
                          </small>
                        </span>
                        <select
                          aria-label="候选窗口主题"
                          value={draft.candidate_theme ?? "follow"}
                          onChange={(event) =>
                            setDraft({
                              ...draft,
                              candidate_theme: event.target.value as SurfaceTheme,
                            })
                          }
                        >
                          <option value="follow">跟随全局</option>
                          <option value="dark">深色</option>
                          <option value="light">浅色</option>
                        </select>
                      </label>
                    </div>
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">
                          悬浮工具栏主题
                          <small>覆盖主题模式；当前影响工具栏设置预览，原生工具栏需宿主支持</small>
                        </span>
                        <select
                          aria-label="悬浮工具栏主题"
                          value={draft.toolbar_theme ?? "follow"}
                          onChange={(event) =>
                            setDraft({
                              ...draft,
                              toolbar_theme: event.target.value as SurfaceTheme,
                            })
                          }
                        >
                          <option value="follow">跟随全局</option>
                          <option value="dark">深色</option>
                          <option value="light">浅色</option>
                        </select>
                      </label>
                    </div>
                    {!mobilePlatform && (
                      <div className="section">
                        <label className="section-header">
                          <span className="section-title">
                            菜单主题<small>覆盖托盘菜单与候选右键菜单的明暗外观</small>
                          </span>
                          <select
                            aria-label="菜单主题"
                            value={draft.menu_theme ?? "follow"}
                            onChange={(event) =>
                              setDraft({ ...draft, menu_theme: event.target.value as SurfaceTheme })
                            }
                          >
                            <option value="follow">跟随全局</option>
                            <option value="dark">深色</option>
                            <option value="light">浅色</option>
                          </select>
                        </label>
                      </div>
                    )}
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">
                          表情面板主题<small>覆盖 Emoji、颜文字和符号面板的明暗外观</small>
                        </span>
                        <select
                          aria-label="表情面板主题"
                          value={draft.emoji_theme ?? "follow"}
                          onChange={(event) =>
                            setDraft({ ...draft, emoji_theme: event.target.value as SurfaceTheme })
                          }
                        >
                          <option value="follow">跟随全局</option>
                          <option value="dark">深色</option>
                          <option value="light">浅色</option>
                        </select>
                      </label>
                    </div>
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">
                          手写识别板主题<small>覆盖手写识别板的明暗外观</small>
                        </span>
                        <select
                          aria-label="手写识别板主题"
                          value={draft.handwriting_theme ?? "follow"}
                          onChange={(event) =>
                            setDraft({
                              ...draft,
                              handwriting_theme: event.target.value as SurfaceTheme,
                            })
                          }
                        >
                          <option value="follow">跟随全局</option>
                          <option value="dark">深色</option>
                          <option value="light">浅色</option>
                        </select>
                      </label>
                    </div>
                    {!androidPlatform && (
                      <div className="section">
                        <label className="section-header">
                          <span className="section-title">
                            语音输入弹出条主题<small>覆盖语音输入面板的明暗外观</small>
                          </span>
                          <select
                            aria-label="语音输入弹出条主题"
                            value={draft.voice_theme ?? "follow"}
                            onChange={(event) =>
                              setDraft({
                                ...draft,
                                voice_theme: event.target.value as SurfaceTheme,
                              })
                            }
                          >
                            <option value="follow">跟随全局</option>
                            <option value="dark">深色</option>
                            <option value="light">浅色</option>
                          </select>
                        </label>
                      </div>
                    )}
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">候选项排列方式</span>
                        <select
                          aria-label="候选项排列方式"
                          value={draft.candidate_layout ?? "vertical"}
                          onChange={(event) =>
                            setDraft({
                              ...draft,
                              candidate_layout: event.target
                                .value as Preferences["candidate_layout"],
                            })
                          }
                        >
                          <option value="horizontal">横向</option>
                          <option value="vertical">纵向</option>
                        </select>
                      </label>
                    </div>
                    {showShuangpinPreedit && (
                      <div className="section">
                        <label className="section-header">
                          <span className="section-title">
                            双拼预编辑
                            <small>
                              仅在双拼方案下生效；选择保留原始双拼按键，或显示展开后的拼音分词。
                            </small>
                          </span>
                          <select
                            aria-label="双拼预编辑"
                            value={draft.shuangpin_preedit_uses_raw === false ? "pinyin" : "raw"}
                            onChange={(event) =>
                              setDraft({
                                ...draft,
                                shuangpin_preedit_uses_raw: event.target.value === "raw",
                              })
                            }
                          >
                            <option value="raw">原始按键</option>
                            <option value="pinyin">拼音分词</option>
                          </select>
                        </label>
                      </div>
                    )}
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">行内预编辑</span>
                        <select
                          aria-label="行内预编辑"
                          value={draft.tsf_preedit_style ?? "raw"}
                          onChange={(event) =>
                            setDraft({
                              ...draft,
                              tsf_preedit_style: event.target
                                .value as Preferences["tsf_preedit_style"],
                            })
                          }
                        >
                          <option value="raw">原始按键</option>
                          <option value="pinyin">拼音分词</option>
                          <option value="empty">不显示</option>
                        </select>
                      </label>
                    </div>
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">候选窗预编辑</span>
                        <select
                          aria-label="候选窗预编辑"
                          value={draft.candidate_preedit_style ?? "pinyin"}
                          onChange={(event) =>
                            setDraft({
                              ...draft,
                              candidate_preedit_style: event.target
                                .value as Preferences["candidate_preedit_style"],
                            })
                          }
                        >
                          <option value="pinyin">拼音分词</option>
                          <option value="empty">不显示</option>
                        </select>
                      </label>
                    </div>
                  </fieldset>
                  <fieldset disabled={busy} hidden={page !== "dictionary"} aria-label="词库">
                    {client.dictionaryManifest && (
                      <DictionaryManifestCard read={client.dictionaryManifest} />
                    )}
                    {client.dictionary?.importPersonal && (
                      <PersonalDictionaryImportCard
                        dictionary={client.dictionary}
                        platform={client.host?.platform}
                      />
                    )}
                    {client.dictionary && (
                      <div
                        className={`section ${settings.managerHeader}`}
                        role="region"
                        aria-label="快捷短语管理"
                      >
                        <div className="section-header">
                          <span className="section-title">
                            本地词库管理
                            <small>
                              查询、新增、编辑、导入、导出和删除 Engine
                              用户词库。导入支持标准、Windows TSV、Rime 和纯汉字自动注音。
                            </small>
                          </span>
                          <span>
                            <button
                              type="button"
                              className="secondary"
                              disabled={phraseBusy}
                              onClick={() => void loadPhrases(dictionaryKind, 0)}
                            >
                              查询
                            </button>{" "}
                            <button
                              type="button"
                              className="secondary"
                              disabled={phraseBusy}
                              onClick={() =>
                                setPhraseForm({
                                  key: "",
                                  value: "",
                                  weight: 10,
                                  previous: null,
                                })
                              }
                            >
                              新增词条
                            </button>{" "}
                            <button
                              type="button"
                              className="secondary"
                              disabled={phraseBusy || dictionaryFormat === "hans"}
                              onClick={() => void exportPhrases()}
                            >
                              导出当前类型
                            </button>{" "}
                            <button
                              type="button"
                              className="secondary"
                              disabled={phraseBusy}
                              onClick={() => void exportAllPhrases()}
                            >
                              导出全部
                            </button>
                            <label className="secondary">
                              导入
                              <input
                                hidden
                                type="file"
                                accept=".txt,.tsv,.yaml,.yml,text/plain"
                                disabled={phraseBusy}
                                onChange={(event) => {
                                  const file = event.target.files?.[0];
                                  if (file) {
                                    const name = file.name.toLowerCase();
                                    if (name.endsWith(".yaml") || name.endsWith(".yml"))
                                      setDictionaryFormat("rime");
                                    void importPhrases(file);
                                  }
                                  event.currentTarget.value = "";
                                }}
                              />
                            </label>
                          </span>
                        </div>
                        {dictionaryPendingCount > 0 && (
                          <p className="input-setting-description" role="status">
                            {dictionaryPendingCount}{" "}
                            项等待键盘同步。打开水杉键盘后会在空闲时逐条生效。
                          </p>
                        )}
                        {dictionarySnapshotError && (
                          <p role="alert" className="error">
                            {dictionarySnapshotError}
                          </p>
                        )}
                        {dictionaryFailures.length > 0 && (
                          <div className={settings.failures} role="alert">
                            <p>
                              有 {dictionaryFailures.length}{" "}
                              项词库请求同步失败，可以重试或移除失败记录。
                            </p>
                            <ul>
                              {dictionaryFailures.map((failure) => (
                                <li key={failure.request_id}>
                                  <span>
                                    <strong>{failure.label}</strong>
                                    <small>{failure.error}</small>
                                  </span>
                                  <span>
                                    <button
                                      type="button"
                                      className="secondary"
                                      disabled={phraseBusy || !client.dictionary?.retry}
                                      onClick={() =>
                                        void retryDictionaryFailure(failure.request_id)
                                      }
                                    >
                                      重试
                                    </button>{" "}
                                    <button
                                      type="button"
                                      className="secondary"
                                      disabled={phraseBusy || !client.dictionary?.dismissFailure}
                                      onClick={() =>
                                        void dismissDictionaryFailure(failure.request_id)
                                      }
                                    >
                                      移除记录
                                    </button>
                                  </span>
                                </li>
                              ))}
                            </ul>
                          </div>
                        )}
                        <div className={settings.managerControls}>
                          <label>
                            词库{" "}
                            <select
                              aria-label="本地词库类型"
                              value={dictionaryKind}
                              disabled={phraseBusy}
                              onChange={(event) => {
                                const kind = event.target.value as LocalDictionaryKind;
                                setDictionaryKind(kind);
                                if (kind !== "pinyin" && dictionaryFormat === "hans")
                                  setDictionaryFormat("standard");
                                setPhrases([]);
                                void loadPhrases(kind);
                              }}
                            >
                              {localDictionaryKinds.map(([kind, label]) => (
                                <option key={kind} value={kind}>
                                  {label}
                                </option>
                              ))}
                            </select>
                          </label>
                          <label>
                            文件格式{" "}
                            <select
                              aria-label="本地词库文件格式"
                              value={dictionaryFormat}
                              disabled={phraseBusy}
                              onChange={(event) =>
                                setDictionaryFormat(event.target.value as LocalDictionaryFormat)
                              }
                            >
                              <option value="standard">词在前（标准 TSV）</option>
                              <option value="windows">编码在前（Windows TSV）</option>
                              <option value="rime">Rime userdb / dict.yaml</option>
                              {dictionaryKind === "pinyin" && (
                                <option value="hans">汉字自动注音（仅导入）</option>
                              )}
                            </select>
                          </label>
                          <label>
                            编码前缀{" "}
                            <input
                              value={phraseSearch}
                              placeholder="留空查看全部"
                              onChange={(event) => setPhraseSearch(event.target.value)}
                            />
                          </label>
                        </div>
                        {phraseError && (
                          <p role="alert" className="error">
                            {phraseError}
                          </p>
                        )}
                        {phraseNotice && (
                          <p role="status" className={settings.empty}>
                            {phraseNotice}
                          </p>
                        )}
                        {phraseForm && (
                          <div className={settings.phraseForm}>
                            <label>
                              编码{" "}
                              <input
                                value={phraseForm.key}
                                onChange={(event) =>
                                  setPhraseForm({ ...phraseForm, key: event.target.value })
                                }
                              />
                              <small className={settings.keyHint}>
                                {dictionaryKindKeyHint(dictionaryKind)}
                              </small>
                            </label>
                            <label>
                              {dictionaryKind === "quick_phrase" ? "短语" : "词条"}{" "}
                              <input
                                value={phraseForm.value}
                                onChange={(event) =>
                                  setPhraseForm({ ...phraseForm, value: event.target.value })
                                }
                              />
                            </label>
                            <label>
                              权重{" "}
                              <input
                                type="number"
                                value={phraseForm.weight}
                                onChange={(event) =>
                                  setPhraseForm({
                                    ...phraseForm,
                                    weight: Number(event.target.value),
                                  })
                                }
                              />
                            </label>
                            <button
                              type="button"
                              disabled={phraseBusy}
                              onClick={() => void savePhrase()}
                            >
                              保存
                            </button>
                            <button
                              type="button"
                              className="secondary"
                              disabled={phraseBusy}
                              onClick={() => setPhraseForm(null)}
                            >
                              取消
                            </button>
                          </div>
                        )}
                        {phrases.length === 0 ? (
                          <p className={settings.empty}>
                            点击查询后查看
                            {localDictionaryKinds.find(([kind]) => kind === dictionaryKind)?.[1] ??
                              "词库"}
                            词条
                          </p>
                        ) : (
                          <ul
                            ref={phraseListRef}
                            className={settings.phraseList}
                            aria-label="词库查询结果"
                          >
                            {phrases
                              .filter((entry) => entry.key.startsWith(phraseSearch))
                              .map((entry, index) => (
                                <li key={`${entry.key}-${entry.value}-${index}`}>
                                  <span>
                                    <code>{entry.key}</code>　{entry.value}　
                                    <small>{entry.weight}</small>
                                  </span>
                                  <span>
                                    <button
                                      type="button"
                                      className="secondary"
                                      disabled={phraseBusy}
                                      onClick={() =>
                                        setPhraseForm({
                                          key: entry.key,
                                          value: entry.value,
                                          weight: entry.weight,
                                          previous: entry,
                                        })
                                      }
                                    >
                                      编辑
                                    </button>{" "}
                                    <button
                                      type="button"
                                      className="secondary"
                                      disabled={phraseBusy}
                                      onClick={() => void removePhrase(entry)}
                                    >
                                      删除
                                    </button>
                                  </span>
                                </li>
                              ))}
                          </ul>
                        )}
                        <div className="flex items-center justify-center gap-4 text-xs text-secondary">
                          <button
                            type="button"
                            className="secondary"
                            disabled={phraseBusy || phrasePage.offset === 0}
                            onClick={() =>
                              turnPhrasePage(Math.max(0, phrasePage.offset - DICTIONARY_PAGE_SIZE))
                            }
                          >
                            上一页
                          </button>
                          <span aria-live="polite">{phrasePage.status}</span>
                          <button
                            type="button"
                            className="secondary"
                            disabled={phraseBusy || !phrasePage.hasMore}
                            onClick={() => turnPhrasePage(phrasePage.offset + DICTIONARY_PAGE_SIZE)}
                          >
                            下一页
                          </button>
                        </div>
                      </div>
                    )}
                    {macosPlatform && client.resetLearnedData && (
                      <div className="section" role="region" aria-label="学习数据">
                        <div className="section-header">
                          <span className="section-title">
                            学习数据
                            <small>
                              清除候选词频、用户词典和拼音学习记录；输入方案与其他设置不会改变。
                            </small>
                          </span>
                          <button
                            type="button"
                            className="secondary danger-button"
                            disabled={phraseBusy}
                            onClick={() => void resetLearnedData()}
                          >
                            清除全部学习数据
                          </button>
                        </div>
                      </div>
                    )}
                  </fieldset>
                  <fieldset disabled={busy} hidden={page !== "skin"} aria-label="皮肤">
                    <div className={settings.skinIntro}>
                      选择候选窗和悬浮工具栏使用的主题；明暗预览仅影响当前卡片，不修改设置。
                    </div>
                    {snapshot?.candidate_skin_catalog && (
                      <div className={settings.externalMeta} role="status">
                        外部皮肤目录：
                        {snapshot.candidate_skin_catalog.scanned
                          ? `已扫描（${snapshot.candidate_skin_catalog.packages.length} 个）`
                          : "尚未扫描"}
                        {snapshot.candidate_skin_catalog.issues?.length
                          ? `，${snapshot.candidate_skin_catalog.issues.length} 个问题`
                          : ""}
                      </div>
                    )}
                    <div className={settings.skinGrid}>
                      {skinOptions.map(([id, title, description]) => (
                        <article
                          aria-label={title}
                          className={settings.skinCard(
                            (draft.candidate_skin ?? "willow_green") === id,
                          )}
                          key={id}
                        >
                          <div className={settings.skinCardHeader} data-skin-card-header="">
                            <div className={settings.skinCardBody}>
                              <span className={settings.skinCardTitle}>
                                {title} (
                                {(skinPreviewThemes[id] ?? candidatePreviewTheme) === "dark"
                                  ? "Dark"
                                  : "Light"}
                                )
                              </span>
                              <span className={settings.skinCardDescription}>{description}</span>
                            </div>
                            <div className={settings.skinCardActions}>
                              <button
                                type="button"
                                role="switch"
                                aria-label={title}
                                aria-checked={(draft.candidate_skin ?? "willow_green") === id}
                                className={settings.skinSwitch(
                                  (draft.candidate_skin ?? "willow_green") === id,
                                )}
                                onClick={() => setDraft({ ...draft, candidate_skin: id })}
                              >
                                <span
                                  className={settings.skinSwitchKnob(
                                    (draft.candidate_skin ?? "willow_green") === id,
                                  )}
                                />
                              </button>
                              <button
                                type="button"
                                className={settings.skinPreviewSwitch}
                                onClick={() =>
                                  setSkinPreviewThemes((current) => ({
                                    ...current,
                                    [id]:
                                      (current[id] ?? candidatePreviewTheme) === "dark"
                                        ? "light"
                                        : "dark",
                                  }))
                                }
                              >
                                {(skinPreviewThemes[id] ?? candidatePreviewTheme) === "dark"
                                  ? "预览浅色"
                                  : "预览深色"}
                              </button>
                            </div>
                          </div>
                          <div
                            className={`${settings.skinCardPreview} skin-${id}`}
                            data-skin-preview=""
                            data-preview-theme={skinPreviewThemes[id] ?? candidatePreviewTheme}
                            style={candidateSkinPalette(
                              id,
                              skinPreviewThemes[id] ?? candidatePreviewTheme,
                            )}
                            aria-hidden="true"
                          >
                            <div className={settings.skinPreviewStage} data-skin-stage="">
                              <SkinCandidatePreview orientation="horizontal" />
                            </div>
                            <div className={settings.skinPreviewStage} data-skin-stage="">
                              <SkinCandidatePreview orientation="vertical" />
                            </div>
                            <div className={settings.skinPreviewStage} data-skin-stage="">
                              <SkinToolbarPreview />
                            </div>
                          </div>
                        </article>
                      ))}
                    </div>
                    <ExternalSkins
                      activeTheme={candidatePreviewTheme}
                      scan={client.scanSkinCatalog}
                      openDirectory={client.openSkinDirectory}
                      importsSkin={host?.skin_directory_import === true}
                      readImage={client.readSkinImage}
                      readFont={client.readSkinFont}
                      readToolbarCss={client.readSkinToolbarCss}
                      selected={draft.candidate_skin ?? "willow_green"}
                      layout={draft.candidate_layout ?? "vertical"}
                      onSelect={(id) => setDraft({ ...draft, candidate_skin: id })}
                    />
                  </fieldset>
                  <fieldset
                    disabled={busy}
                    hidden={page !== "floating-toolbar"}
                    aria-label="悬浮工具栏"
                  >
                    <div className={`section ${settings.toolbarCard}`}>
                      <label className={`section-header ${settings.toolbarSettingRow}`}>
                        <span className="section-title">
                          在桌面显示悬浮工具栏<small>快速访问输入法状态与常用功能</small>
                        </span>
                        <input
                          aria-label="在桌面显示悬浮工具栏"
                          className="toggle"
                          type="checkbox"
                          checked={floatingToolbar.enabled}
                          onChange={(event) =>
                            setDraft({
                              ...draft,
                              floating_toolbar: {
                                ...floatingToolbar,
                                enabled: event.target.checked,
                              },
                            })
                          }
                        />
                      </label>
                      <div className={settings.toolbarPreviewArea} aria-label="悬浮工具栏预览">
                        <div className={settings.toolbarPreviewLabel}>预览</div>
                        <div
                          className={`${settings.skinCardPreview} skin-${draft.candidate_skin ?? "willow_green"}`}
                          data-skin-preview=""
                          data-toolbar-preview=""
                          data-preview-theme={toolbarPreviewTheme}
                          style={candidateSkinPalette(
                            draft.candidate_skin ?? "willow_green",
                            toolbarPreviewTheme,
                          )}
                        >
                          <SkinToolbarPreview preferences={floatingToolbar} />
                        </div>
                      </div>
                    </div>
                    {!showToolbarAppearance && (
                      <div className="section">
                        <small>
                          当前宿主以输入法菜单呈现工具栏，缩放和图标尺寸不适用；组件选择仍然生效，上方开关仍然生效。
                        </small>
                      </div>
                    )}
                    {showToolbarAppearance && (
                      <div className={`section ${settings.toolbarAppearanceHeader}`}>
                        <label className="section-header">
                          <span className="section-title">
                            工具栏缩放<small>相对系统 DPI 的额外缩放，不改变系统显示缩放</small>
                          </span>
                          <select
                            aria-label="工具栏缩放"
                            value={floatingToolbar.scale_percent}
                            onChange={(event) =>
                              setDraft({
                                ...draft,
                                floating_toolbar: {
                                  ...floatingToolbar,
                                  scale_percent: Number(
                                    event.target.value,
                                  ) as FloatingToolbarPreferences["scale_percent"],
                                },
                              })
                            }
                          >
                            {floatingToolbarScales.map((value) => (
                              <option key={value} value={value}>
                                {value}%
                              </option>
                            ))}
                          </select>
                        </label>
                        <div className="input-option-divider" />
                        <label className="section-header">
                          <span className="section-title">
                            图标尺寸<small>图标基准大小（像素），再乘以上方缩放</small>
                          </span>
                          <select
                            aria-label="图标尺寸"
                            value={floatingToolbar.font_size}
                            onChange={(event) =>
                              setDraft({
                                ...draft,
                                floating_toolbar: {
                                  ...floatingToolbar,
                                  font_size: Number(
                                    event.target.value,
                                  ) as FloatingToolbarPreferences["font_size"],
                                },
                              })
                            }
                          >
                            {floatingToolbarFontSizes.map((value) => (
                              <option key={value} value={value}>
                                {value}
                              </option>
                            ))}
                          </select>
                        </label>
                      </div>
                    )}
                    {showToolbarComponents && (
                      <div className={`section ${settings.toolbarComponents}`}>
                        <div className="section-title">
                          工具栏组件<small>勾选要显示在悬浮工具栏中的功能</small>
                        </div>
                        <div className={settings.toolbarComponentList}>
                          <label className={`check-option ${settings.toolbarRequiredOption}`}>
                            <input type="checkbox" checked disabled />
                            <span>中英文切换</span>
                            <span className={settings.toolbarRequiredLabel}>始终显示</span>
                          </label>
                          {floatingToolbarOptions
                            .filter(([, , capability]) => !capability || !host || host[capability])
                            .map(([key, label]) => (
                              <div key={key}>
                                <div className="input-option-divider" />
                                <label className="check-option">
                                  <input
                                    type="checkbox"
                                    checked={floatingToolbar[key]}
                                    onChange={(event) =>
                                      setDraft({
                                        ...draft,
                                        floating_toolbar: {
                                          ...floatingToolbar,
                                          [key]: event.target.checked,
                                        },
                                      })
                                    }
                                  />
                                  <span>{label}</span>
                                </label>
                              </div>
                            ))}
                        </div>
                      </div>
                    )}
                  </fieldset>
                  <fieldset disabled={busy} hidden={page !== "input"} aria-label="输入">
                    {iosPlatform && (
                      <div className="section">
                        <div className="section-title">手写输入</div>
                        <p>
                          首次在键盘中使用手写时下载中文模型，需要完全访问权限。下载后可离线识别，笔迹和识别结果不会上传。Google
                          ML Kit 会发送性能及使用统计。
                        </p>
                        {client.openExternalUrl && (
                          <button
                            type="button"
                            className="secondary"
                            onClick={() => void openExternalUrl(handwritingSdkPrivacyUrl)}
                          >
                            手写 SDK 隐私说明
                          </button>
                        )}
                      </div>
                    )}
                    {harmonyPlatform && (
                      <div className="section">
                        <div className="section-title">手写输入</div>
                        <p>
                          手写使用系统的文字识别能力，笔迹留在本机、不上传。设备未提供该能力时手写方案会明确提示，不会改用其他识别方式。
                        </p>
                      </div>
                    )}
                    {androidPlatform && (
                      <div className="section">
                        <div className="section-title">Android 手写输入</div>
                        <p>
                          首次在 Android 键盘中切换到手写时，可能需要下载 Google ML Kit
                          中文手写模型。模型下载完成后可离线识别；笔迹和识别结果只用于当前输入，不会上传。Google
                          ML Kit 可能发送性能及使用统计。
                        </p>
                        {client.openExternalUrl && (
                          <button
                            type="button"
                            className="secondary"
                            onClick={() => void openExternalUrl(handwritingSdkPrivacyUrl)}
                          >
                            手写 SDK 隐私说明
                          </button>
                        )}
                      </div>
                    )}
                    {mobilePlatform && (
                      <div className="section input-ai-info">
                        <div className="section-title">高情商回复</div>
                        <p>
                          复制对方的话，切换到高情商回复键盘，点“粘贴”后选择回复风格。支持帮你回、帮润色和换一句，点选回复插入聊天输入框。
                        </p>
                        <button
                          type="button"
                          className="secondary"
                          onClick={() => selectPage("ai")}
                        >
                          配置键盘 AI
                        </button>
                      </div>
                    )}
                    <div
                      className="section"
                      role="group"
                      aria-labelledby="input-mode-title"
                      hidden={client.touchKeyboardSchemes}
                    >
                      <div className="section-title" id="input-mode-title">
                        输入模式
                      </div>
                      <div className="input-setting-description">
                        切换中文或日文输入，并保留各模式上次选择的方案
                      </div>
                      <div className="input-option-content input-mode-options">
                        <label className="radio-option">
                          <input
                            type="radio"
                            name="input-mode"
                            value="chinese"
                            checked={draft.scheme !== "japanese"}
                            onChange={() =>
                              setDraft({ ...draft, scheme: draft.last_chinese_scheme ?? "quanpin" })
                            }
                          />
                          <span>中文</span>
                        </label>
                        <div className="input-option-divider" />
                        <label className="radio-option">
                          <input
                            type="radio"
                            name="input-mode"
                            value="japanese"
                            checked={draft.scheme === "japanese"}
                            onChange={() =>
                              setDraft({
                                ...draft,
                                last_chinese_scheme:
                                  draft.scheme === "japanese"
                                    ? draft.last_chinese_scheme
                                    : draft.scheme,
                                scheme: "japanese",
                              })
                            }
                          />
                          <span>日文</span>
                        </label>
                      </div>
                    </div>
                    {client.touchKeyboardSchemes && (
                      <div
                        className="section"
                        role="group"
                        aria-labelledby="touch-keyboard-schemes-title"
                      >
                        <div className="section-title" id="touch-keyboard-schemes-title">
                          输入方案
                        </div>
                        <div className="input-setting-description">
                          开启的方案会显示在键盘快捷切换中，至少保留一种。点击名称设为当前方案。
                        </div>
                        <div className="input-option-content">
                          {touchKeyboardSchemeOptions.map(([scheme, label], index) => {
                            const enabled = touchKeyboardSchemes.enabled.includes(scheme);
                            const selected = selectedTouchKeyboardScheme === scheme;
                            return (
                              <div className="input-option-item" key={scheme}>
                                {index > 0 && <div className="input-option-divider" />}
                                <div className={skin.schemeRow}>
                                  <button
                                    type="button"
                                    className={skin.schemeSelect(selected)}
                                    aria-label={`设为当前输入方案 ${label}`}
                                    aria-pressed={selected}
                                    disabled={!enabled}
                                    onClick={() =>
                                      setDraft(selectTouchKeyboardScheme(draft, scheme))
                                    }
                                  >
                                    <span>{label}</span>
                                    {selected && <span aria-hidden="true">✓</span>}
                                  </button>
                                  <input
                                    className="toggle"
                                    type="checkbox"
                                    aria-label={`显示输入方案 ${label}`}
                                    checked={enabled}
                                    disabled={enabled && touchKeyboardSchemes.enabled.length === 1}
                                    onChange={(event) =>
                                      setTouchKeyboardSchemeEnabled(scheme, event.target.checked)
                                    }
                                  />
                                </div>
                              </div>
                            );
                          })}
                        </div>
                      </div>
                    )}
                    <div
                      className="section"
                      role="group"
                      aria-labelledby="input-scheme-title"
                      hidden={client.touchKeyboardSchemes || draft.scheme === "japanese"}
                    >
                      <div className="section-title" id="input-scheme-title">
                        输入方案
                      </div>
                      <div className="input-option-content">
                        {(
                          [
                            ["quanpin", "全拼"],
                            ["shuangpin", "双拼"],
                            ["wubi", "五笔"],
                          ] as const
                        ).map(([scheme, label], index) => (
                          <div className="input-option-item" key={scheme}>
                            {index > 0 && <div className="input-option-divider" />}
                            <label className="radio-option">
                              <input
                                type="radio"
                                name="input-scheme"
                                value={scheme}
                                checked={draft.scheme === scheme}
                                onChange={() =>
                                  setDraft({ ...draft, scheme, last_chinese_scheme: scheme })
                                }
                              />
                              <span>{label}</span>
                            </label>
                          </div>
                        ))}
                      </div>
                    </div>
                    <div
                      className="section"
                      hidden={client.touchKeyboardSchemes || draft.scheme === "japanese"}
                    >
                      <label className="section-header">
                        <span className="section-title">双拼方案</span>
                        {/* The source disables this menu unless Shuangpin is the active scheme
                            (`_shuangpinSchemeButton.enabled = storedScheme == 1`): until then the
                            choice changes nothing, and a live control that does nothing reads as a
                            setting being ignored. Other hosts keep it always editable. */}
                        <select
                          disabled={macosPlatform && draft.scheme !== "shuangpin"}
                          value={draft.shuangpin_profile}
                          onChange={(event) =>
                            setDraft({
                              ...draft,
                              shuangpin_profile: event.target
                                .value as Preferences["shuangpin_profile"],
                            })
                          }
                        >
                          <option value="xiaohe">小鹤双拼</option>
                          <option value="ziranma">自然码双拼</option>
                          <option value="shoudao">首道双拼</option>
                          <option value="microsoft">微软双拼</option>
                        </select>
                      </label>
                    </div>
                    {macosPlatform &&
                      client.loadMacosShuangpinKeymap &&
                      macosShuangpinKeymap !== undefined && (
                        <div
                          className="section"
                          hidden={client.touchKeyboardSchemes || draft.scheme !== "shuangpin"}
                        >
                          <label className="section-header">
                            <span className="section-title">
                              输入时显示双拼键位提示
                              <small>双拼输入时显示当前方案的键位图，完成上屏后自动隐藏。</small>
                            </span>
                            <input
                              aria-label="输入时显示双拼键位提示"
                              className="toggle"
                              type="checkbox"
                              checked={macosShuangpinKeymap}
                              onChange={(event) => setMacosShuangpinKeymap(event.target.checked)}
                            />
                          </label>
                        </div>
                      )}
                    <div
                      className="section"
                      hidden={client.touchKeyboardSchemes || draft.scheme === "japanese"}
                    >
                      <label className="section-header">
                        <span className="section-title">五笔方案</span>
                        <select value="wubi86" onChange={() => {}}>
                          <option value="wubi86">86 五笔</option>
                        </select>
                      </label>
                    </div>
                    {((client.touchKeyboardSchemes &&
                      touchKeyboardSchemes.enabled.includes("wubi")) ||
                      draft.scheme === "wubi") && (
                      <div className="section" role="group" aria-label="五笔">
                        <label className="section-header">
                          <span className="section-title">
                            编码打不出时用拼音候选
                            <small>
                              五笔词库无法回答当前编码时，用同一串字母查询全拼；词库能回答时不影响。
                            </small>
                          </span>
                          <input
                            aria-label="编码打不出时用拼音候选"
                            className="toggle"
                            type="checkbox"
                            checked={draft.wubi_mixed_pinyin ?? false}
                            onChange={(event) =>
                              setDraft({ ...draft, wubi_mixed_pinyin: event.target.checked })
                            }
                          />
                        </label>
                        <label className="section-header">
                          <span className="section-title">
                            候选显示剩余编码
                            <small>
                              在候选后面标出还要再打哪几个字母才能单独打出它。已经打完整码的候选不标。
                            </small>
                          </span>
                          <input
                            aria-label="候选显示剩余编码"
                            className="toggle"
                            type="checkbox"
                            checked={draft.wubi_code_hint ?? true}
                            onChange={(event) =>
                              setDraft({ ...draft, wubi_code_hint: event.target.checked })
                            }
                          />
                        </label>
                        {macosPlatform && macosWubiAutoCommitUnique !== undefined && (
                          <label className="section-header">
                            <span className="section-title">
                              五笔四码唯一候选自动上屏
                              <small>五笔输入达到四码且只有一个候选时，自动提交该候选。</small>
                            </span>
                            <input
                              aria-label="五笔四码唯一候选自动上屏"
                              className="toggle"
                              type="checkbox"
                              checked={macosWubiAutoCommitUnique}
                              onChange={(event) =>
                                setMacosWubiAutoCommitUnique(event.target.checked)
                              }
                            />
                          </label>
                        )}
                      </div>
                    )}
                    <div
                      className="section"
                      role="group"
                      aria-labelledby="japanese-scheme-title"
                      hidden={client.touchKeyboardSchemes || draft.scheme !== "japanese"}
                    >
                      <div className="section-title" id="japanese-scheme-title">
                        日语方案
                      </div>
                      <div className="input-option-content">
                        <label className="radio-option">
                          <input type="radio" name="japanese-scheme" checked readOnly />
                          <span>罗马音</span>
                        </label>
                      </div>
                      <div className="input-setting-description japanese-scheme-description">
                        直接输入罗马音，提供平假名、片假名及日语词库候选
                      </div>
                    </div>
                    <div className="section" role="group" aria-labelledby="paging-title">
                      <div className="section-title" id="paging-title">
                        翻页方式
                      </div>
                      <div className="input-option-content">
                        {navigationOptions.map(([key, label], index) => (
                          <div className="input-option-item" key={key}>
                            {index > 0 && <div className="input-option-divider" />}
                            <label className="check-option">
                              <input
                                type="checkbox"
                                checked={(draft.navigation ?? defaultNavigation)[key]}
                                onChange={(event) =>
                                  setDraft({
                                    ...draft,
                                    ...(event.target.checked &&
                                    wordCharacter.enabled &&
                                    wordCharacter.keys === key
                                      ? { word_character: { ...wordCharacter, enabled: false } }
                                      : {}),
                                    navigation: {
                                      ...(draft.navigation ?? defaultNavigation),
                                      [key]: event.target.checked,
                                    },
                                  })
                                }
                              />
                              <span>{label}</span>
                            </label>
                          </div>
                        ))}
                      </div>
                    </div>
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">
                          候选词翻译<small>为当前候选请求翻译结果并显示在候选行</small>
                        </span>
                        <input
                          className="toggle"
                          type="checkbox"
                          checked={candidateTranslations}
                          onChange={(event) =>
                            setDraft({ ...draft, candidate_translations: event.target.checked })
                          }
                        />
                      </label>
                      <div className="input-option-divider" />
                      <label className="section-header">
                        <span className="section-title">目标语言</span>
                        <select
                          aria-label="候选词翻译目标语言"
                          disabled={!candidateGlossLanguagesEnabled}
                          value={translationTargetLanguage}
                          onChange={(event) =>
                            setDraft({
                              ...draft,
                              translation_target_language: event.target
                                .value as Preferences["translation_target_language"],
                            })
                          }
                        >
                          {visibleTranslationLanguages.map(([value, label]) => (
                            <option key={value} value={value}>
                              {label}
                            </option>
                          ))}
                        </select>
                      </label>
                      {(androidPlatform || iosPlatform || macosPlatform) && (
                        <>
                          <div className="input-option-divider" />
                          <label className="section-header">
                            <span className="section-title">
                              第二种语言<small>候选词下方可同时显示第二种释义</small>
                            </span>
                            <select
                              aria-label="候选词翻译第二种语言"
                              disabled={!candidateGlossLanguagesEnabled}
                              value={translationSecondaryLanguage}
                              onChange={(event) =>
                                setDraft({
                                  ...draft,
                                  translation_secondary_language:
                                    event.target.value === ""
                                      ? null
                                      : (event.target
                                          .value as Preferences["translation_target_language"]),
                                })
                              }
                            >
                              {visibleSecondaryLanguages.map(([value, label]) => (
                                <option key={value || "none"} value={value}>
                                  {label}
                                </option>
                              ))}
                            </select>
                          </label>
                        </>
                      )}
                      {androidPlatform && (
                        <p className="input-setting-description">
                          Android 使用已登录的 MSIME
                          在线服务处理候选词翻译；凭据保存在系统安全存储中，不会进入此设置页。
                        </p>
                      )}
                    </div>
                    {!androidPlatform && (
                      <>
                        <div className="section" role="group" aria-label="候选词翻译服务">
                          <label className="section-header">
                            <span className="section-title">翻译服务</span>
                            <select
                              aria-label="候选词翻译服务"
                              disabled={!candidateTranslations}
                              value={translationProvider}
                              onChange={(event) =>
                                setTranslationProvider(
                                  event.target.value as "none" | "custom" | "tencent" | "niutrans",
                                )
                              }
                            >
                              <option value="none">关闭</option>
                              <option value="tencent">腾讯云机器翻译</option>
                              <option value="niutrans">小牛翻译（NiuTrans）</option>
                              <option value="custom">自定义 DeepLX 兼容服务</option>
                            </select>
                          </label>
                        </div>
                        <div className="section" role="group" aria-label="小牛翻译（NiuTrans）">
                          <label className="section-header">
                            <span className="section-title">
                              小牛翻译（NiuTrans）
                              <small>使用 App ID 和 API Key 为候选词提供逐条翻译</small>
                            </span>
                            <input
                              aria-label="小牛翻译（NiuTrans）"
                              className="toggle"
                              type="checkbox"
                              disabled={!candidateTranslations}
                              checked={niutrans.enabled}
                              onChange={(event) =>
                                setTranslationProvider(event.target.checked ? "niutrans" : "none")
                              }
                            />
                          </label>
                          <div className="input-option-divider" />
                          <label className="section-header">
                            <span className="section-title">App ID</span>
                            <input
                              aria-label="NiuTrans App ID"
                              value={niutrans.app_id}
                              disabled={!candidateTranslations || !niutrans.enabled}
                              onChange={(event) =>
                                setDraft({
                                  ...draft,
                                  niutrans: { ...niutrans, app_id: event.target.value },
                                })
                              }
                            />
                          </label>
                          <div className="input-option-divider" />
                          <label className="section-header">
                            <span className="section-title">API Key</span>
                            <SecretInput
                              label="NiuTrans API Key"
                              value={niutrans.apikey}
                              disabled={!candidateTranslations || !niutrans.enabled}
                              onChange={(value) =>
                                setDraft({ ...draft, niutrans: { ...niutrans, apikey: value } })
                              }
                            />
                          </label>
                          {niutrans.enabled &&
                            credentialTestControl(
                              "translation.niutrans",
                              "测试 NiuTrans 配置",
                              { app_id: niutrans.app_id, apikey: niutrans.apikey },
                              !candidateTranslations ||
                                !niutrans.app_id.trim() ||
                                !niutrans.apikey.trim(),
                            )}
                        </div>
                        <div className="section" role="group" aria-label="在线翻译服务">
                          {linuxPlatform ? (
                            <>
                              <div className="section-title">
                                在线翻译服务
                                <small>由用户管理的 Linux provider 服务负责网络请求和凭据</small>
                              </div>
                              <p className="input-setting-description">
                                候选词翻译开启后，provider 从用户配置目录的{" "}
                                <code>tencent-provider.json</code>{" "}
                                读取腾讯云凭据；设置页不保存不会生效的 SecretId 或 SecretKey。
                              </p>
                              {translationProvider === "tencent" &&
                                credentialTestControl(
                                  "translation.tencent",
                                  "测试腾讯云翻译配置",
                                  {},
                                  !candidateTranslations,
                                )}
                            </>
                          ) : (
                            <>
                              <label className="section-header">
                                <span className="section-title">
                                  在线翻译服务
                                  <small>
                                    候选词翻译默认使用腾讯云机器翻译，需要填入你自己的 API 凭据
                                  </small>
                                </span>
                                <input
                                  aria-label="腾讯云机器翻译"
                                  className="toggle"
                                  type="checkbox"
                                  disabled={!candidateTranslations}
                                  checked={tencentTranslation.enabled}
                                  onChange={(event) =>
                                    setDraft({
                                      ...draft,
                                      tencent_tmt: {
                                        ...tencentTranslation,
                                        enabled: event.target.checked,
                                      },
                                    })
                                  }
                                />
                              </label>
                              <div className="input-option-divider" />
                              <label className="section-header">
                                <span className="section-title">SecretId</span>
                                <input
                                  aria-label="腾讯云 SecretId"
                                  type="text"
                                  autoComplete="off"
                                  spellCheck={false}
                                  value={tencentTranslation.secret_id}
                                  disabled={!candidateTranslations || !tencentTranslation.enabled}
                                  onChange={(event) =>
                                    setDraft({
                                      ...draft,
                                      tencent_tmt: {
                                        ...tencentTranslation,
                                        secret_id: event.target.value,
                                      },
                                    })
                                  }
                                  placeholder="AKIDxxxxxxxxxxxxxxxx"
                                />
                              </label>
                              <div className="input-option-divider" />
                              <label className="section-header">
                                <span className="section-title">SecretKey</span>
                                <SecretInput
                                  label="腾讯云 SecretKey"
                                  value={tencentTranslation.secret_key}
                                  disabled={!candidateTranslations || !tencentTranslation.enabled}
                                  onChange={(value) =>
                                    setDraft({
                                      ...draft,
                                      tencent_tmt: { ...tencentTranslation, secret_key: value },
                                    })
                                  }
                                />
                              </label>
                              <div className="input-option-divider" />
                              <label className="section-header">
                                <span className="section-title">地域</span>
                                <input
                                  aria-label="腾讯云地域"
                                  type="text"
                                  autoComplete="off"
                                  spellCheck={false}
                                  value={tencentTranslation.region}
                                  disabled={!candidateTranslations || !tencentTranslation.enabled}
                                  onChange={(event) =>
                                    setDraft({
                                      ...draft,
                                      tencent_tmt: {
                                        ...tencentTranslation,
                                        region: event.target.value,
                                      },
                                    })
                                  }
                                  placeholder="ap-guangzhou"
                                />
                              </label>
                              {(windowsPlatform || macosPlatform) &&
                                tencentTranslation.enabled &&
                                credentialTestControl(
                                  "translation.tencent",
                                  "测试腾讯云翻译配置",
                                  {
                                    secret_id: tencentTranslation.secret_id,
                                    secret_key: tencentTranslation.secret_key,
                                    region: tencentTranslation.region,
                                  },
                                  !candidateTranslations ||
                                    Boolean(
                                      tencentCredentialIssue(
                                        tencentTranslation.secret_id,
                                        tencentTranslation.secret_key,
                                        tencentTranslation.region,
                                      ),
                                    ),
                                )}
                              {candidateTranslations &&
                                tencentTranslation.enabled &&
                                tencentCredentialIssue(
                                  tencentTranslation.secret_id,
                                  tencentTranslation.secret_key,
                                  tencentTranslation.region,
                                ) && (
                                  <p className={settings.settingsWarning} role="status">
                                    {tencentCredentialIssue(
                                      tencentTranslation.secret_id,
                                      tencentTranslation.secret_key,
                                      tencentTranslation.region,
                                    )}
                                  </p>
                                )}
                              {candidateTranslations &&
                                tencentTranslation.enabled &&
                                !tencentCredentialIssue(
                                  tencentTranslation.secret_id,
                                  tencentTranslation.secret_key,
                                  tencentTranslation.region,
                                ) &&
                                !(
                                  tencentSecretConfigured(tencentTranslation.secret_id) &&
                                  tencentSecretConfigured(tencentTranslation.secret_key)
                                ) &&
                                !customTranslation.enabled && (
                                  <p className={settings.settingsWarning} role="status">
                                    未填写腾讯云凭据，候选词翻译不会有任何结果。请填入 SecretId 与
                                    SecretKey，或改用下面的自定义翻译服务。
                                  </p>
                                )}
                            </>
                          )}
                        </div>
                        {client.customTranslations && (
                          <div className="section" role="group" aria-label="自定义候选释义设置">
                            <div className="section-title">
                              自定义候选释义
                              <small>
                                候选窗的中英互译来自内置词库；覆盖不全或译得不准时，可以自己加一层，不改内置词库。每行一条，用
                                Tab 分隔源词和译文；以 #
                                开头的行是注释。源词含汉字即为中译英，全是英文则为英译中。同一个源词写多次时以最后一次为准。保存后重新启动输入法生效。
                              </small>
                            </div>
                            <textarea
                              aria-label="自定义候选释义"
                              rows={8}
                              value={customTranslationsText}
                              placeholder={customTranslationsExample}
                              onChange={(event) => {
                                setCustomTranslationsText(event.target.value);
                                setCustomTranslationsNotice("");
                              }}
                            />
                            <p role="status">
                              {customTranslationsNotice || customTranslationsSummary}
                            </p>
                            <button
                              type="button"
                              className="secondary"
                              disabled={customTranslationsBusy}
                              onClick={() => void saveCustomTranslations()}
                            >
                              {customTranslationsBusy ? "保存中…" : "保存自定义释义"}
                            </button>
                          </div>
                        )}
                        <div className="section" role="group" aria-label="自定义翻译服务">
                          <label className="section-header">
                            <span className="section-title">
                              自定义翻译服务
                              <small>
                                改用自建的兼容 DeepLX 的 HTTPS
                                服务；关闭后候选词翻译使用上面选择的在线服务
                              </small>
                            </span>
                            <input
                              aria-label="自定义翻译服务"
                              className="toggle"
                              type="checkbox"
                              disabled={!candidateTranslations}
                              checked={customTranslation.enabled}
                              onChange={(event) =>
                                setDraft({
                                  ...draft,
                                  custom_translation: {
                                    ...customTranslation,
                                    enabled: event.target.checked,
                                  },
                                })
                              }
                            />
                          </label>
                          <div className="input-option-divider" />
                          <label className="section-header">
                            <span className="section-title">翻译 Endpoint</span>
                            <input
                              aria-label="自定义翻译 Endpoint"
                              type="url"
                              value={customTranslation.endpoint}
                              disabled={!candidateTranslations || !customTranslation.enabled}
                              onChange={(event) =>
                                setDraft({
                                  ...draft,
                                  custom_translation: {
                                    ...customTranslation,
                                    endpoint: event.target.value,
                                  },
                                })
                              }
                              placeholder="https://example.com/translate"
                            />
                          </label>
                          {candidateTranslations &&
                            customTranslation.enabled &&
                            translationEndpointIssue(customTranslation.endpoint) && (
                              <p className={settings.settingsWarning} role="status">
                                {translationEndpointIssue(customTranslation.endpoint)}
                              </p>
                            )}
                          <div className="input-option-divider" />
                          <label className="section-header">
                            <span className="section-title">API Key</span>
                            <SecretInput
                              label="自定义翻译 API Key"
                              value={customTranslation.api_key}
                              disabled={!candidateTranslations || !customTranslation.enabled}
                              onChange={(value) =>
                                setDraft({
                                  ...draft,
                                  custom_translation: { ...customTranslation, api_key: value },
                                })
                              }
                            />
                          </label>
                          {customTranslation.enabled &&
                            credentialTestControl(
                              "translation.custom",
                              "测试自定义翻译配置",
                              {
                                endpoint: customTranslation.endpoint,
                                api_key: customTranslation.api_key,
                              },
                              !candidateTranslations ||
                                Boolean(translationEndpointIssue(customTranslation.endpoint)),
                            )}
                        </div>
                      </>
                    )}
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">
                          以词定字
                          <small>
                            开启后，按所选键组的左键上屏高亮候选的首个汉字，右键上屏末个汉字
                          </small>
                        </span>
                        <input
                          className="toggle"
                          type="checkbox"
                          checked={wordCharacter.enabled}
                          onChange={(event) =>
                            setDraft({
                              ...draft,
                              word_character: { ...wordCharacter, enabled: event.target.checked },
                              ...(event.target.checked
                                ? {
                                    navigation: {
                                      ...(draft.navigation ?? defaultNavigation),
                                      [wordCharacter.keys]: false,
                                    },
                                  }
                                : {}),
                            })
                          }
                        />
                      </label>
                      <div className="word-to-character-keys-row">
                        <div className="section-title" id="word-character-title">
                          以词定字快捷键
                        </div>
                        <div
                          className="input-option-content"
                          role="radiogroup"
                          aria-labelledby="word-character-title"
                        >
                          {(
                            [
                              ["brackets", "[ / ]"],
                              ["minus_equal", "- / ="],
                            ] as const
                          ).map(([keys, label], index) => (
                            <div className="input-option-item" key={keys}>
                              {index > 0 && <div className="input-option-divider" />}
                              <label className="radio-option">
                                <input
                                  type="radio"
                                  name="word-character-keys"
                                  checked={wordCharacter.keys === keys}
                                  disabled={(draft.navigation ?? defaultNavigation)[keys]}
                                  onChange={() =>
                                    setDraft({
                                      ...draft,
                                      word_character: { ...wordCharacter, keys },
                                    })
                                  }
                                />
                                <span>{label}</span>
                              </label>
                            </div>
                          ))}
                        </div>
                      </div>
                    </div>
                    <div className="section" role="group" aria-label="全拼纠错">
                      <div className="section-title">
                        全拼纠错<small>分别控制字母错位和邻键误触的拼音纠错</small>
                      </div>
                      <label className="section-header">
                        <span className="section-title">
                          字母顺序错位<small>例如把 shang 输入为 sahng</small>
                        </span>
                        <input
                          aria-label="全拼纠错：字母顺序错位"
                          className="toggle"
                          type="checkbox"
                          checked={quanpinAutocorrect.autocorrect_transposition}
                          onChange={(event) =>
                            setDraft({
                              ...draft,
                              quanpin: {
                                ...draft.quanpin,
                                ...quanpinAutocorrect,
                                autocorrect_transposition: event.target.checked,
                              },
                            })
                          }
                        />
                      </label>
                      <div className="input-option-divider" />
                      <label className="section-header">
                        <span className="section-title">
                          相邻键误触<small>例如把 shang 输入为 shabg</small>
                        </span>
                        <input
                          aria-label="全拼纠错：相邻键误触"
                          className="toggle"
                          type="checkbox"
                          checked={quanpinAutocorrect.autocorrect_neighbor}
                          onChange={(event) =>
                            setDraft({
                              ...draft,
                              quanpin: {
                                ...draft.quanpin,
                                ...quanpinAutocorrect,
                                autocorrect_neighbor: event.target.checked,
                              },
                            })
                          }
                        />
                      </label>
                    </div>
                    {client.fuzzyPinyin && (
                      <div className="section" role="group" aria-label="模糊音">
                        <label className="section-header">
                          <span className="section-title">
                            模糊音<small>全拼、九键与双拼均支持；更改会在当前输入结束后生效</small>
                          </span>
                          <input
                            aria-label="启用模糊音"
                            className="toggle"
                            type="checkbox"
                            checked={fuzzyPinyin.enabled}
                            onChange={(event) => {
                              const enabled = event.target.checked;
                              const firstEnable = enabled && !fuzzyPinyin.seeded;
                              setDraft({
                                ...draft,
                                fuzzy_pinyin: {
                                  ...fuzzyPinyin,
                                  enabled,
                                  ...(firstEnable
                                    ? { rules: fuzzyPinyinRuleIds, seeded: true }
                                    : {}),
                                },
                              });
                            }}
                          />
                        </label>
                        <p className="input-setting-description">
                          勾选容易混淆的读音后，会补充对应候选。关闭总开关会保留已选规则。
                        </p>
                        {fuzzyPinyinGroups.map(([title, rules]) => (
                          <div key={title} className="fuzzy-pinyin-group">
                            <div className="section-title">{title}</div>
                            <div className="input-option-content">
                              {rules.map(([id, label], index) => (
                                <div className="input-option-item" key={id}>
                                  {index > 0 && <div className="input-option-divider" />}
                                  <label className="check-option">
                                    <input
                                      aria-label={`模糊音规则 ${id}`}
                                      type="checkbox"
                                      disabled={!fuzzyPinyin.enabled}
                                      checked={fuzzyPinyin.rules.includes(id)}
                                      onChange={(event) => {
                                        const selected = new Set(fuzzyPinyin.rules);
                                        if (event.target.checked) selected.add(id);
                                        else selected.delete(id);
                                        setDraft({
                                          ...draft,
                                          fuzzy_pinyin: {
                                            ...fuzzyPinyin,
                                            rules: [...selected].sort(),
                                          },
                                        });
                                      }}
                                    />
                                    <span>{label}</span>
                                  </label>
                                </div>
                              ))}
                            </div>
                          </div>
                        ))}
                        <button
                          type="button"
                          className="secondary fuzzy-pinyin-reset"
                          onClick={() => {
                            void confirm({
                              title: "关闭模糊音",
                              message: "所有模糊音规则会被清空。",
                              confirmLabel: "关闭并清空",
                              danger: true,
                            }).then((confirmed) => {
                              if (!confirmed) return;
                              setDraft({
                                ...draft,
                                fuzzy_pinyin: {
                                  enabled: false,
                                  rules: [],
                                  seeded: fuzzyPinyin.seeded ?? false,
                                },
                              });
                            });
                          }}
                        >
                          重置模糊音配置
                        </button>
                      </div>
                    )}
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">
                          学习选词习惯<small>根据选词调整候选顺序</small>
                        </span>
                        <input
                          className="toggle"
                          type="checkbox"
                          checked={draft.learning}
                          onChange={(event) =>
                            setDraft({ ...draft, learning: event.target.checked })
                          }
                        />
                      </label>
                    </div>
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">
                          中文标点<small>默认使用中文标点符号</small>
                        </span>
                        <input
                          className="toggle"
                          type="checkbox"
                          checked={draft.chinese_punctuation}
                          onChange={(event) =>
                            setDraft({ ...draft, chinese_punctuation: event.target.checked })
                          }
                        />
                      </label>
                    </div>
                    {!mobilePlatform && (
                      <div className="section">
                        <label className="section-header">
                          <span className="section-title">
                            全角输入
                            <small>
                              将英文字符和空格提交为全角形式，可用工具栏或快捷键临时切换
                            </small>
                          </span>
                          <input
                            aria-label="全角输入"
                            className="toggle"
                            type="checkbox"
                            checked={(draft.character_width ?? "halfwidth") === "fullwidth"}
                            onChange={(event) =>
                              setDraft({
                                ...draft,
                                character_width: event.target.checked ? "fullwidth" : "halfwidth",
                              })
                            }
                          />
                        </label>
                      </div>
                    )}
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">
                          智能标点
                          <small>中文标点模式下，字母或数字后的 , . : 自动使用英文标点</small>
                        </span>
                        <input
                          className="toggle"
                          type="checkbox"
                          checked={smartPunctuation}
                          onChange={(event) =>
                            setDraft({ ...draft, smart_punctuation: event.target.checked })
                          }
                        />
                      </label>
                    </div>
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">
                          重复标点转中文
                          <small>
                            智能标点输出英文标点后，2 秒内再次输入同一标点时替换为中文标点
                          </small>
                        </span>
                        <input
                          className="toggle"
                          type="checkbox"
                          checked={smartPunctuationRepeat}
                          onChange={(event) =>
                            setDraft({ ...draft, smart_punctuation_repeat: event.target.checked })
                          }
                        />
                      </label>
                    </div>
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">
                          中文标点后按空格转换
                          <small>刚输入中文标点后按空格，转换为对应英文标点</small>
                        </span>
                        <input
                          className="toggle"
                          type="checkbox"
                          checked={smartPunctuationSpaceConvert}
                          onChange={(event) =>
                            setDraft({
                              ...draft,
                              smart_punctuation_space_convert: event.target.checked,
                            })
                          }
                        />
                      </label>
                    </div>
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">
                          数字后直出<small>数字后输入逗号、句点或冒号时保留 ASCII 标点</small>
                        </span>
                        <input
                          className="toggle"
                          type="checkbox"
                          checked={smartPunctuationDirectDigit}
                          onChange={(event) =>
                            setDraft({
                              ...draft,
                              smart_punctuation_direct_digit: event.target.checked,
                            })
                          }
                        />
                      </label>
                    </div>
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">
                          字母后直出<small>字母后输入逗号、句点或冒号时保留 ASCII 标点</small>
                        </span>
                        <input
                          className="toggle"
                          type="checkbox"
                          checked={smartPunctuationDirectLetter}
                          onChange={(event) =>
                            setDraft({
                              ...draft,
                              smart_punctuation_direct_letter: event.target.checked,
                            })
                          }
                        />
                      </label>
                    </div>
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">
                          成对标点自动补全
                          <small>输入左侧符号时自动补全右侧符号，并将光标置于中间</small>
                        </span>
                        <input
                          className="toggle"
                          type="checkbox"
                          checked={pairedPunctuation}
                          onChange={(event) =>
                            setDraft({ ...draft, paired_punctuation: event.target.checked })
                          }
                        />
                      </label>
                    </div>
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">
                          固定标点<small>切换中英文时的标点形态，三者互斥</small>
                        </span>
                        <select
                          aria-label="固定标点"
                          value={punctuationLock}
                          onChange={(event) =>
                            setDraft({
                              ...draft,
                              punctuation_lock: event.target
                                .value as Preferences["punctuation_lock"],
                            })
                          }
                        >
                          <option value="follow">跟随中英文状态</option>
                          <option value="chinese">始终使用中文标点</option>
                          <option value="english">始终使用英文标点</option>
                        </select>
                      </label>
                    </div>
                    <div className="section" role="group" aria-label="中英混输">
                      <label className="section-header">
                        <span className="section-title">
                          中英混输<small>中文输入时在候选项中补充英文单词</small>
                        </span>
                        <input
                          className="toggle"
                          type="checkbox"
                          checked={mixedInput.english}
                          onChange={(event) =>
                            setDraft({
                              ...draft,
                              mixed_input: { ...mixedInput, english: event.target.checked },
                            })
                          }
                        />
                      </label>
                      <div className="input-option-divider" />
                      <label className="section-header frequency-option-row">
                        <span className="section-title">
                          触发字符数<small>预编辑字母达到该长度后才出现英文候选项</small>
                        </span>
                        <select
                          aria-label="触发字符数"
                          disabled={!mixedInput.english}
                          value={mixedInput.minimum_prefix}
                          onChange={(event) =>
                            setDraft({
                              ...draft,
                              mixed_input: {
                                ...mixedInput,
                                minimum_prefix: Number(event.target.value),
                              },
                            })
                          }
                        >
                          {[1, 2, 3, 4, 5, 6, 7, 8].map((value) => (
                            <option key={value} value={value}>
                              {value}
                            </option>
                          ))}
                        </select>
                      </label>
                    </div>
                    {(
                      [
                        [
                          "emoji",
                          "emoji 混输",
                          "中文输入时在候选项中加入匹配的 emoji（位于英文候选之后；云候选与 AI 联想会使其相应顺移）",
                        ],
                        [
                          "kaomoji",
                          "颜文字混输",
                          "中文输入时在候选项中加入匹配的颜文字（排在 emoji 之后；云候选与 AI 联想会使其相应顺移）",
                        ],
                      ] as const
                    ).map(([key, label, description]) => (
                      <div className="section" key={key}>
                        <label className="section-header">
                          <span className="section-title">
                            {label}
                            <small>{description}</small>
                          </span>
                          <input
                            className="toggle"
                            type="checkbox"
                            checked={mixedInput[key]}
                            onChange={(event) =>
                              setDraft({
                                ...draft,
                                mixed_input: { ...mixedInput, [key]: event.target.checked },
                              })
                            }
                          />
                        </label>
                      </div>
                    ))}
                    {/* macOS keeps this with the chords that trigger it, on the shortcut page. */}
                    {showInputModeHUD && !macosPlatform && (
                      <div className="section">
                        <label className="section-header">
                          <span className="section-title">
                            中英文切换提示
                            <small>
                              切换输入模式后，在光标附近短暂显示“中”或“英”，不会抢占焦点。
                            </small>
                          </span>
                          <input
                            aria-label="中英文切换提示"
                            className="toggle"
                            type="checkbox"
                            checked={inputModeHUD}
                            onChange={(event) =>
                              setDraft({ ...draft, input_mode_hud: event.target.checked })
                            }
                          />
                        </label>
                      </div>
                    )}
                    {client.candidateEnglishGloss && (
                      <div className="section">
                        <label className="section-header">
                          <span className="section-title">
                            显示英文释义
                            <small>
                              在候选词后面标出它的英文意思，中文候选给英文、英文候选给中文。释义来自随键盘打包的离线词库，不联网。
                            </small>
                          </span>
                          <input
                            aria-label="显示英文释义"
                            className="toggle"
                            type="checkbox"
                            checked={candidateEnglishGloss}
                            onChange={(event) =>
                              setDraft({ ...draft, candidate_english_gloss: event.target.checked })
                            }
                          />
                        </label>
                      </div>
                    )}
                    {showEnglishSuggestions && (
                      <div className="section">
                        <label className="section-header">
                          <span className="section-title">
                            英文建议
                            <small>
                              英文 26
                              键直接输入时，在候选栏显示当前单词的补全建议；关闭后仍可正常输入英文。
                            </small>
                          </span>
                          <input
                            aria-label="英文建议"
                            className="toggle"
                            type="checkbox"
                            checked={englishSuggestions}
                            onChange={(event) =>
                              setDraft({ ...draft, english_suggestions: event.target.checked })
                            }
                          />
                        </label>
                      </div>
                    )}
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">
                          默认中英文<small>新焦点会话开始时使用的中文或英文状态</small>
                        </span>
                        <select
                          aria-label="默认中英文"
                          value={draft.default_ime_mode ?? "chinese"}
                          onChange={(event) =>
                            setDraft({
                              ...draft,
                              default_ime_mode: event.target
                                .value as Preferences["default_ime_mode"],
                            })
                          }
                        >
                          <option value="chinese">中文</option>
                          <option value="english">英文</option>
                        </select>
                      </label>
                    </div>
                    {showModeScope && (
                      <div className="section">
                        <label className="section-header">
                          <span className="section-title">
                            中英文状态
                            <small>按应用分别记忆输入状态，或让所有输入上下文保持同一状态</small>
                          </span>
                          <select
                            aria-label="中英文状态"
                            value={draft.ime_mode_scope ?? "app"}
                            onChange={(event) =>
                              setDraft({
                                ...draft,
                                ime_mode_scope: event.target.value as Preferences["ime_mode_scope"],
                              })
                            }
                          >
                            <option value="app">按应用记忆</option>
                            <option value="global">全局统一</option>
                          </select>
                        </label>
                      </div>
                    )}
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">
                          简繁输入<small>将提交的简体中文转换为繁体中文</small>
                        </span>
                        <input
                          aria-label="简繁输入"
                          className="toggle"
                          type="checkbox"
                          checked={draft.traditional_chinese_output ?? false}
                          onChange={(event) =>
                            setDraft({ ...draft, traditional_chinese_output: event.target.checked })
                          }
                        />
                      </label>
                    </div>
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">
                          云候选<small>向在线服务请求额外候选</small>
                        </span>
                        <input
                          className="toggle"
                          type="checkbox"
                          checked={cloudCandidates}
                          onChange={(event) =>
                            setDraft({ ...draft, cloud_candidates: event.target.checked })
                          }
                        />
                      </label>
                    </div>
                    <div className="section" role="group" aria-labelledby="frequency-title">
                      <div className="section-title" id="frequency-title">
                        拼音方案调频
                      </div>
                      <div className="frequency-option-content">
                        <label className="section-header frequency-option-row">
                          <span className="section-title">调频方式</span>
                          <select
                            value={frequency.mode}
                            onChange={(event) =>
                              setDraft({
                                ...draft,
                                frequency: {
                                  ...frequency,
                                  mode: event.target.value as FrequencyPreferences["mode"],
                                },
                              })
                            }
                          >
                            <option value="disabled">关闭</option>
                            <option value="pin">一次置顶</option>
                            <option value="halve">折半调频</option>
                            <option value="linear">线性调频</option>
                            <option value="promote">一次置前</option>
                          </select>
                        </label>
                        {(
                          [
                            ["trigger_count", "触发频次(第几次上屏触发)"],
                            ["linear_step", "线性调频步长"],
                          ] as const
                        ).map(([key, label]) => (
                          <div key={key}>
                            <div className="input-option-divider" />
                            <label className="section-header frequency-option-row">
                              <span className="section-title">{label}</span>
                              <select
                                value={frequency[key]}
                                onChange={(event) =>
                                  setDraft({
                                    ...draft,
                                    frequency: { ...frequency, [key]: Number(event.target.value) },
                                  })
                                }
                              >
                                {[
                                  1,
                                  2,
                                  3,
                                  4,
                                  5,
                                  6,
                                  ...(frequency[key] > 6 ? [frequency[key]] : []),
                                ].map((value) => (
                                  <option key={value} value={value}>
                                    {value}
                                  </option>
                                ))}
                              </select>
                            </label>
                          </div>
                        ))}
                      </div>
                    </div>
                    {mobilePlatform && client.mobileKeyboardFeedback && mobileKeyboardFeedback && (
                      <div className="section" role="group" aria-label="按键反馈">
                        <div className="section-title">按键反馈</div>
                        <label className="section-header">
                          <span className="section-title">
                            按键音<small>按键音受系统静音设置控制</small>
                          </span>
                          <input
                            aria-label="按键音"
                            className="toggle"
                            type="checkbox"
                            disabled={mobileKeyboardFeedbackBusy}
                            checked={mobileKeyboardFeedback.soundEnabled}
                            onChange={(event) =>
                              void saveMobileKeyboardFeedback({
                                ...mobileKeyboardFeedback,
                                soundEnabled: event.target.checked,
                              })
                            }
                          />
                        </label>
                        <div className="input-option-divider" />
                        <label className="section-header">
                          <span className="section-title">
                            按键振动<small>振动效果取决于设备与系统支持</small>
                          </span>
                          <input
                            aria-label="按键振动"
                            className="toggle"
                            type="checkbox"
                            disabled={mobileKeyboardFeedbackBusy}
                            checked={mobileKeyboardFeedback.hapticsEnabled}
                            onChange={(event) =>
                              void saveMobileKeyboardFeedback({
                                ...mobileKeyboardFeedback,
                                hapticsEnabled: event.target.checked,
                              })
                            }
                          />
                        </label>
                        {mobileKeyboardFeedback.hapticsEnabled && (
                          <>
                            <div className="input-option-divider" />
                            <label className="section-header">
                              <span className="section-title">振动强度</span>
                              <select
                                aria-label="振动强度"
                                disabled={mobileKeyboardFeedbackBusy}
                                value={mobileKeyboardFeedback.hapticStrength}
                                onChange={(event) =>
                                  void saveMobileKeyboardFeedback({
                                    ...mobileKeyboardFeedback,
                                    hapticStrength: event.target
                                      .value as MobileKeyboardFeedback["hapticStrength"],
                                  })
                                }
                              >
                                <option value="light">轻</option>
                                <option value="medium">中</option>
                                <option value="strong">强</option>
                              </select>
                            </label>
                            {client.mobileKeyboardFeedback?.preview && (
                              <button
                                type="button"
                                className="secondary"
                                disabled={mobileKeyboardFeedbackBusy}
                                onClick={() => void previewMobileKeyboardHaptics()}
                              >
                                试一下振动
                              </button>
                            )}
                          </>
                        )}
                        {iosPlatform && (
                          <>
                            <div className="input-option-divider" />
                            <label className="section-header">
                              <span className="section-title">
                                英文建议
                                <small>
                                  英文 26
                                  键直接输入时，在候选栏显示当前单词的补全建议；关闭后仍可正常输入英文。
                                </small>
                              </span>
                              <input
                                aria-label="英文建议"
                                className="toggle"
                                type="checkbox"
                                disabled={mobileKeyboardFeedbackBusy}
                                checked={mobileKeyboardFeedback.englishSuggestions !== false}
                                onChange={(event) =>
                                  void saveMobileKeyboardFeedback({
                                    ...mobileKeyboardFeedback,
                                    englishSuggestions: event.target.checked,
                                  })
                                }
                              />
                            </label>
                          </>
                        )}
                      </div>
                    )}
                  </fieldset>
                  <fieldset disabled={busy} hidden={page !== "helpcode"} aria-label="辅助码">
                    {showHelpcodeShiftEntry && (
                      <div className="section input-setting-description">
                        <p>
                          全拼或双拼组字时，按 Shift
                          再输入的字母作为辅助码交给输入引擎，用于缩小候选。五笔、日语和本地输入模式不使用辅助码。
                        </p>
                      </div>
                    )}
                    {(
                      [
                        ["shuangpin_helpcode", "双拼"],
                        ["quanpin_helpcode", "全拼"],
                      ] as const
                    ).map(([key, label]) => {
                      const value = {
                        ...defaultHelpcode[key],
                        ...draft[key],
                      } as Required<HelpcodePreferences>;
                      return (
                        <div className="section" key={key}>
                          <label className="section-header">
                            <span className="section-title">{label}辅助码</span>
                            <input
                              className="toggle"
                              type="checkbox"
                              checked={value.enabled}
                              onChange={(event) =>
                                setDraft({
                                  ...draft,
                                  [key]: { ...value, enabled: event.target.checked },
                                })
                              }
                            />
                          </label>
                          <label className="section-header helpcode-schema">
                            <span className="section-title">{label}辅助码方案</span>
                            <select
                              disabled={!value.enabled}
                              value={value.schema}
                              onChange={(event) =>
                                setDraft({
                                  ...draft,
                                  [key]: { ...value, schema: event.target.value as HelpcodeSchema },
                                })
                              }
                            >
                              {helpcodeSchemas.map(([schema, name]) => (
                                <option key={schema} value={schema}>
                                  {name}
                                </option>
                              ))}
                            </select>
                          </label>
                          <label className="section-header">
                            {/*
                             * Named after its own scheme, the way the reference window names these:
                             * both rows are on the page at once, so one shared wording left two
                             * checkboxes with the same accessible name and nothing to tell a screen
                             * reader -- or a test -- which one it had.
                             */}
                            <span className="section-title">
                              {mobilePlatform
                                ? `在候选栏中显示${label}辅助码`
                                : `在候选窗口中显示${label}辅助码`}
                            </span>
                            <input
                              aria-label={
                                mobilePlatform
                                  ? `在候选栏中显示${label}辅助码`
                                  : `在候选窗口中显示${label}辅助码`
                              }
                              className="toggle"
                              type="checkbox"
                              checked={value.show_in_candidate_window}
                              onChange={(event) =>
                                setDraft({
                                  ...draft,
                                  [key]: {
                                    ...value,
                                    show_in_candidate_window: event.target.checked,
                                  },
                                })
                              }
                            />
                          </label>
                        </div>
                      );
                    })}
                  </fieldset>
                  <fieldset disabled={busy} hidden={page !== "shortcuts"} aria-label="快捷键">
                    <div className={`section ${settings.shortcutIntro}`}>
                      输入法快捷键仅在对应输入状态或候选窗口显示时生效。翻页方式可在“输入”中启用或关闭。
                    </div>
                    {showModeSwitchShortcuts && (
                      <div className="section" role="group" aria-label="输入模式切换快捷键">
                        <div className="section-title">输入模式切换</div>
                        <small>
                          在当前输入上下文中切换中英文模式；关闭后快捷键会交给应用处理。
                        </small>
                        {modeSwitchShortcutRows.map(([key, label]) => (
                          <label className="section-header" key={key}>
                            <span className="section-title">{label}</span>
                            <input
                              aria-label={label}
                              className="toggle"
                              type="checkbox"
                              checked={keybindings[key]}
                              onChange={(event) =>
                                setDraft({
                                  ...draft,
                                  keybindings: { ...keybindings, [key]: event.target.checked },
                                })
                              }
                            />
                          </label>
                        ))}
                        {macosPlatform && showInputModeHUD && (
                          <label className="section-header">
                            <span className="section-title">
                              切换中英文时显示提示
                              <small>切换后在光标下方短暂显示「中」或「英」。</small>
                            </span>
                            <input
                              aria-label="切换中英文时显示提示"
                              className="toggle"
                              type="checkbox"
                              checked={inputModeHUD}
                              onChange={(event) =>
                                setDraft({ ...draft, input_mode_hud: event.target.checked })
                              }
                            />
                          </label>
                        )}
                        {macosPlatform && (
                          <label className="section-header">
                            <span className="section-title">
                              Option+Shift+H 切换全半角
                              <small>
                                关掉后这个组合键交给应用处理；工具栏的全半角开关不受影响。
                              </small>
                            </span>
                            <input
                              aria-label="Option+Shift+H 切换全半角"
                              className="toggle"
                              type="checkbox"
                              checked={keybindings.toggle_fullwidth_option_shift_h}
                              onChange={(event) =>
                                setDraft({
                                  ...draft,
                                  keybindings: {
                                    ...keybindings,
                                    toggle_fullwidth_option_shift_h: event.target.checked,
                                  },
                                })
                              }
                            />
                          </label>
                        )}
                        {windowsPlatform && (
                          <div className={settings.shortcutIntro}>
                            <div className="section-title">修改或关闭 Ctrl+Space（系统）</div>
                            <small>
                              Ctrl+Space 由 Windows 管理，此处不控制。请前往系统设置修改“输入法 /
                              非输入法切换”的按键顺序：
                            </small>
                            <ol>
                              <li>打开“设置”，进入“时间和语言” → “输入”。</li>
                              <li>选择“高级键盘设置” → “输入语言热键”。</li>
                              <li>
                                选中“中文（简体）输入法 - 输入法 /
                                非输入法切换”，点击“更改按键顺序”。
                              </li>
                              <li>关闭该按键顺序，或将 Ctrl+Space 改为其他不常用组合。</li>
                            </ol>
                            <small>
                              不同 Windows
                              版本的选项名称可能略有差异；修改后如未立即生效，请重新登录或重启电脑。
                            </small>
                          </div>
                        )}
                      </div>
                    )}
                    {showPanelShortcuts && (
                      <div className="section" role="group" aria-label="面板快捷键">
                        <div className="section-title">面板快捷键</div>
                        <small>
                          {macosPlatform
                            ? "可从当前输入上下文使用 Command 组合键打开面板。"
                            : harmonyPlatform
                              ? "连接实体键盘后，在输入状态下可用 Super 组合键打开面板。"
                              : "桌面环境转发 Super 组合键时可从当前输入上下文打开面板。"}
                        </small>
                        <div className={settings.shortcutList}>
                          <div className={settings.shortcutRow}>
                            <span>打开屏幕键盘</span>
                            <kbd>Ctrl+Shift+{macosPlatform ? "Command" : "Super"}+K</kbd>
                          </div>
                        </div>
                      </div>
                    )}
                    <div className={`section ${settings.shortcutSectionTitle}`}>
                      <div className="section-title">候选操作</div>
                      <small>输入和选取候选词时使用</small>
                      {showNumberRowSelection && (
                        <label className="section-header">
                          <span className="section-title">
                            数字键选词<small>关闭后，候选窗口显示时数字键仍交给当前应用。</small>
                          </span>
                          <input
                            aria-label="数字键选词"
                            className="toggle"
                            type="checkbox"
                            checked={draft.number_row_selection ?? true}
                            onChange={(event) =>
                              setDraft({ ...draft, number_row_selection: event.target.checked })
                            }
                          />
                        </label>
                      )}
                      <div className={settings.shortcutList}>
                        <div className={settings.shortcutRow}>
                          <span>选择候选</span>
                          <kbd>Space{(draft.number_row_selection ?? true) ? " 或 1–9" : ""}</kbd>
                        </div>
                        {(draft.navigation ?? defaultNavigation).minus_equal && (
                          <div className={settings.shortcutRow}>
                            <span>向前 / 向后翻页</span>
                            <kbd>- / =</kbd>
                          </div>
                        )}
                        {(draft.navigation ?? defaultNavigation).comma_period && (
                          <div className={settings.shortcutRow}>
                            <span>向前 / 向后翻页</span>
                            <kbd>, / .</kbd>
                          </div>
                        )}
                        {(draft.navigation ?? defaultNavigation).tab && (
                          <div className={settings.shortcutRow}>
                            <span>向前 / 向后翻页</span>
                            <kbd>Shift+Tab / Tab</kbd>
                          </div>
                        )}
                        {(draft.navigation ?? defaultNavigation).page_up_down && (
                          <div className={settings.shortcutRow}>
                            <span>向前 / 向后翻页</span>
                            <kbd>Page Up / Page Down</kbd>
                          </div>
                        )}
                        {(draft.navigation ?? defaultNavigation).mouse_wheel && (
                          <div className={settings.shortcutRow}>
                            <span>候选窗口翻页</span>
                            <kbd>鼠标滚轮</kbd>
                          </div>
                        )}
                        {(draft.navigation ?? defaultNavigation).arrows && (
                          <div className={settings.shortcutRow}>
                            <span>移动候选项</span>
                            <kbd>↑ / ↓</kbd>
                          </div>
                        )}
                        <div className={settings.shortcutRow}>
                          <span>移动到当前候选页首 / 尾</span>
                          <kbd>Home / End</kbd>
                        </div>
                        <div className={settings.shortcutRow}>
                          <span>编辑输入串</span>
                          <kbd>← / → / Backspace</kbd>
                        </div>
                        <div className={settings.shortcutRow}>
                          <span>提交原始输入 / 取消输入</span>
                          <kbd>Enter / Esc</kbd>
                        </div>
                      </div>
                    </div>
                    {showDesktopMaintenanceShortcuts && (
                      <div className={`section ${settings.shortcutSectionTitle}`}>
                        <div className="section-title">
                          {macosPlatform ? "输入上下文维护快捷键" : "全局维护快捷键"}
                        </div>
                        <small>
                          {macosPlatform
                            ? "仅在水杉输入法当前输入上下文生效；Option 对应 Windows 基线中的 Alt。"
                            : linuxPlatform
                              ? "当前 IBus 会话中的候选维护与服务重启"
                              : "程序运行时全局生效；用于维护与调试"}
                        </small>
                        <div className={settings.shortcutList}>
                          <div className={settings.shortcutRow}>
                            <span>删除当前候选窗口中的第 1–8 项</span>
                            <kbd>{maintenanceChord}+1–8</kbd>
                          </div>
                          {linuxPlatform && (
                            <>
                              <div className={settings.shortcutRow}>
                                <span>清除当前输入法会话的 Engine 缓存</span>
                                <kbd>Ctrl+Shift+Alt+C</kbd>
                              </div>
                              <div className={settings.shortcutRow}>
                                <span>重启输入法服务</span>
                                <kbd>Ctrl+Shift+Alt+R</kbd>
                              </div>
                            </>
                          )}
                          {!linuxPlatform && (
                            <>
                              <div className={settings.shortcutRow}>
                                <span>
                                  {macosPlatform
                                    ? "清除当前输入法会话的 Engine 缓存"
                                    : "清除输入法引擎缓存"}
                                </span>
                                <kbd>{maintenanceChord}+C</kbd>
                              </div>
                              <div className={settings.shortcutRow}>
                                <span>
                                  {macosPlatform ? "重新注册并重启当前输入法" : "重启输入法服务"}
                                </span>
                                <kbd>{maintenanceChord}+R</kbd>
                              </div>
                              <div
                                className={`${settings.shortcutRow} ${settings.shortcutRowDanger}`}
                              >
                                <span>
                                  {macosPlatform ? "立即退出当前输入法进程" : "立即退出输入法服务"}
                                </span>
                                <kbd>{maintenanceChord}+T</kbd>
                              </div>
                            </>
                          )}
                        </div>
                      </div>
                    )}
                    {showRestartInputMethod && (
                      <div className={`section ${settings.shortcutSectionTitle}`}>
                        <div className="section-title">输入法服务</div>
                        <small>
                          {macosPlatform
                            ? "重新注册并启用已安装的水杉输入源；当前输入法进程继续按系统生命周期运行。"
                            : linuxPlatform
                              ? "IBus 配置支持热重载；需要重新启动输入法服务时可使用此按钮。"
                              : "请求受监督的输入法服务重新启动。"}
                        </small>
                        <div className={settings.serviceRow}>
                          <span>{macosPlatform ? "重新注册当前输入源" : "立即重启输入法服务"}</span>
                          <HostActionButton
                            action={client.restartInputMethod}
                            label={macosPlatform ? "重新注册" : "重启"}
                            success={macosPlatform ? "已重新注册输入源。" : "已发送重启请求。"}
                            error={
                              macosPlatform
                                ? "重新注册输入源失败，请确认输入法已经安装。"
                                : "重启输入法服务失败，请稍后重试。"
                            }
                          />
                        </div>
                        {showInstallInputSource && (
                          <div className={settings.serviceRow}>
                            <span>
                              安装或更新水杉输入源
                              <small>
                                将当前应用随附的 IMK bundle 安装到本机输入法目录，然后注册到系统。
                              </small>
                            </span>
                            <HostActionButton
                              action={client.installInputSource}
                              label="安装 / 更新"
                              success="输入源已安装并注册。"
                              error="输入源安装或注册失败，请重试。"
                            />
                          </div>
                        )}
                      </div>
                    )}
                  </fieldset>
                  <fieldset disabled={busy} hidden={page !== "tools"} aria-label="实用功能">
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">
                          剪贴板管理
                          <small>
                            {iosPlatform
                              ? "由键盘的“允许完全访问”权限控制；记录仅保存在本机。"
                              : "开启后记录复制的文本；保存关闭设置后清空已保存记录，且只记录文本类型。"}
                          </small>
                        </span>
                        {!iosPlatform && (
                          <input
                            aria-label="剪贴板管理"
                            className="toggle"
                            type="checkbox"
                            checked={clipboardHistory}
                            onChange={(event) => toggleClipboardHistory(event.target.checked)}
                          />
                        )}
                      </label>
                      <div className={settings.clipboardToolbar}>
                        {!iosPlatform && client.clipboard?.sync && (
                          <button
                            type="button"
                            className="secondary"
                            disabled={!clipboardHistory || !snapshot?.preferences.clipboard_history}
                            onClick={() =>
                              void client.clipboard!.sync!()
                                .then((entries) => {
                                  setClipboardEntries(entries);
                                  setClipboardClearArmed(false);
                                })
                                .catch(() => setError("无法同步剪贴板历史"))
                            }
                          >
                            从系统剪贴板同步
                          </button>
                        )}
                        {client.clipboard?.clear && clipboardEntries.length > 0 && (
                          <button
                            type="button"
                            className="secondary"
                            disabled={!clipboardHistory}
                            onClick={() => {
                              if (!clipboardClearArmed) {
                                setClipboardClearArmed(true);
                                return;
                              }
                              void mutateClipboardHistory(
                                () => client.clipboard!.clear(),
                                "无法清空剪贴板历史，请稍后重试。",
                              );
                            }}
                          >
                            {clipboardClearArmed ? "确认清空" : "清空历史"}
                          </button>
                        )}
                      </div>
                      {clipboardHistory && client.clipboard?.list && (
                        <div className={settings.clipboardList} aria-label="剪贴板历史">
                          {clipboardEntries.length === 0 ? (
                            <small>暂无历史记录</small>
                          ) : (
                            clipboardEntries.map((entry) => (
                              <div
                                className={settings.clipboardRow}
                                data-clipboard-entry-row=""
                                key={entry.text}
                              >
                                <span className={settings.clipboardEntry}>
                                  <span title={entry.text}>{entry.text}</span>
                                  <small>
                                    {entry.pinned ? "已固定 · " : ""}
                                    {entry.timestampMs > 1_000_000_000_000
                                      ? new Date(entry.timestampMs).toLocaleString()
                                      : "旧记录"}
                                  </small>
                                </span>
                                <span className={settings.clipboardActions}>
                                  {client.clipboard?.copy && (
                                    <button
                                      type="button"
                                      className="secondary"
                                      onClick={() => void client.clipboard!.copy!(entry.text)}
                                    >
                                      重新复制
                                    </button>
                                  )}
                                  {client.clipboard?.setPinned && (
                                    <button
                                      type="button"
                                      className="secondary"
                                      aria-label={`${entry.pinned ? "取消固定" : "固定"}剪贴板记录`}
                                      onClick={() =>
                                        void mutateClipboardHistory(
                                          () =>
                                            client.clipboard!.setPinned!(entry.text, !entry.pinned),
                                          "无法更新剪贴板固定状态",
                                        )
                                      }
                                    >
                                      {entry.pinned ? "取消固定" : "固定"}
                                    </button>
                                  )}
                                  {client.clipboard?.remove && (
                                    <button
                                      type="button"
                                      className="secondary"
                                      aria-label="删除剪贴板记录"
                                      onClick={() =>
                                        void mutateClipboardHistory(
                                          () => client.clipboard!.remove!(entry.text),
                                          "无法删除剪贴板记录",
                                        )
                                      }
                                    >
                                      删除
                                    </button>
                                  )}
                                </span>
                              </div>
                            ))
                          )}
                        </div>
                      )}
                      {macosPlatform ? (
                        <p className={settings.panelPreviewLabel}>
                          云剪贴板和云词典需要当前输入法进程提供输入会话；请从输入法悬浮工具栏或输入法菜单打开对应面板。
                        </p>
                      ) : (
                        <>
                          {client.openCloudClipboard && (
                            <button
                              type="button"
                              className="secondary"
                              onClick={() => void openPanel(client.openCloudClipboard)}
                            >
                              打开云剪贴板
                            </button>
                          )}
                          {client.openCloudDictionary && (
                            <button
                              type="button"
                              className="secondary"
                              onClick={() => void openPanel(client.openCloudDictionary)}
                            >
                              打开云词典
                            </button>
                          )}
                        </>
                      )}
                    </div>
                    {visibleLocalModeRows.map(([key, label, description]) => (
                      <div className="section" key={key}>
                        <label className="section-header">
                          <span className="section-title">
                            {label}
                            <small>{description}</small>
                          </span>
                          <input
                            className="toggle"
                            type="checkbox"
                            checked={localModes[key]}
                            onChange={(event) =>
                              setDraft({
                                ...draft,
                                local_modes: { ...localModes, [key]: event.target.checked },
                              })
                            }
                          />
                        </label>
                      </div>
                    ))}
                  </fieldset>
                  <fieldset disabled={busy} hidden={page !== "help"} aria-label="帮助">
                    {macosPlatform &&
                      macosHelpCards.map((card) => (
                        <div
                          key={card.title}
                          className={`section ${doc.guide}`}
                          role="group"
                          aria-label={card.title}
                        >
                          <div className="section-title">{card.title}</div>
                          {card.rows.map((row, index) => (
                            <div
                              key={row.term}
                              className={`${doc.guideRow}${index === 0 && card.rows.length > 1 ? ` ${doc.guideLead}` : ""}`}
                            >
                              <span className={doc.guideTerm}>{row.term}</span>
                              <p className={doc.guideText}>{row.text}</p>
                            </div>
                          ))}
                        </div>
                      ))}
                    {macosPlatform && client.openExternalUrl && (
                      <div className="section" role="group" aria-label="更多">
                        <div className="section-header">
                          <span className="section-title">
                            更多<small>更完整的说明、词库来源和更新记录在官网上。</small>
                          </span>
                          <button
                            type="button"
                            className="secondary"
                            onClick={() => void openExternalUrl(documentationUrl)}
                          >
                            打开官网
                          </button>
                        </div>
                      </div>
                    )}
                    {!macosPlatform && (
                      <div className={`section ${doc.page}`}>
                        <p>{platformHelpIntro}</p>
                        <div className={doc.subsection}>
                          <div className="section-title">快速上手</div>
                          <p>{platformQuickStart}</p>
                          {mobilePlatform && client.openSystemKeyboardSettings && (
                            <button
                              type="button"
                              className="secondary"
                              onClick={() => void client.openSystemKeyboardSettings!()}
                            >
                              {iosPlatform ? "打开系统键盘设置" : "打开系统输入法设置"}
                            </button>
                          )}
                        </div>
                        {iosPlatform && (
                          <div className={doc.subsection}>
                            <div className="section-title">允许完全访问</div>
                            <p>
                              打字统计保存本机字数、手写首次下载识别模型时需要在系统键盘设置中开启“允许完全访问”。不开启也可以正常打字；键盘默认离线，不会因为未开启而上传输入内容。
                            </p>
                          </div>
                        )}
                        {androidPlatform && (
                          <div className={doc.subsection}>
                            <div className="section-title">输入权限</div>
                            <p>
                              Android
                              的输入法服务只在当前编辑器请求时接收文本。云功能、语音和社区按你主动启用的功能联网，日常拼音输入无需联网。
                            </p>
                          </div>
                        )}
                        <div className={doc.subsection}>
                          <div className="section-title">基本功能</div>
                          <p>
                            支持全拼、双拼和五笔。可以在设置窗口下的输入功能分区进行切换。全拼和双拼均支持辅助码，辅助码方案目前支持自然码辅助码、蓝天小雨点、首右
                            2.0、首右 plus 和小鹤。
                          </p>
                          <p>{platformNetworkDescription}</p>
                          <p>更多功能欢迎自由探索～</p>
                        </div>
                        {client.openExternalUrl && (
                          <div className={doc.subsection}>
                            <div className="section-title">更多</div>
                            <button
                              type="button"
                              className="secondary"
                              onClick={() => void openExternalUrl(documentationUrl)}
                            >
                              完整文档（网页）
                            </button>
                          </div>
                        )}
                      </div>
                    )}
                  </fieldset>
                  <fieldset disabled={busy} hidden={page !== "about"} aria-label="关于">
                    <div className={`section ${doc.hero}`}>
                      <div className={doc.mark}>
                        <img src={logo} alt="水杉 IME" />
                      </div>
                      <div>
                        <div className={doc.eyebrow}>Metasequoia IME</div>
                        <div className={doc.heroTitle}>水杉 IME</div>
                        <p>{platformAboutDescription}</p>
                      </div>
                    </div>
                    <div className={`section ${doc.linkList}`}>
                      <div className={`${doc.linkRow} ${doc.versionRow}`}>
                        <div>
                          <div className={doc.linkTitle}>当前版本</div>
                          <div className={doc.version}>v{currentAppVersion}</div>
                          {updateStatus && (
                            <p className={doc.updateStatus} role="status">
                              {updateStatus}
                            </p>
                          )}
                        </div>
                        <button
                          type="button"
                          className={`secondary ${doc.updateButton}`}
                          disabled={updateBusy}
                          onClick={() => void checkForUpdate()}
                        >
                          {updateBusy ? "正在检查…" : "检查更新"}
                        </button>
                      </div>
                      {availableUpdate && (
                        <div className={doc.updateResult}>
                          <p>水杉 IME v{availableUpdate.version.display} 已发布。</p>
                          {installerTrust?.warning && (
                            <p className={doc.updateWarning}>{installerTrust.warning}</p>
                          )}
                          {installerTrust?.verify && (
                            <p>
                              下载后请核对 SHA256：<code>{installerTrust.verify.sha256}</code>
                            </p>
                          )}
                          <button
                            type="button"
                            className="secondary"
                            onClick={() => void openExternalUrl(availableUpdate.releaseUrl)}
                          >
                            前往下载
                          </button>
                        </div>
                      )}
                      <button
                        type="button"
                        className={doc.linkRow}
                        onClick={() => void openExternalUrl(platformLicenseUrl)}
                      >
                        <span className={doc.linkTitle}>开源许可协议</span>
                        <span aria-hidden="true">↗</span>
                      </button>
                      <button
                        type="button"
                        className={doc.linkRow}
                        onClick={() =>
                          void openExternalUrl(
                            clientHostedPlatform ? androidPrivacyUrl : privacyUrl,
                          )
                        }
                      >
                        <span className={doc.linkTitle}>隐私政策</span>
                        <span aria-hidden="true">↗</span>
                      </button>
                    </div>
                    {macosPlatform && client.dataDirectory && (
                      <div className="section" role="group" aria-label="数据目录">
                        <div className="section-header">
                          <span className="section-title">
                            数据目录
                            <small>
                              词库、学习记录、皮肤、剪贴板历史和设置共用此位置。可移动到其他磁盘。
                            </small>
                          </span>
                        </div>
                        <div className={settings.serviceRow}>
                          <span>
                            当前目录
                            <small>
                              <code>{dataDirectory?.path ?? "正在读取…"}</code>
                              {dataDirectory?.isDefault ? "（默认）" : ""}
                            </small>
                          </span>
                          <div>
                            <button
                              type="button"
                              className="secondary"
                              disabled={dataDirectoryBusy || !dataDirectory}
                              aria-busy={dataDirectoryBusy}
                              onClick={() => void chooseDataDirectory()}
                            >
                              {dataDirectoryBusy ? "正在移动…" : "选择位置…"}
                            </button>
                          </div>
                        </div>
                        {dataDirectoryResult && <p role="status">{dataDirectoryResult}</p>}
                      </div>
                    )}
                    {macosPlatform && (
                      <div className="section" role="group" aria-label="许可与卸载">
                        <div className="section-header">
                          <span className="section-title">
                            许可与版权
                            <small>水杉 IME 以 GPL-3.0 发布；第三方组件许可随应用资源提供。</small>
                          </span>
                          <span className={doc.version} aria-label="版权">
                            © 2026 Metasequoia IME
                          </span>
                        </div>
                        {client.openThirdPartyLicenses && (
                          <button
                            type="button"
                            className="secondary"
                            onClick={() => void client.openThirdPartyLicenses!()}
                          >
                            查看许可全文
                          </button>
                        )}
                        {client.uninstallInputSource && (
                          <div className={`${settings.serviceRow} ${settings.serviceRowDanger}`}>
                            <span>
                              卸载水杉输入法
                              <small>
                                输入源会移到废纸篓；默认保留词库、学习记录和偏好，重新安装后可继续使用。
                              </small>
                              <label>
                                <input
                                  type="checkbox"
                                  checked={removeUserDataOnUninstall}
                                  onChange={(event) =>
                                    setRemoveUserDataOnUninstall(event.target.checked)
                                  }
                                />{" "}
                                同时删除词库、偏好与语音密钥
                              </label>
                            </span>
                            <div>
                              <button
                                type="button"
                                className="secondary"
                                disabled={uninstallBusy}
                                aria-label="卸载…"
                                aria-busy={uninstallBusy}
                                onClick={() => {
                                  setUninstallResult(null);
                                  setUninstallConfirmation(true);
                                }}
                              >
                                {uninstallBusy ? "处理中…" : "卸载…"}
                              </button>
                              {uninstallResult === "success" && (
                                <span role="status">输入法已移到废纸篓。</span>
                              )}
                              {uninstallResult === "error" && (
                                <span role="alert">卸载未能完成，请稍后重试。</span>
                              )}
                            </div>
                            {uninstallConfirmation && (
                              <div
                                className={settings.serviceConfirmation}
                                role="alertdialog"
                                aria-modal="true"
                                aria-label="确认卸载水杉输入法"
                              >
                                <p>
                                  输入法会被移到废纸篓，放错了可以从那里放回原处。
                                  {removeUserDataOnUninstall
                                    ? "已选择同时删除词库、偏好与语音密钥。"
                                    : "词库、学习记录和偏好会保留，重新安装后可以继续使用。"}{" "}
                                  卸载后请重新登录系统，让它从输入源列表中消失。
                                </p>
                                <div>
                                  <button
                                    type="button"
                                    className="danger"
                                    disabled={uninstallBusy}
                                    onClick={() => void uninstallInputSource()}
                                  >
                                    确认卸载
                                  </button>
                                  <button
                                    type="button"
                                    className="secondary"
                                    disabled={uninstallBusy}
                                    onClick={() => setUninstallConfirmation(false)}
                                  >
                                    取消
                                  </button>
                                </div>
                              </div>
                            )}
                          </div>
                        )}
                      </div>
                    )}
                    {mobilePlatform && (
                      <div className={`section ${doc.linkList}`} aria-label="帮助与反馈">
                        <button
                          type="button"
                          className={doc.linkRow}
                          onClick={() => selectPage("help")}
                        >
                          <span className={doc.linkTitle}>使用帮助</span>
                          <span aria-hidden="true">›</span>
                        </button>
                        <button
                          type="button"
                          className={doc.linkRow}
                          onClick={() => selectPage("feedback")}
                        >
                          <span className={doc.linkTitle}>反馈问题与建议</span>
                          <span aria-hidden="true">›</span>
                        </button>
                      </div>
                    )}
                    {(!client.host || linuxPlatform || windowsPlatform || macosPlatform) && (
                      <div className="section" role="group" aria-label="诊断日志">
                        <label className="section-header">
                          <span className="section-title">
                            {linuxPlatform
                              ? "IBus 宿主日志"
                              : macosPlatform
                                ? "输入法日志"
                                : "Server 端日志"}
                            <small>
                              {linuxPlatform
                                ? "排查 IBus 宿主通信、焦点会话、菜单和输入延迟时开启。日志限量轮转，只记录状态和操作阶段，不记录按键、输入内容或候选文本。"
                                : macosPlatform
                                  ? "排查焦点切换和设置加载失败时开启。记录焦点进出与偏好加载、应用、保存的结果，限量轮转，不记录按键、输入内容或候选文本。文件是应用支持目录下的 diagnostic.log，复现后可直接发送。"
                                  : "排查 Server 通信和输入延迟时开启。记录慢请求阶段、候选窗、悬浮工具栏、菜单、焦点会话和通信状态，不记录按键、输入内容或候选文本。"}
                            </small>
                          </span>
                          <input
                            aria-label={
                              linuxPlatform
                                ? "IBus 宿主日志"
                                : macosPlatform
                                  ? "输入法日志"
                                  : "Server 端日志"
                            }
                            className="toggle"
                            type="checkbox"
                            checked={diagnosticLog.server}
                            onChange={(event) =>
                              setDraft({
                                ...draft,
                                diagnostic_log: { ...diagnosticLog, server: event.target.checked },
                              })
                            }
                          />
                        </label>
                        {(!client.host || windowsPlatform) && (
                          <>
                            <div className="input-option-divider" />
                            <label className="section-header">
                              <span className="section-title">
                                TSF 端日志
                                <small>
                                  排查应用内预编辑和输入延迟时开启。日志在内存中限量缓冲，并通过独立管道批量汇总，不记录按键、输入内容或候选文本。
                                </small>
                              </span>
                              <input
                                aria-label="TSF 端日志"
                                className="toggle"
                                type="checkbox"
                                checked={diagnosticLog.tsf}
                                onChange={(event) =>
                                  setDraft({
                                    ...draft,
                                    diagnostic_log: { ...diagnosticLog, tsf: event.target.checked },
                                  })
                                }
                              />
                            </label>
                          </>
                        )}
                      </div>
                    )}
                  </fieldset>
                  <fieldset
                    disabled={busy}
                    hidden={page !== "screen-keyboard"}
                    aria-label="屏幕键盘"
                  >
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">
                          屏幕键盘主题<small>覆盖主题模式；桌面屏幕键盘支持此设置</small>
                        </span>
                        <select
                          aria-label="屏幕键盘主题"
                          value={draft.screen_keyboard_theme ?? "follow"}
                          onChange={(event) =>
                            setDraft({
                              ...draft,
                              screen_keyboard_theme: event.target.value as SurfaceTheme,
                            })
                          }
                        >
                          <option value="follow">跟随全局</option>
                          <option value="dark">深色</option>
                          <option value="light">浅色</option>
                        </select>
                      </label>
                    </div>
                    <div
                      className="section"
                      role="group"
                      aria-labelledby="touch-keyboard-skin-title"
                    >
                      <div className="section-title" id="touch-keyboard-skin-title">
                        键盘皮肤<small>与 Apple 内置皮肤一致；独立于桌面候选窗皮肤</small>
                      </div>
                      <div className={skin.skinGrid}>
                        {touchKeyboardSkinOptions.map((option) => (
                          <article
                            className={skin.skinCard(touchKeyboardSkin === option.id)}
                            key={option.id}
                          >
                            <button
                              type="button"
                              className={skin.skinCardButton}
                              role="switch"
                              aria-label={`屏幕键盘皮肤 ${option.title}`}
                              aria-checked={touchKeyboardSkin === option.id}
                              onClick={() => setDraft({ ...draft, touch_keyboard_skin: option.id })}
                            >
                              <ScreenKeyboardPreview
                                theme={keyboardPreviewTheme}
                                skin={option.id}
                                compact
                              />
                              <span className={skin.skinCardCopy}>
                                <strong>{option.title}</strong>
                                <small>{option.description}</small>
                              </span>
                              <span className={skin.skinCardCheck} aria-hidden="true">
                                {touchKeyboardSkin === option.id ? "✓" : ""}
                              </span>
                            </button>
                          </article>
                        ))}
                        {client.customTouchKeyboardSkins && (
                          <article className={skin.skinCard(touchKeyboardSkin === "custom")}>
                            <button
                              type="button"
                              className={skin.skinCardButton}
                              role="switch"
                              aria-label="屏幕键盘皮肤 我的皮肤"
                              aria-checked={touchKeyboardSkin === "custom"}
                              onClick={() => setDraft({ ...draft, touch_keyboard_skin: "custom" })}
                            >
                              <ScreenKeyboardPreview
                                theme={keyboardPreviewTheme}
                                skin="custom"
                                customDesign={customTouchKeyboardSkin}
                                compact
                              />
                              <span className={skin.skinCardCopy}>
                                <strong>我的皮肤</strong>
                                <small>自由配色 · 自定义键帽</small>
                              </span>
                              <span className={skin.skinCardCheck} aria-hidden="true">
                                {touchKeyboardSkin === "custom" ? "✓" : ""}
                              </span>
                            </button>
                          </article>
                        )}
                      </div>
                      {client.customTouchKeyboardSkins && (
                        <button
                          type="button"
                          className={`secondary ${skin.editorOpen}`}
                          aria-expanded={showTouchSkinEditor}
                          onClick={() => setShowTouchSkinEditor((value) => !value)}
                        >
                          {showTouchSkinEditor ? "收起自定义编辑器" : "设计我的皮肤"}
                        </button>
                      )}
                    </div>
                    {mobilePlatform && client.communitySkins && (
                      <div className="section">
                        <div className="section-header">
                          <span className="section-title">
                            社区皮肤<small>看看别人做的键盘皮肤，可以直接试用或保存</small>
                          </span>
                          <button
                            type="button"
                            className="secondary"
                            onClick={() => openCommunity("all")}
                          >
                            去社区发现皮肤
                          </button>
                        </div>
                      </div>
                    )}
                    {client.customTouchKeyboardSkins && showTouchSkinEditor && (
                      <div className="section">
                        <TouchKeyboardSkinEditor
                          design={customTouchKeyboardSkin}
                          selected={touchKeyboardSkin === "custom"}
                          theme={keyboardPreviewTheme}
                          disabled={busy}
                          library={client.customSkinLibrary}
                          aiSkins={client.aiSkins}
                          communitySkins={client.communitySkins}
                          onChange={(design) =>
                            setDraft((current) =>
                              current
                                ? { ...current, custom_touch_keyboard_skin: design }
                                : current,
                            )
                          }
                          onUse={() =>
                            setDraft((current) =>
                              current ? { ...current, touch_keyboard_skin: "custom" } : current,
                            )
                          }
                          onClose={() => setShowTouchSkinEditor(false)}
                        />
                      </div>
                    )}
                    <div
                      className="section"
                      role="group"
                      aria-labelledby="touch-keyboard-geometry-title"
                    >
                      <div className="section-title" id="touch-keyboard-geometry-title">
                        触屏键盘尺寸
                        <small>
                          与 Apple 键盘一致，只改变触屏键位外观，不改变输入方案或 Engine
                          组合状态；也可以直接在下方预览上左右拖动调节键距、上下拖动调节行距。
                        </small>
                      </div>
                      <label className="section-header">
                        <span className="section-title">
                          键盘高度{" "}
                          <small>
                            {touchKeyboardHeightAdjustment > 0 ? "+" : ""}
                            {touchKeyboardHeightAdjustment} dp
                          </small>
                        </span>
                        <input
                          aria-label="键盘高度"
                          type="range"
                          min="-12"
                          max="48"
                          step="1"
                          value={touchKeyboardHeightAdjustment}
                          onChange={(event) =>
                            setDraft({
                              ...draft,
                              touch_keyboard_height_adjustment: Number(event.target.value),
                            })
                          }
                        />
                      </label>
                      <div className="input-option-divider" />
                      <label className="section-header">
                        <span className="section-title">
                          按键间距 <small>{(touchKeySpacingTenths / 10).toFixed(1)} dp</small>
                        </span>
                        <input
                          aria-label="按键间距"
                          type="range"
                          min="30"
                          max="60"
                          step="1"
                          value={touchKeySpacingTenths}
                          onChange={(event) =>
                            setDraft({
                              ...draft,
                              touch_key_spacing_tenths: Number(event.target.value),
                            })
                          }
                        />
                      </label>
                      <div className="input-option-divider" />
                      <label className="section-header">
                        <span className="section-title">
                          行间距 <small>{(touchRowSpacingTenths / 10).toFixed(1)} dp</small>
                        </span>
                        <input
                          aria-label="行间距"
                          type="range"
                          min="40"
                          max="100"
                          step="1"
                          value={touchRowSpacingTenths}
                          onChange={(event) =>
                            setDraft({
                              ...draft,
                              touch_row_spacing_tenths: Number(event.target.value),
                            })
                          }
                        />
                      </label>
                      <div className="input-option-divider" />
                      <label className="section-header">
                        <span className="section-title">
                          顶部语音入口 <small>在触屏键盘工具栏直接打开最近一次语音结果</small>
                        </span>
                        <input
                          aria-label="顶部语音入口"
                          className="toggle"
                          type="checkbox"
                          checked={draft.touch_voice_shortcut ?? false}
                          onChange={(event) =>
                            setDraft({ ...draft, touch_voice_shortcut: event.target.checked })
                          }
                        />
                      </label>
                      <button
                        type="button"
                        className="danger-text"
                        aria-label="恢复屏幕键盘默认设置"
                        onClick={() => void resetTouchKeyboardSettings()}
                      >
                        恢复默认
                      </button>
                    </div>
                    <div className={`section ${settings.launchCard}`}>
                      <div className={`section-header ${settings.launchRow}`}>
                        <span className="section-title">
                          打开屏幕键盘<small>使用鼠标或触控方式输入文字与快捷按键</small>
                        </span>
                        <button
                          type="button"
                          className={`secondary ${settings.openButton}`}
                          disabled={!client.openScreenKeyboard}
                          onClick={() => void openPanel(client.openScreenKeyboard)}
                        >
                          打开
                        </button>
                      </div>
                      <div className={settings.panelPreview} aria-label="屏幕键盘预览">
                        <div className={settings.panelPreviewLabel}>预览</div>
                        <div
                          aria-label="拖动预览调整键盘间距"
                          onPointerDown={beginTouchGeometryDrag}
                          onPointerMove={updateTouchGeometryDrag}
                          onPointerUp={endTouchGeometryDrag}
                          onPointerCancel={endTouchGeometryDrag}
                          style={{ touchAction: "none" }}
                        >
                          <ScreenKeyboardPreview
                            theme={keyboardPreviewTheme}
                            skin={touchKeyboardSkin}
                            customDesign={customTouchKeyboardSkin}
                            keySpacingTenths={touchKeySpacingTenths}
                            rowSpacingTenths={touchRowSpacingTenths}
                            heightAdjustment={touchKeyboardHeightAdjustment}
                          />
                        </div>
                      </div>
                    </div>
                  </fieldset>
                  <fieldset disabled={busy} hidden={page !== "handwriting"} aria-label="手写识别板">
                    {iosPlatform ? (
                      <div className={`section ${settings.launchCard}`}>
                        <div className="section-title">iOS 键盘手写</div>
                        <p className={settings.panelPreviewLabel}>
                          请在 iOS
                          系统键盘设置中启用水杉键盘，并在键盘内切换到“手写”输入方案。首次使用会按需下载中文识别模型；需要开启“允许完全访问”才能下载模型，下载后可离线识别。
                        </p>
                        <p className={settings.panelPreviewLabel}>
                          手写由键盘扩展在当前输入框内完成，不打开独立的 Tauri
                          手写面板；笔迹和识别结果不会上传，Google ML Kit 仅可能发送性能及使用统计。
                        </p>
                        {client.openSystemKeyboardSettings && (
                          <button
                            type="button"
                            className="secondary"
                            onClick={() => void client.openSystemKeyboardSettings!()}
                          >
                            打开系统键盘设置
                          </button>
                        )}
                      </div>
                    ) : androidPlatform ? (
                      <div className={`section ${settings.launchCard}`}>
                        <div className="section-title">Android 键盘手写</div>
                        <p className={settings.panelPreviewLabel}>
                          请在 Android
                          系统输入法设置中启用水杉键盘，再从键盘方案切换到“手写”。首次使用时按需下载
                          Google ML Kit 中文手写模型；模型就绪后可离线识别。
                        </p>
                        <p className={settings.panelPreviewLabel}>
                          手写识别在 Android
                          键盘进程内完成，候选确认后才提交到当前编辑器；笔迹和识别结果不会上传，Google
                          ML Kit 仅可能发送性能及使用统计。
                        </p>
                        {client.openSystemKeyboardSettings && (
                          <button
                            type="button"
                            className="secondary"
                            onClick={() => void client.openSystemKeyboardSettings!()}
                          >
                            打开系统输入法设置
                          </button>
                        )}
                      </div>
                    ) : harmonyPlatform ? (
                      <div className={`section ${settings.launchCard}`}>
                        <div className="section-title">HarmonyOS 键盘手写</div>
                        <p className={settings.panelPreviewLabel}>
                          请在系统输入法设置中启用水杉输入法，再从键盘的方案选择器切换到“手写”。2in1
                          上候选窗不绘制键面，先从工具栏打开屏幕键盘，方案选择器在那里。
                        </p>
                        <p className={settings.panelPreviewLabel}>
                          识别由系统的 Core Vision Kit
                          在设备上完成，候选确认后才提交到当前编辑器；笔迹和识别结果不离开设备。
                        </p>
                        {client.openSystemKeyboardSettings && (
                          <button
                            type="button"
                            className="secondary"
                            onClick={() => void client.openSystemKeyboardSettings!()}
                          >
                            打开系统输入法设置
                          </button>
                        )}
                      </div>
                    ) : macosPlatform ? (
                      <div className={`section ${settings.launchCard}`}>
                        <div className="section-title">macOS 手写识别板</div>
                        <p className={settings.panelPreviewLabel}>
                          手写面板需要当前输入法进程提供 IMK
                          输入会话；请从输入法悬浮工具栏或输入法菜单打开，识别候选会直接回到当前输入上下文。
                        </p>
                      </div>
                    ) : (
                      <div className={`section ${settings.launchCard}`}>
                        <div className={`section-header ${settings.launchRow}`}>
                          <span className="section-title">
                            打开手写识别板
                            <small>使用鼠标或触控方式手写输入，自动识别候选汉字</small>
                          </span>
                          <button
                            type="button"
                            className={`secondary ${settings.openButton}`}
                            disabled={!client.openHandwriting}
                            onClick={() => void openPanel(client.openHandwriting)}
                          >
                            打开
                          </button>
                        </div>
                        <div className={settings.panelPreview} aria-label="手写识别板预览">
                          <div className={settings.panelPreviewLabel}>预览</div>
                          <div className={surface.mock}>
                            <div className={surface.mockCanvas}>
                              <span className={surface.mockStroke}>水</span>
                            </div>
                            <div className={surface.mockCandidates}>
                              <span>水</span>
                              <span>永</span>
                              <span>木</span>
                              <span>未</span>
                            </div>
                          </div>
                        </div>
                      </div>
                    )}
                  </fieldset>
                  <fieldset disabled={busy} hidden={page !== "voice"} aria-label="语音输入">
                    {localVoice ? (
                      <div className={`section ${settings.launchCard}`}>
                        <div className="section-title">本地 Whisper</div>
                        <p className={settings.panelPreviewLabel}>
                          录音和识别都在这台机器上完成，音频不会离开本机，也不需要任何 API
                          Key。需要自备 whisper.cpp 的 ggml
                          模型文件（.bin），在下方填写它的绝对路径；模型越大越准也越慢，首次识别要等模型载入。可选的文本润色仍会调用你配置的云服务。
                        </p>
                      </div>
                    ) : systemVoice ? (
                      <div className={`section ${settings.launchCard}`}>
                        <div className="section-title">
                          {harmonyPlatform ? "HarmonyOS" : "macOS"} 系统语音
                        </div>
                        <p className={settings.panelPreviewLabel}>
                          保存设置后，在目标应用中启用水杉输入法，使用键盘内的语音入口录音。不需要识别
                          API
                          Key；首次使用需授予麦克风和语音识别权限。服务可用性及是否联网由系统决定，可选文本润色仍使用你配置的云服务。
                        </p>
                      </div>
                    ) : androidPlatform ? (
                      <div className={`section ${settings.launchCard}`}>
                        <div className="section-title">Android 系统语音</div>
                        <p className={settings.panelPreviewLabel}>
                          从键盘工具栏的“语音”入口调用设备上的系统语音识别服务。识别结果会回到键盘，确认后才插入当前输入框。
                        </p>
                      </div>
                    ) : iosPlatform ? (
                      <div className={`section ${settings.launchCard}`}>
                        <div className="section-title">iOS 应用语音</div>
                        <p className={settings.panelPreviewLabel}>
                          iOS
                          的录音、识别和文本提交在当前共享设置与应用语音服务中完成。保存设置后，从应用内的语音入口开始；识别结果会回到当前页面，再由你确认使用。不打开无法提交到键盘扩展输入会话的
                          Tauri 语音面板。
                        </p>
                        {client.openVoice && (
                          <button
                            type="button"
                            className="secondary"
                            onClick={() => void openPanel(client.openVoice)}
                          >
                            开始 iOS 语音
                          </button>
                        )}
                      </div>
                    ) : macosPlatform ? (
                      <div className={`section ${settings.launchCard}`}>
                        <div className="section-title">macOS 输入法语音</div>
                        <p className={settings.panelPreviewLabel}>
                          macOS
                          的语音录音、云端识别和文本提交由当前输入法进程负责；保存设置后，请在目标应用中使用下方语音快捷键或输入法悬浮工具栏开始。不打开无法提交到当前输入法会话的
                          Tauri 面板。
                        </p>
                      </div>
                    ) : harmonyPlatform ? (
                      <div className={`section ${settings.launchCard}`}>
                        <div className="section-title">HarmonyOS 输入法语音</div>
                        <p className={settings.panelPreviewLabel}>
                          豆包配置有效时，键盘直接采集 16 kHz
                          麦克风音频并进行实时识别；选择系统识别时由 HarmonyOS CoreSpeechKit
                          处理。识别结果会回到键盘，确认后才插入当前输入框。
                        </p>
                      </div>
                    ) : (
                      <div className={`section ${settings.launchCard}`}>
                        <div className={`section-header ${settings.launchRow}`}>
                          <span className="section-title">
                            打开语音输入
                            <small>
                              {linuxPlatform
                                ? "录音和识别由已配置的 provider 服务完成"
                                : "录音和识别在本机完成"}
                            </small>
                          </span>
                          <button
                            type="button"
                            className={`secondary ${settings.openButton}`}
                            disabled={!client.openVoice}
                            onClick={() => void openPanel(client.openVoice)}
                          >
                            打开
                          </button>
                        </div>
                        {linuxPlatform && (
                          <p className={settings.panelPreviewLabel}>
                            没有 provider 时可继续使用 IBus 属性中的入口；服务负责录音、模型和凭据。
                          </p>
                        )}
                      </div>
                    )}
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">
                          语音输入<small>使用语音识别将录音转换为文字</small>
                        </span>
                        <input
                          aria-label="启用语音输入"
                          className="toggle"
                          type="checkbox"
                          checked={voiceInput.enabled}
                          onChange={(event) => updateVoice({ enabled: event.target.checked })}
                        />
                      </label>
                    </div>
                    {!androidPlatform && (
                      <div className="section">
                        <label className="section-header">
                          <span className="section-title">识别服务</span>
                          <select
                            aria-label="识别服务"
                            value={String(voiceInput.asr_provider)}
                            onChange={(event) =>
                              updateVoice({
                                ...asrProviderUpdate(event.target.value, voiceInput),
                                ...(event.target.value === "system" &&
                                voiceInput.language === "auto"
                                  ? { language: "zh-CN" }
                                  : {}),
                                ...(linuxPlatform
                                  ? { asr_resource_id: "", doubao_boosting_table_id: "" }
                                  : {}),
                              })
                            }
                          >
                            <option value="doubao">豆包</option>
                            <option value="siliconflow">SiliconFlow</option>
                            <option value="openai">OpenAI</option>
                            <option value="groq">Groq</option>
                            <option value="everyapi">EveryAPI</option>
                            <option value="mistral">Mistral · Voxtral</option>
                            {macosPlatform && <option value="system">macOS 系统识别</option>}
                            {macosPlatform && <option value="local">本地 Whisper（离线）</option>}
                            {!macosPlatform && voiceInput.asr_provider === "local" && (
                              <option value="local" disabled>
                                本地 Whisper（当前平台不可用）
                              </option>
                            )}
                            {harmonyPlatform && <option value="system">HarmonyOS 系统识别</option>}
                            {!nativeVoicePlatform && voiceInput.asr_provider === "system" && (
                              <option value="system" disabled>
                                系统识别（当前平台不可用）
                              </option>
                            )}
                            {harmonyUnsupportedAsr && (
                              <option value={String(voiceInput.asr_provider)} disabled>
                                {String(voiceInput.asr_provider)}（当前 HarmonyOS 版本不可用）
                              </option>
                            )}
                          </select>
                        </label>
                      </div>
                    )}
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">
                          识别语言
                          {systemVoice && (
                            <small>选择明确的语言代码，例如 zh-CN、en-US；可用语言由系统决定</small>
                          )}
                        </span>
                        <input
                          aria-label="识别语言"
                          maxLength={64}
                          list="settings-voice-language-options"
                          value={voiceInput.language}
                          onChange={(event) => updateVoice({ language: event.target.value })}
                        />
                        <datalist id="settings-voice-language-options">
                          <option value={systemVoice ? "zh-CN" : "zh-cn"}>中文（普通话）</option>
                          <option value={systemVoice ? "en-US" : "en"}>English</option>
                          <option value={systemVoice ? "ja-JP" : "ja"}>日本語</option>
                          {!systemVoice && <option value="auto">自动识别</option>}
                        </datalist>
                      </label>
                    </div>
                    {localVoice && (
                      <div className="section">
                        <label className="section-header">
                          <span className="section-title">
                            Whisper 模型文件
                            <small>
                              ggml 模型的绝对路径，例如 /Users/you/models/ggml-large-v3-turbo.bin
                            </small>
                          </span>
                          <span className="flex items-center gap-2 [&>input]:min-w-0 [&>input]:flex-1">
                            <input
                              aria-label="Whisper 模型文件"
                              value={voiceInput.asr_model_path ?? ""}
                              placeholder="/path/to/ggml-model.bin"
                              onChange={(event) =>
                                updateVoice({ asr_model_path: event.target.value })
                              }
                            />
                            {client.pickVoiceModelPath && (
                              <button
                                type="button"
                                className="secondary"
                                onClick={() => {
                                  void (async () => {
                                    // Cancelling resolves to null and must leave the field as it was,
                                    // rather than clearing a path that already worked.
                                    const chosen = await client.pickVoiceModelPath?.();
                                    if (chosen) updateVoice({ asr_model_path: chosen });
                                  })();
                                }}
                              >
                                选择…
                              </button>
                            )}
                          </span>
                        </label>
                      </div>
                    )}
                    {!androidPlatform &&
                      serviceVoice &&
                      providerPresetControls(
                        "识别服务",
                        ASR_PROVIDER_DEFAULTS[String(voiceInput.asr_provider)],
                        voiceInput.asr_model ?? "",
                        (asr_model) => updateVoice({ asr_model }),
                      )}
                    {!androidPlatform && serviceVoice && (
                      <div className="section">
                        <label className="section-header">
                          <span className="section-title">
                            识别模型<small>由 provider 服务选择对应模型</small>
                          </span>
                          <input
                            aria-label="识别模型"
                            value={voiceInput.asr_model ?? ""}
                            onChange={(event) => updateVoice({ asr_model: event.target.value })}
                          />
                        </label>
                      </div>
                    )}
                    {!androidPlatform && voiceInput.asr_provider === "doubao" && (
                      <div className="section">
                        <label className="section-header">
                          <span className="section-title">
                            豆包鉴权方式
                            <small>
                              {linuxPlatform
                                ? "provider 服务必须与此模式匹配"
                                : "新版控制台使用单 API Key；旧版使用 App ID + Access Token"}
                            </small>
                          </span>
                          <select
                            aria-label="豆包鉴权方式"
                            value={doubaoAuthMode}
                            onChange={(event) =>
                              updateVoice({
                                doubao_auth_mode:
                                  event.target.value === "legacy" ? "legacy" : "api_key",
                              })
                            }
                          >
                            <option value="api_key">新版 API Key</option>
                            <option value="legacy">旧版 App ID + Access Token</option>
                          </select>
                        </label>
                      </div>
                    )}
                    {!androidPlatform && !linuxPlatform && serviceVoice && (
                      <>
                        {voiceInput.asr_provider === "doubao" && (
                          <div className="section">
                            <label className="section-header">
                              <span className="section-title">
                                流式接口
                                <small>
                                  整句流式边录边传、说完返回整句，服务方称准确率更高并推荐用于输入法；双向流式返回增量结果，流式预编辑刷新更频繁。选择后写入下方接口地址。
                                </small>
                              </span>
                              <select
                                aria-label="流式接口"
                                value={
                                  DOUBAO_STREAM_ENDPOINTS.find(
                                    (option) => option.endpoint === (voiceInput.asr_endpoint ?? ""),
                                  )?.id ?? "custom"
                                }
                                onChange={(event) => {
                                  const chosen = DOUBAO_STREAM_ENDPOINTS.find(
                                    (option) => option.id === event.target.value,
                                  );
                                  if (chosen) updateVoice({ asr_endpoint: chosen.endpoint });
                                }}
                              >
                                {DOUBAO_STREAM_ENDPOINTS.map((option) => (
                                  <option key={option.id} value={option.id}>
                                    {option.title}
                                  </option>
                                ))}
                                {/* Whatever is in the field now, when it is neither
                                    preset. Selecting it does nothing: the address
                                    below stays the place to type one. */}
                                <option value="custom">自定义地址</option>
                              </select>
                            </label>
                          </div>
                        )}
                        <div className="section">
                          <label className="section-header">
                            <span className="section-title">
                              识别接口地址<small>留空使用当前 provider 默认地址</small>
                            </span>
                            <input
                              aria-label="识别接口地址"
                              type="url"
                              value={voiceInput.asr_endpoint ?? ""}
                              onChange={(event) =>
                                updateVoice({ asr_endpoint: event.target.value })
                              }
                            />
                          </label>
                        </div>
                        {voiceInput.asr_provider === "doubao" && doubaoAuthMode === "legacy" && (
                          <div className="section">
                            <label className="section-header">
                              <span className="section-title">
                                Doubao App Key<small>旧版控制台鉴权使用</small>
                              </span>
                              <SecretInput
                                label="Doubao App Key"
                                value={voiceInput.asr_app_key ?? ""}
                                onChange={(value) => updateVoice({ asr_app_key: value })}
                              />
                            </label>
                          </div>
                        )}
                        <div className="section">
                          <label className="section-header">
                            <span className="section-title">
                              {voiceInput.asr_provider === "doubao" && doubaoAuthMode !== "legacy"
                                ? "Doubao API Key"
                                : "识别 API Token"}
                              <small>仅保存在本机设置中</small>
                            </span>
                            <SecretInput
                              label={
                                voiceInput.asr_provider === "doubao" && doubaoAuthMode !== "legacy"
                                  ? "Doubao API Key"
                                  : "识别 API Token"
                              }
                              value={voiceInput.asr_token ?? ""}
                              onChange={(value) => updateVoice({ asr_token: value })}
                            />
                          </label>
                        </div>
                      </>
                    )}
                    {!androidPlatform && serviceVoice && (
                      <div className="section">
                        <label className="section-header">
                          <span className="section-title">
                            Doubao 资源 ID<small>仅由 Doubao provider 使用</small>
                          </span>
                          <input
                            aria-label="Doubao 资源 ID"
                            value={voiceInput.asr_resource_id ?? ""}
                            onChange={(event) =>
                              updateVoice({ asr_resource_id: event.target.value })
                            }
                          />
                        </label>
                      </div>
                    )}
                    {linuxPlatform &&
                      credentialTestControl("voice.asr", "测试语音识别配置", {
                        asr_provider: voiceInput.asr_provider ?? "doubao",
                        asr_model: voiceInput.asr_model ?? "",
                        asr_resource_id: voiceInput.asr_resource_id ?? "",
                        doubao_auth_mode: doubaoAuthMode,
                        doubao_enable_itn: voiceInput.doubao_enable_itn !== false,
                        doubao_enable_punc: voiceInput.doubao_enable_punc !== false,
                        doubao_enable_ddc: voiceInput.doubao_enable_ddc === true,
                      })}
                    {/*
                     * Doubao belongs in this list, not in a HarmonyOS-only arm: the probe is the
                     * shared one, and Windows and macOS have had it since it was added. Gating it
                     * on HarmonyOS alone silently dropped the button on the two hosts whose tests
                     * cover it.
                     */}
                    {(windowsPlatform || macosPlatform || harmonyPlatform) &&
                      ["openai", "siliconflow", "groq", "doubao"].includes(
                        voiceInput.asr_provider ?? "",
                      ) && (
                        <>
                          <p className={settings.panelPreviewLabel}>
                            测试会向当前服务发送一秒合成静音，不使用麦克风；服务可能计入 API 用量。
                          </p>
                          {credentialTestControl(
                            "voice.asr",
                            voiceInput.asr_provider === "doubao"
                              ? "测试豆包识别配置"
                              : "测试语音识别配置",
                            {
                              provider: voiceInput.asr_provider,
                              endpoint:
                                voiceInput.asr_endpoint?.trim() ||
                                ASR_PROVIDER_DEFAULTS[voiceInput.asr_provider ?? ""]?.endpoint ||
                                "",
                              model:
                                voiceInput.asr_model?.trim() ||
                                ASR_PROVIDER_DEFAULTS[voiceInput.asr_provider ?? ""]?.model ||
                                "",
                              token: voiceInput.asr_token ?? "",
                              ...(voiceInput.asr_provider === "doubao"
                                ? {
                                    auth_mode: doubaoAuthMode,
                                    app_id:
                                      doubaoAuthMode === "legacy"
                                        ? (voiceInput.asr_app_key ?? "")
                                        : "",
                                    resource_id:
                                      voiceInput.asr_resource_id ?? "volc.seedasr.sauc.duration",
                                    doubao_enable_itn: voiceInput.doubao_enable_itn !== false,
                                    doubao_enable_punc: voiceInput.doubao_enable_punc !== false,
                                    doubao_enable_ddc: voiceInput.doubao_enable_ddc === true,
                                    doubao_boosting_table_id:
                                      voiceInput.doubao_boosting_table_id ?? "",
                                  }
                                : {}),
                            },
                            !voiceInput.asr_token?.trim() ||
                              (voiceInput.asr_provider === "doubao" &&
                                doubaoAuthMode === "legacy" &&
                                !voiceInput.asr_app_key?.trim()),
                          )}
                        </>
                      )}
                    {!androidPlatform && (
                      <div className="section">
                        <label className="section-header">
                          <span className="section-title">
                            流式预编辑<small>provider 支持时显示实时识别片段</small>
                          </span>
                          <input
                            aria-label="流式预编辑"
                            className="toggle"
                            type="checkbox"
                            checked={voiceInput.stream_inline_preedit === true}
                            onChange={(event) =>
                              updateVoice({ stream_inline_preedit: event.target.checked })
                            }
                          />
                        </label>
                      </div>
                    )}
                    {showVoiceCommitMode && (
                      <div className="section">
                        <label className="section-header">
                          <span className="section-title">
                            结果提交策略
                            <small>
                              {macosPlatform
                                ? "系统按键和 Command-V 粘贴需要系统事件权限；不可用时回退到输入法会话，粘贴会替换剪贴板内容"
                                : "由当前桌面宿主决定如何把识别结果交给前台窗口"}
                            </small>
                          </span>
                          <select
                            aria-label="结果提交策略"
                            value={voiceInput.commit_mode ?? "tsf"}
                            onChange={(event) =>
                              updateVoice({
                                commit_mode: event.target
                                  .value as VoiceInputPreferences["commit_mode"],
                              })
                            }
                          >
                            <option value="tsf">输入法会话</option>
                            <option value="sendinput">系统按键</option>
                            <option value="ctrl_v">剪贴板粘贴</option>
                          </select>
                        </label>
                      </div>
                    )}
                    {showVoiceCaptureDevices && (
                      <div className="section">
                        <div className="section-title">
                          录音设备<small>保存后从下一次录音生效，不打断当前录音</small>
                        </div>
                        <label className="section-header">
                          <span className="section-title">录音后端</span>
                          <select
                            aria-label="录音后端"
                            value={voiceInput.capture_backend ?? ""}
                            onChange={(event) =>
                              updateVoice({
                                capture_backend: event.target
                                  .value as VoiceInputPreferences["capture_backend"],
                                capture_device: "",
                              })
                            }
                          >
                            <option value="">
                              {windowsPlatform ? "系统默认" : "沿用服务设置"}
                            </option>
                            {captureBackendOptions.map(([value, label]) => (
                              <option key={value} value={value}>
                                {label}
                              </option>
                            ))}
                            {voiceInput.capture_backend &&
                              !captureBackendOptions.some(
                                ([value]) => value === voiceInput.capture_backend,
                              ) && (
                                <option value={voiceInput.capture_backend} disabled>
                                  {voiceInput.capture_backend}（此平台不可用）
                                </option>
                              )}
                          </select>
                        </label>
                        {client.listVoiceCaptureDevices && (
                          <VoiceDevicePicker
                            read={client.listVoiceCaptureDevices}
                            backend={voiceInput.capture_backend ?? ""}
                            device={voiceInput.capture_device ?? ""}
                            choose={(capture_backend, capture_device) =>
                              updateVoice({ capture_backend, capture_device })
                            }
                          />
                        )}
                        <label className="section-header">
                          <span className="section-title">
                            麦克风设备
                            <small>
                              {windowsPlatform
                                ? "刷新列表并选择麦克风，保存其端点标识而非设备序号。留空使用系统默认设备；已选设备不可用时录音失败，不切换到其他麦克风。旧的数字序号需重新选择。"
                                : harmonyPlatform
                                  ? "刷新列表并选择麦克风，保存的是设备类型与地址，重启后仍然有效。留空使用系统默认设备；已选设备拔掉后回到系统默认，不会中断录音。系统语音识别由服务自行取音，不受此项影响。"
                                  : "填写 PulseAudio source、PipeWire 节点名称或序号、ALSA PCM 名称。选择后端后留空使用系统默认设备；沿用服务设置时留空使用服务设备。"}
                            </small>
                          </span>
                          <input
                            aria-label="麦克风设备"
                            maxLength={windowsPlatform ? 1024 : 128}
                            value={voiceInput.capture_device ?? ""}
                            onChange={(event) =>
                              updateVoice({ capture_device: event.target.value })
                            }
                          />
                        </label>
                      </div>
                    )}
                    {!androidPlatform && (
                      <div className="section">
                        <div className="section-title">
                          {linuxPlatform ? "Linux provider 行为" : "录音行为"}
                          <small>
                            {linuxPlatform
                              ? "这些选项会随请求传给用户管理的语音服务，不包含凭据"
                              : "录音期间的提示音与静音由输入法在本机处理"}
                          </small>
                        </div>
                        {(
                          [
                            ["sound_enabled", "语音提示音", true],
                            ["start_sound", "开始录音提示音", true],
                            ["end_sound", "结束录音提示音", true],
                            ["mute_system_audio", "录音时静音其他声音", false],
                          ] as const
                        ).map(([key, label, enabledByDefault]) => (
                          <label className="section-header" key={key}>
                            <span className="section-title">{label}</span>
                            <input
                              aria-label={label}
                              className="toggle"
                              type="checkbox"
                              checked={
                                enabledByDefault
                                  ? voiceInput[key] !== false
                                  : voiceInput[key] === true
                              }
                              onChange={(event) => updateVoice({ [key]: event.target.checked })}
                            />
                          </label>
                        ))}
                      </div>
                    )}
                    {!androidPlatform && voiceInput.asr_provider === "doubao" && (
                      <div className="section">
                        <div className="section-title">
                          豆包识别选项
                          <small>
                            {linuxPlatform ? "由 provider 服务应用" : "随识别请求发送给豆包"}
                          </small>
                        </div>
                        {(
                          [
                            ["doubao_enable_itn", "数字格式化", true],
                            ["doubao_enable_punc", "标点预测", true],
                            ["doubao_enable_ddc", "语义顺滑", false],
                          ] as const
                        ).map(([key, label, enabledByDefault]) => (
                          <label className="section-header" key={key}>
                            <span className="section-title">{label}</span>
                            <input
                              aria-label={label}
                              className="toggle"
                              type="checkbox"
                              checked={
                                enabledByDefault
                                  ? voiceInput[key] !== false
                                  : voiceInput[key] === true
                              }
                              onChange={(event) => updateVoice({ [key]: event.target.checked })}
                            />
                          </label>
                        ))}
                        <label className="section-header">
                          <span className="section-title">热词表 ID</span>
                          <input
                            aria-label="热词表 ID"
                            value={voiceInput.doubao_boosting_table_id ?? ""}
                            onChange={(event) =>
                              updateVoice({ doubao_boosting_table_id: event.target.value })
                            }
                          />
                        </label>
                      </div>
                    )}
                    {!androidPlatform && (
                      <div className="section">
                        <div className="section-title">
                          文本润色 provider<small>识别结果可交给用户管理的服务润色</small>
                        </div>
                        <label className="section-header">
                          <span className="section-title">启用润色</span>
                          <input
                            aria-label="启用文本润色"
                            className="toggle"
                            type="checkbox"
                            checked={
                              voiceInput.polish_text === true || voiceInput.polish_enabled === true
                            }
                            onChange={(event) =>
                              updateVoice({
                                polish_text: event.target.checked,
                                polish_enabled: event.target.checked,
                              })
                            }
                          />
                        </label>
                        <label className="section-header">
                          <span className="section-title">服务提供商</span>
                          <select
                            aria-label="文本润色服务提供商"
                            value={voiceInput.polish_provider ?? "siliconflow"}
                            onChange={(event) =>
                              updateVoice(polishProviderUpdate(event.target.value, voiceInput))
                            }
                          >
                            <option value="siliconflow">SiliconFlow</option>
                            <option value="openai">OpenAI</option>
                            <option value="deepseek">DeepSeek</option>
                            <option value="groq">Groq</option>
                          </select>
                        </label>
                        {providerPresetControls(
                          "文本润色",
                          POLISH_PROVIDER_DEFAULTS[voiceInput.polish_provider ?? "siliconflow"],
                          voiceInput.polish_model ?? "",
                          (polish_model) => updateVoice({ polish_model }),
                          "provider-preset-section",
                        )}
                        <label className="section-header">
                          <span className="section-title">模型</span>
                          <input
                            aria-label="文本润色模型"
                            value={voiceInput.polish_model ?? ""}
                            onChange={(event) => updateVoice({ polish_model: event.target.value })}
                          />
                        </label>
                        {!linuxPlatform && (
                          <>
                            <label className="section-header">
                              <span className="section-title">
                                润色接口地址<small>留空使用当前 provider 默认地址</small>
                              </span>
                              <input
                                aria-label="润色接口地址"
                                type="url"
                                value={voiceInput.polish_endpoint ?? ""}
                                onChange={(event) =>
                                  updateVoice({ polish_endpoint: event.target.value })
                                }
                              />
                            </label>
                            <label className="section-header">
                              <span className="section-title">
                                润色 API Token<small>仅保存在本机设置中</small>
                              </span>
                              <SecretInput
                                label="润色 API Token"
                                value={voiceInput.polish_token ?? ""}
                                onChange={(value) => updateVoice({ polish_token: value })}
                              />
                            </label>
                          </>
                        )}
                        <label className="section-header">
                          <span className="section-title">润色方案</span>
                          <select
                            aria-label="润色方案"
                            value={polishSlot}
                            onChange={(event) =>
                              updateVoice({
                                polish_prompt_id: event.target.value,
                                polish_prompt: polishPromptFor(event.target.value, voiceInput),
                              })
                            }
                          >
                            {POLISH_PRESET_IDS.map((id) => (
                              <option key={id} value={id}>
                                {POLISH_PRESET_NAMES[id]}
                              </option>
                            ))}
                            <option value="custom_1">自定义一</option>
                            <option value="custom_2">自定义二</option>
                            <option value="custom_3">自定义三</option>
                          </select>
                        </label>
                        <label className="section-header polish-prompt-row">
                          <span className="section-title">
                            润色提示词
                            <small>
                              {isPolishCustomSlot(polishSlot)
                                ? "这一段会保存到所选的自定义方案"
                                : "内置方案的完整提示词，可以就地修改"}
                            </small>
                          </span>
                          <textarea
                            aria-label="润色提示词"
                            value={voiceInput.polish_prompt ?? ""}
                            onChange={(event) =>
                              updateVoice({
                                polish_prompt: event.target.value,
                                ...(polishSlotField(polishSlot)
                                  ? { [polishSlotField(polishSlot) as string]: event.target.value }
                                  : {}),
                              })
                            }
                          />
                        </label>
                        <button
                          type="button"
                          className="secondary"
                          disabled={
                            (voiceInput.polish_prompt ?? "") ===
                            polishPromptFor(polishSlot, voiceInput)
                          }
                          onClick={() =>
                            updateVoice({ polish_prompt: polishPromptFor(polishSlot, voiceInput) })
                          }
                        >
                          恢复默认
                        </button>
                        {linuxPlatform &&
                          credentialTestControl(
                            "voice.polish",
                            "测试语音润色配置",
                            {
                              polish_provider: voiceInput.polish_provider ?? "siliconflow",
                              polish_model: voiceInput.polish_model ?? "",
                            },
                            !(
                              voiceInput.polish_text === true || voiceInput.polish_enabled === true
                            ),
                          )}
                        {(windowsPlatform || macosPlatform || iosPlatform || harmonyPlatform) &&
                          credentialTestControl(
                            "voice.polish",
                            "测试语音润色配置",
                            {
                              provider: voiceInput.polish_provider ?? "siliconflow",
                              endpoint:
                                voiceInput.polish_endpoint?.trim() ||
                                POLISH_PROVIDER_DEFAULTS[
                                  voiceInput.polish_provider ?? "siliconflow"
                                ]?.endpoint ||
                                "",
                              model:
                                voiceInput.polish_model?.trim() ||
                                POLISH_PROVIDER_DEFAULTS[
                                  voiceInput.polish_provider ?? "siliconflow"
                                ]?.model ||
                                "",
                              token: voiceInput.polish_token ?? "",
                            },
                            !voiceInput.polish_token?.trim(),
                          )}
                      </div>
                    )}
                    {!androidPlatform && (
                      <div className="section">
                        <div className="section-title">
                          {linuxPlatform ? "Linux IBus 快捷键" : "语音快捷键"}
                          <small>
                            {linuxPlatform
                              ? "在当前输入上下文中切换语音录音；没有 provider 时快捷键不会拦截编辑器输入"
                              : macosPlatform
                                ? "输入法启用时按住修饰键快捷键录音，松开结束；组合键先按 Control。按住期间按空格锁定，Escape 取消。修饰键快捷键由输入法自身接收，不需要额外授权；Ctrl+F9 在输入法会话之外接收，需要在「系统设置 › 隐私与安全性 › 输入监控」中允许本输入法，否则按下没有任何反应。首次授权后请重新按键。"
                                : "输入法运行时全局生效，用于开始和结束语音录音"}
                          </small>
                        </div>
                        {(
                          [
                            ["hotkey_ctrl_f9", "Ctrl+F9 切换语音"],
                            [
                              "hotkey_ralt",
                              macosPlatform ? "按住右 Option 录音" : "右 Alt 切换语音",
                            ],
                            [
                              "hotkey_rctrl_ralt",
                              macosPlatform
                                ? "按住右 Control+右 Option 录音"
                                : "Ctrl+右 Alt 切换语音",
                            ],
                            [
                              "hotkey_ctrl_win",
                              macosPlatform ? "按住 Control+Command 录音" : "Ctrl+Win 切换语音",
                            ],
                            ["hotkey_hold_space_lock", "空格锁定语音"],
                          ] as const
                        ).map(([key, label]) => (
                          <label className="section-header" key={key}>
                            <span className="section-title">{label}</span>
                            <input
                              aria-label={label}
                              className="toggle"
                              type="checkbox"
                              checked={draft.voice_input?.[key] !== false}
                              onChange={(event) =>
                                setDraft({
                                  ...draft,
                                  voice_input: {
                                    ...draft.voice_input,
                                    enabled: draft.voice_input?.enabled ?? true,
                                    language: draft.voice_input?.language ?? "zh-CN",
                                    [key]: event.target.checked,
                                  },
                                })
                              }
                            />
                          </label>
                        ))}
                      </div>
                    )}
                  </fieldset>
                  <fieldset disabled={busy} hidden={page !== "ai"} aria-label="AI 辅助">
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">
                          启用 AI 辅助
                          <small>
                            {iosPlatform
                              ? "为键盘 AI 联想、回复与润色提供共享配置"
                              : androidPlatform
                                ? "为拼音联想和 Android 选中文字润色提供共享配置"
                                : "为拼音联想提供共享配置"}
                          </small>
                        </span>
                        <input
                          aria-label="启用 AI 辅助"
                          className="toggle"
                          type="checkbox"
                          checked={ai.enabled}
                          onChange={(event) => updateAi({ enabled: event.target.checked })}
                        />
                      </label>
                    </div>
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">服务提供商</span>
                        <select
                          aria-label="AI 服务提供商"
                          value={ai.provider}
                          onChange={(event) => updateAi(aiProviderUpdate(event.target.value, ai))}
                        >
                          {AI_PROVIDER_OPTIONS.map((option) => (
                            <option key={option.id} value={option.id}>
                              {option.title}
                            </option>
                          ))}
                        </select>
                      </label>
                    </div>
                    {providerPresetControls(
                      "AI ",
                      AI_PROVIDER_OPTIONS.find((option) => option.id === ai.provider),
                      ai.model,
                      (model) => updateAi({ model }),
                    )}
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">模型</span>
                        <input
                          aria-label="AI 模型"
                          value={ai.model}
                          onChange={(event) => updateAi({ model: event.target.value })}
                        />
                      </label>
                    </div>
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">接口地址</span>
                        <input
                          aria-label="AI 接口地址"
                          type="url"
                          value={ai.endpoint}
                          onChange={(event) => updateAi({ endpoint: event.target.value })}
                        />
                      </label>
                    </div>
                    {linuxPlatform ? (
                      <div className="section">
                        <div className="section-title">
                          Linux AI provider<small>AI 请求由用户管理的 provider 服务完成</small>
                        </div>
                        <p className="input-setting-description">
                          凭据不保存在共享设置中；请在用户配置目录的 <code>ai-provider.json</code>{" "}
                          中配置，并使其中的 provider、接口地址和模型与上方设置一致。
                        </p>
                        {credentialTestControl(
                          "ai.assistant",
                          "测试 AI 辅助配置",
                          { provider: ai.provider, endpoint: ai.endpoint, model: ai.model },
                          !ai.enabled || !aiOrigin || !ai.model.trim(),
                        )}
                      </div>
                    ) : (
                      <div className="section">
                        <label className="section-header">
                          <span className="section-title">
                            API Token
                            <small>
                              {aiOrigin ? `只用于 ${aiOrigin}` : "请先填写有效的 HTTPS 接口地址"}
                            </small>
                          </span>
                          <input
                            aria-label="AI API Token"
                            type="password"
                            autoComplete="off"
                            disabled={!aiOrigin}
                            value={aiToken}
                            onChange={(event) => updateAiToken(event.target.value)}
                          />
                        </label>
                      </div>
                    )}
                    {(windowsPlatform || macosPlatform || iosPlatform) &&
                      credentialTestControl(
                        "ai.assistant",
                        "测试 AI 辅助配置",
                        {
                          provider: ai.provider,
                          endpoint: ai.endpoint,
                          model: ai.model,
                          token: aiToken,
                        },
                        !ai.enabled || !aiOrigin || !ai.model.trim() || !aiToken.trim(),
                      )}
                    {client.aiAssistant && (
                      <div className="section">
                        <div className="section-header">
                          <span className="section-title">
                            服务模型
                            <small>
                              从当前服务的模型目录读取；服务不支持时可继续手动填写模型。
                            </small>
                          </span>
                          <button
                            type="button"
                            className="secondary"
                            disabled={aiModelsBusy || !aiOrigin}
                            onClick={() => void fetchAiModels()}
                          >
                            {aiModelsBusy ? "获取中…" : "获取模型列表"}
                          </button>
                        </div>
                        {aiModels && aiModels.length > 0 && (
                          <label className="section-header">
                            <span className="section-title">已获取模型</span>
                            <select
                              aria-label="已获取的 AI 模型"
                              value={aiModels.includes(ai.model) ? ai.model : ""}
                              onChange={(event) => {
                                if (event.target.value) updateAi({ model: event.target.value });
                              }}
                            >
                              <option value="">选择模型…</option>
                              {aiModels.map((model) => (
                                <option key={model} value={model}>
                                  {model}
                                </option>
                              ))}
                            </select>
                          </label>
                        )}
                        {aiModelsStatus && <p role="status">{aiModelsStatus}</p>}
                      </div>
                    )}
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">候选数量</span>
                        <input
                          aria-label="AI 候选数量"
                          type="number"
                          min="1"
                          max="10"
                          value={ai.candidate_limit}
                          onChange={(event) =>
                            updateAi({
                              candidate_limit: Math.max(
                                1,
                                Math.min(10, Number(event.target.value) || 3),
                              ),
                            })
                          }
                        />
                      </label>
                    </div>
                    <div className="section">
                      <label className="section-header">
                        <span className="section-title">
                          AI 联想提示词方案
                          <small>使用选中的独立槽位；槽位留空时使用兼容提示词</small>
                        </span>
                        <select
                          aria-label="AI 联想提示词方案"
                          value={
                            ai.prompt_id === "custom" ? "custom_1" : ai.prompt_id || "custom_1"
                          }
                          onChange={(event) => updateAi({ prompt_id: event.target.value })}
                        >
                          <option value="custom_1">自定义一</option>
                          <option value="custom_2">自定义二</option>
                          <option value="custom_3">自定义三</option>
                        </select>
                      </label>
                    </div>
                    <div className="section">
                      <label className="section-title">
                        兼容提示词<small>旧版提示词，所选自定义槽位留空时使用</small>
                      </label>
                      <textarea
                        aria-label="AI 润色提示词"
                        value={ai.prompt ?? defaultAiAssistant.prompt}
                        onChange={(event) => updateAi({ prompt: event.target.value })}
                      />
                    </div>
                    <div className="section">
                      <label className="section-title">
                        自定义提示词一<small>发送给 AI 联想服务的额外提示词</small>
                      </label>
                      <textarea
                        aria-label="自定义提示词一"
                        value={ai.prompt_custom_1}
                        onChange={(event) => updateAi({ prompt_custom_1: event.target.value })}
                      />
                    </div>
                    <div className="section">
                      <label className="section-title">自定义提示词二</label>
                      <textarea
                        aria-label="自定义提示词二"
                        value={ai.prompt_custom_2}
                        onChange={(event) => updateAi({ prompt_custom_2: event.target.value })}
                      />
                    </div>
                    <div className="section">
                      <label className="section-title">自定义提示词三</label>
                      <textarea
                        aria-label="自定义提示词三"
                        value={ai.prompt_custom_3}
                        onChange={(event) => updateAi({ prompt_custom_3: event.target.value })}
                      />
                    </div>
                    {client.aiAssistant && (
                      <div className="section ai-test-tools">
                        <div className="section-title">
                          AI 润色测试
                          <small>仅在点击发送时请求当前配置；测试文字不会写入日志。</small>
                        </div>
                        <textarea
                          aria-label="AI 测试输入"
                          placeholder="输入一段待润色文字"
                          value={aiTestInput}
                          onChange={(event) => setAiTestInput(event.target.value)}
                        />
                        <button
                          type="button"
                          className="secondary"
                          disabled={aiTestBusy || !aiTestInput.trim()}
                          onClick={() => void testAi()}
                        >
                          {aiTestBusy ? "发送中…" : "发送并润色"}
                        </button>
                        {aiTestStatus && <p role="status">{aiTestStatus}</p>}
                        {aiTestOutput && (
                          <div className="ai-test-result">
                            <div>{aiTestOutput}</div>
                            {client.copyText && (
                              <button
                                type="button"
                                className="secondary"
                                onClick={() => void client.copyText!(aiTestOutput)}
                              >
                                复制结果
                              </button>
                            )}
                          </div>
                        )}
                      </div>
                    )}
                  </fieldset>
                  <fieldset disabled={busy} hidden={page !== "feedback"} aria-label="反馈">
                    <div className={`section ${doc.hero}`}>
                      <div className={doc.eyebrow}>反馈与交流</div>
                      <div className={doc.heroTitle}>告诉我们你的想法</div>
                      <p>遇到问题或有功能建议时，可以通过以下渠道提交和交流。</p>
                    </div>
                    <div className="section" aria-label="问题报告">
                      <div className="section-title">
                        提交可复现的问题
                        <small>报告只在你点击按钮时生成，不会读取或上传输入历史。</small>
                      </div>
                      <label className="section-header">
                        <span className="section-title">类型</span>
                        <select
                          aria-label="反馈类型"
                          value={feedbackKind}
                          onChange={(event) => setFeedbackKind(event.target.value)}
                        >
                          <option>功能异常</option>
                          <option>候选词不对</option>
                          <option>功能建议</option>
                          <option>其他</option>
                        </select>
                      </label>
                      <label className="section-title">
                        描述
                        <textarea
                          aria-label="反馈描述"
                          maxLength={4000}
                          value={feedbackDetail}
                          onChange={(event) => setFeedbackDetail(event.target.value)}
                          placeholder="发生了什么？如果和打字有关，写出输入方案、编码和期望结果。"
                          rows={6}
                        />
                      </label>
                      <div className={doc.note}>
                        <strong>会一起附上的信息</strong>
                        <span className="block break-anywhere text-xs text-secondary">
                          {supportDiagnostics}
                        </span>
                      </div>
                      <div className={settings.serviceRow}>
                        {client.copyText && (
                          <button
                            type="button"
                            className="secondary"
                            onClick={() =>
                              void client.copyText!(feedbackReport).then(() => {
                                setFeedbackReportCopied(true);
                                window.setTimeout(() => setFeedbackReportCopied(false), 1600);
                              })
                            }
                          >
                            {feedbackReportCopied ? "已复制报告" : "复制报告"}
                          </button>
                        )}
                        {client.openExternalUrl && (
                          <button type="button" className="secondary" onClick={submitFeedback}>
                            在 GitHub 提交
                          </button>
                        )}
                      </div>
                      <small>
                        提交会打开 GitHub
                        并预填报告；网址长度有限，过长描述会被截断，完整内容请先复制。
                      </small>
                    </div>
                    <div className={doc.feedbackList}>
                      <div className={`section ${doc.feedbackCard}`}>
                        <div className={doc.feedbackIcon}>GH</div>
                        <div className={doc.feedbackBody}>
                          <div className={doc.feedbackTitle}>GitHub Issues</div>
                          <p>适合提交可复现的问题、功能建议和开发讨论。</p>
                          <code>{platformIssuesUrl.replace("https://", "")}</code>
                        </div>
                        <button
                          type="button"
                          className="secondary"
                          onClick={() => void openExternalUrl(platformIssuesUrl)}
                        >
                          查看 Issues
                        </button>
                      </div>
                      <div className={`section ${doc.feedbackCard}`}>
                        <div className={doc.feedbackIcon}>QQ</div>
                        <div className={doc.feedbackBody}>
                          <div className={doc.feedbackTitle}>QQ 交流群</div>
                          <p>适合中文用户进行日常交流、测试反馈和使用讨论。</p>
                          <code>群号：829919142</code>
                        </div>
                        <button
                          type="button"
                          className="secondary"
                          onClick={() => {
                            if (!client.copyText) return;
                            void client.copyText("829919142").then(() => {
                              setFeedbackCopied(true);
                              window.setTimeout(() => setFeedbackCopied(false), 1600);
                            });
                          }}
                        >
                          {feedbackCopied ? "已复制" : "复制群号"}
                        </button>
                      </div>
                      <div className={`section ${doc.feedbackCard}`}>
                        <div className={doc.feedbackIcon}>TG</div>
                        <div className={doc.feedbackBody}>
                          <div className={doc.feedbackTitle}>Telegram 群组</div>
                          <p>面向国际用户和开发者的即时讨论频道。</p>
                          <code>t.me/msimegroup</code>
                        </div>
                        <button
                          type="button"
                          className="secondary"
                          onClick={() => void openExternalUrl("https://t.me/msimegroup")}
                        >
                          打开群组
                        </button>
                      </div>
                    </div>
                    <div className={`section ${doc.note}`}>
                      <strong>提交问题时建议附上</strong>
                      <span>
                        系统版本、输入方案、复现步骤、相关截图，以及 Debug 输出中的关键日志。
                      </span>
                    </div>
                  </fieldset>
                  {!validCandidateFonts(draft) && (
                    <p role="alert">
                      请在外观页修正字体：名称不能为空、不能含控制字符或超过 128 个 UTF-8
                      字节，补充字体最多 32 项。
                    </p>
                  )}
                  <footer className={settings.settingsActions}>
                    {client.loadDefaultPreferences && (
                      <button
                        type="button"
                        className="secondary"
                        disabled={busy}
                        onClick={() => void restoreDefaults()}
                      >
                        恢复默认设置
                      </button>
                    )}
                    <span>{dirty ? "有未保存的修改" : ""}</span>
                    <button type="submit" disabled={busy || !dirty || !validCandidateFonts(draft)}>
                      {busy ? "处理中…" : "保存设置"}
                    </button>
                  </footer>
                </form>
              )}
            {page !== "typing-statistics" &&
              page !== "account" &&
              page !== "chat" &&
              page !== "community" && (
                <button
                  className="secondary"
                  disabled={busy}
                  onClick={() => {
                    if (!dirty) {
                      void reload();
                      return;
                    }
                    void confirm({
                      title: "重新读取",
                      message: "尚未保存的修改会被放弃。",
                      confirmLabel: "放弃并重新读取",
                      danger: true,
                    }).then((confirmed) => {
                      if (confirmed) void reload();
                    });
                  }}
                >
                  重新读取
                </button>
              )}
          </div>
        </main>
      </div>
    </div>
  );
}
