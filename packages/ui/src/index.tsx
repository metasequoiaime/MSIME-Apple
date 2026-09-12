import { useEffect, useRef, useState } from "react";
import { HostActionButton } from "./HostActionButton";
import { DICTIONARY_PAGE_SIZE, dictionaryPageStatus, readDictionaryFile } from "./dictionary-file";
import { SkinCandidatePreview } from "./skin-candidate-preview";
import { AppearanceCandidatePreview } from "./appearance-candidate-preview";
import { candidateFontSize, candidateFontSizes } from "./candidate-font-size";
import { candidateTextColor } from "./candidate-text-color";
import { useCandidatePreviewTheme } from "./candidate-preview-theme";
import { CandidateFontControls } from "./candidate-font-controls";
import { validCandidateFonts } from "./candidate-font-family";
import type { FontCatalogReader } from "./font-catalog";
import { SkinToolbarPreview } from "./skin-toolbar-preview";
import { ScreenKeyboardPreview } from "./screen-keyboard-preview";
import { ExternalSkins, type SkinCatalog } from "./external-skins";
import { TypingStatisticsPage, type TypingStatisticsClient } from "./typing-statistics";
export { TypingStatisticsPage, type TypingBreakdown, type TypingStatistics, type TypingStatisticsClient, type TypingStatisticsStatus } from "./typing-statistics";
export type { SkinCatalog, ExternalSkin } from "./external-skins";
import type { SkinImageReader } from "./skin-image";
export type { SkinImage, SkinImageReader } from "./skin-image";
import type { SkinFontReader } from "./skin-font";
export type { SkinFont, SkinFontReader } from "./skin-font";
export { candidateTemplate, candidateThemeStylesheet, type CandidateAppearance, type CandidateOrientation, type CandidateTheme } from "./candidate-themes";
import { compareVersions, describeInstallerTrust, parseVersion, validateManifest, type UpdateManifest, type ValidatedUpdate } from "./update-manifest";
export { serializeWindowHostMessage, type WindowControl, type WindowHostMessage, type WindowResizeEdge } from "./window-host";
export { CloudClipboardPanel, CloudDictionaryPanel, EmojiPanel, HandwritingPanel, KeyboardPanel, VoicePanel, type CloudClipboardAction, type CloudClipboardPanelClient, type CloudDictionaryAction, type CloudDictionaryEntry, type CloudDictionaryFileFormat, type CloudDictionaryKind, type CloudDictionaryPanelClient, type EmojiPanelClient, type PanelClient, type VoicePanelClient } from "./panels";
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
export type FuzzyPinyinPreferences = { enabled: boolean; rules: string[] };
const defaultFuzzyPinyin: FuzzyPinyinPreferences = { enabled: false, rules: [] };
const fuzzyPinyinGroups: [string, [string, string][]][] = [
  ["平翘舌", [["z-zh", "z ↔ zh"], ["c-ch", "c ↔ ch"], ["s-sh", "s ↔ sh"]]],
  ["声母", [["n-l", "n ↔ l"], ["f-h", "f ↔ h"], ["r-l", "r ↔ l"]]],
  ["前后鼻音", [["an-ang", "an ↔ ang"], ["en-eng", "en ↔ eng"], ["in-ing", "in ↔ ing"]]],
  ["其他韵母", [["ian-iang", "ian ↔ iang"], ["uan-uang", "uan ↔ uang"]]],
];
const helpcodeSchemas: [HelpcodeSchema, string][] = [["lantian", "蓝天小雨点"], ["ziranma", "自然码"], ["shouyou2_0", "首右2.0"], ["shouyouplus", "首右plus"], ["xiaohe", "小鹤"]];
const pages = [
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
const linuxLicenseUrl = "https://github.com/metasequoiaime/MSIME-Client/blob/main/LICENSE";
const linuxIssuesUrl = "https://github.com/metasequoiaime/MSIME-Client/issues";

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
  voice_input?: VoiceInputPreferences;
  local_modes?: LocalModePreferences;
  clipboard_history?: boolean;
  cloud_candidates?: boolean;
  candidate_translations?: boolean;
  translation_target_language?: "en" | "fr" | "ja" | "es" | "ru" | "de" | "ko";
  floating_toolbar?: FloatingToolbarPreferences;
  mixed_input?: MixedInputPreferences;
  fuzzy_pinyin?: FuzzyPinyinPreferences;
  frequency?: FrequencyPreferences;
  word_character?: { enabled: boolean; keys: "brackets" | "minus_equal" };
  navigation?: NavigationPreferences;
  keybindings?: KeybindingPreferences;
  scheme: "quanpin" | "shuangpin" | "wubi" | "japanese";
  touch_keyboard_layout?: "twenty_six_key" | "nine_key" | "handwriting";
  touch_key_spacing_tenths?: number;
  touch_row_spacing_tenths?: number;
  touch_voice_shortcut?: boolean;
  default_ime_mode?: "chinese" | "english";
  ime_mode_scope?: "app" | "global";
  last_chinese_scheme?: "quanpin" | "shuangpin" | "wubi" | null;
  shuangpin_profile: "xiaohe" | "ziranma" | "shoudao" | "microsoft";
  candidate_page_size: number;
  candidate_font_size?: number;
  candidate_preedit_font_size?: number;
  candidate_text_color?: string | null;
  candidate_font_family?: string;
  candidate_fallback_fonts?: string[];
  candidate_layout?: "horizontal" | "vertical";
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
  asr_provider?: string;
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
const defaultVoiceInput: VoiceInputPreferences = { enabled: true, language: "zh-CN", asr_provider: "local_whisper", asr_resource_id: "volc.seedasr.sauc.duration" };

export function aiCredentialOrigin(endpoint: string): string | null {
  if (!endpoint || endpoint.length > 2048 || /[\u0000-\u001f\u007f]/.test(endpoint)) return null;
  try {
    const url = new URL(endpoint.trim());
    if (url.protocol !== "https:" || !url.hostname || url.username || url.password || url.hash) return null;
    return `https://${url.hostname.toLowerCase()}:${url.port || "443"}`;
  } catch { return null; }
}
const defaultCustomTranslation = { enabled: false, endpoint: "", api_key: "" };
export type ExternalSkinCatalog = { scanned: boolean; directory?: string; revision?: number; packages: Array<{ id: string; title: string; description?: string; valid?: boolean }> ; issues?: string[] };
export type Snapshot = { format_version: number; revision: number; preferences: Preferences; candidate_skin_catalog?: ExternalSkinCatalog };
export type LocalDictionaryKind = "pinyin" | "wubi" | "quick_phrase" | "english";
export type LocalDictionaryFormat = "standard" | "windows" | "rime" | "hans";
export type DictionaryEntry = { kind: LocalDictionaryKind; key: string; value: string; weight: number };
export interface DictionaryClient {
  list(offset: number, limit: number): Promise<{ entries: DictionaryEntry[]; has_more: boolean }>;
  edit(previous: DictionaryEntry | null, replacement: DictionaryEntry | null, request_id: string): Promise<void>;
  import?(kind: LocalDictionaryKind, format: LocalDictionaryFormat, text: string, request_id: string): Promise<{ applied: number }>;
  export?(kind: LocalDictionaryKind, format: Exclude<LocalDictionaryFormat, "rime" | "hans">, offset: number, limit: number): Promise<{ text: string; has_more: boolean }>;
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
export type MixedInputPreferences = { english: boolean; minimum_prefix: number; emoji: boolean; kaomoji: boolean };
const defaultMixedInput: MixedInputPreferences = { english: true, minimum_prefix: 2, emoji: false, kaomoji: false };
export type FrequencyPreferences = { mode: "disabled" | "pin" | "halve" | "linear" | "promote"; trigger_count: number; linear_step: number };
const defaultFrequency: FrequencyPreferences = { mode: "promote", trigger_count: 1, linear_step: 1 };
export type NavigationPreferences = { minus_equal: boolean; comma_period: boolean; brackets: boolean; tab: boolean; page_up_down: boolean; arrows: boolean };
const defaultNavigation: NavigationPreferences = { minus_equal: true, comma_period: true, brackets: false, tab: true, page_up_down: true, arrows: true };
const translationLanguages: [NonNullable<Preferences["translation_target_language"]>, string][] = [["en", "英语"], ["fr", "法语"], ["ja", "日语"], ["es", "西班牙语"], ["ru", "俄语"], ["de", "德语"], ["ko", "韩语"]];
const defaultWordCharacter = { enabled: false, keys: "brackets" as const };
const navigationOptions: [keyof NavigationPreferences, string][] = [["minus_equal", "- / ="], ["comma_period", ", / ."], ["brackets", "[ / ]"], ["tab", "Shift+Tab / Tab"], ["page_up_down", "PageUp / PageDown"], ["arrows", "上 / 下（移动候选项）"]];
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
  /** Android exposes the Apple-parity fuzzy-pinyin settings; desktop hosts keep this absent. */
  fuzzyPinyin?: boolean;
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

export function SettingsPage({ client }: { client: SettingsClient }) {
  const linuxPlatform = isLinuxDesktop();
  const platformReleasesPageUrl = linuxPlatform ? linuxReleasesPageUrl : releasesPageUrl;
  const platformLicenseUrl = linuxPlatform ? linuxLicenseUrl : licenseUrl;
  const platformIssuesUrl = linuxPlatform ? linuxIssuesUrl : "https://github.com/metasequoiaime/MSIME-Windows/issues";
  const [snapshot, setSnapshot] = useState<Snapshot>();
  const [draft, setDraft] = useState<Preferences>();
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [page, setPage] = useState<(typeof pages)[number]["id"]>("appearance");
  const [updateStatus, setUpdateStatus] = useState("");
  const [updateBusy, setUpdateBusy] = useState(false);
  const [availableUpdate, setAvailableUpdate] = useState<ValidatedUpdate | null>(null);
  const [feedbackCopied, setFeedbackCopied] = useState(false);
  const [phrases, setPhrases] = useState<DictionaryEntry[]>([]);
  const [phrasePage, setPhrasePage] = useState({ offset: 0, hasMore: false, status: "" });
  const [phraseBusy, setPhraseBusy] = useState(false);
  const [phraseError, setPhraseError] = useState("");
  const [phraseSearch, setPhraseSearch] = useState("");
  const [phraseForm, setPhraseForm] = useState<{ key: string; value: string; weight: number; previous: DictionaryEntry | null } | null>(null);
  const [dictionaryKind, setDictionaryKind] = useState<LocalDictionaryKind>("quick_phrase");
  const [dictionaryFormat, setDictionaryFormat] = useState<LocalDictionaryFormat>("standard");
  const [windowMaximized, setWindowMaximized] = useState(false);
  const [skinPreviewThemes, setSkinPreviewThemes] = useState<Partial<Record<NonNullable<Preferences["candidate_skin"]>, "light" | "dark">>>({});
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
    setPhraseBusy(true); setPhraseError("");
    setPhrasePage(current => ({ ...current, status: "查询中…" }));
    try {
      const page = await client.dictionary.list(offset, DICTIONARY_PAGE_SIZE);
      const entries = page.entries.filter(entry => entry.kind === kind);
      setPhrases(entries);
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
    setPhraseBusy(true); setPhraseError("");
    try { await client.dictionary.edit(entry, null, requestId("ui-remove")); await loadPhrases(); }
    catch { setPhraseError("快捷短语删除失败，请稍后重试。"); }
    finally { setPhraseBusy(false); }
  }
  async function savePhrase() {
    if (!client.dictionary || !phraseForm) return;
    const replacement: DictionaryEntry = { kind: dictionaryKind, key: phraseForm.key.trim(), value: phraseForm.value, weight: phraseForm.weight };
    if (!replacement.key || !replacement.value) { setPhraseError("编码和短语不能为空。"); return; }
    setPhraseBusy(true); setPhraseError("");
    try { await client.dictionary.edit(phraseForm.previous, replacement, requestId(phraseForm.previous ? "ui-edit" : "ui-add")); setPhraseForm(null); await loadPhrases(); }
    catch { setPhraseError("快捷短语保存失败，请稍后重试。"); }
    finally { setPhraseBusy(false); }
  }
  async function importPhrases(file: File) {
    if (!client.dictionary) return;
    setPhraseBusy(true); setPhraseError("");
    try {
      const text = await readDictionaryFile(file);
      if (client.dictionary.import) {
        await client.dictionary.import(dictionaryKind, dictionaryFormat, text, requestId("ui-import"));
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
    } catch { setPhraseError("快捷短语导入失败，请检查文本格式。"); }
    finally { setPhraseBusy(false); }
  }
  async function exportPhrases() {
    if (!client.dictionary) return;
    if (dictionaryFormat === "hans") { setPhraseError("汉字自动注音格式仅支持导入。"); return; }
    setPhraseBusy(true); setPhraseError("");
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
      const url = URL.createObjectURL(new Blob([text], { type: "text/plain;charset=utf-8" }));
      const anchor = document.createElement("a"); anchor.href = url; anchor.download = `msime-${dictionaryKind}-dictionary.tsv`; anchor.click(); URL.revokeObjectURL(url);
    } catch { setPhraseError("词库导出失败，请稍后重试。"); }
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
  const localModes = draft?.local_modes ?? defaultLocalModes;
  const quanpinAutocorrect = {
    autocorrect_transposition: draft?.quanpin?.autocorrect_transposition ?? draft?.autocorrect ?? true,
    autocorrect_neighbor: draft?.quanpin?.autocorrect_neighbor ?? draft?.autocorrect ?? true,
  };
  const clipboardHistory = draft?.clipboard_history ?? false;
  const diagnosticLog = { server: draft?.diagnostic_log?.server ?? false, tsf: draft?.diagnostic_log?.tsf ?? false };
  const cloudCandidates = draft?.cloud_candidates ?? true;
  const candidateTranslations = draft?.candidate_translations ?? true;
  const translationTargetLanguage = draft?.translation_target_language ?? "en";
  const voiceInput = { ...defaultVoiceInput, ...(draft?.voice_input ?? {}) };
  const updateVoice = (patch: Partial<VoiceInputPreferences>) => {
    if (draft) setDraft({ ...draft, voice_input: { ...voiceInput, ...patch } });
  };
  const customTranslation = draft?.custom_translation ?? defaultCustomTranslation;
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
  useEffect(() => setSkinPreviewThemes({}), [candidatePreviewTheme]);
  const touchKeySpacingTenths = draft?.touch_key_spacing_tenths ?? 60;
  const touchRowSpacingTenths = draft?.touch_row_spacing_tenths ?? 70;
  const installerTrust = availableUpdate ? describeInstallerTrust(availableUpdate) : null;
  const [clipboardEntries, setClipboardEntries] = useState<string[]>([]);
  const availablePages = client.typingStatistics ? pages : pages.filter(item => item.id !== "typing-statistics");
  useEffect(() => {
    if (page === "typing-statistics" && !client.typingStatistics) setPage("appearance");
  }, [client.typingStatistics, page]);
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
    if (!client.clipboard?.list) return;
    void client.clipboard.list().then(setClipboardEntries).catch(() => undefined);
  }, [client, page]);
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
        aria-current={page === item.id ? "page" : undefined} aria-controls="settings-content" onClick={() => setPage(item.id)}>
        <span className="icon"><img src={item.icon} alt="" /></span>{item.title}
      </button>)}
      <p className="preview-label">客户端预览版</p>
    </nav>
    <main id="settings-content" aria-labelledby="page-title"><div className="content">
    <header className="content-header"><h1 id="page-title">{availablePages.find(item => item.id === page)?.title ?? "外观"}</h1></header>
    {error && <p role="alert" className="error">{error}</p>}
    {notice && <p role="status" className="notice">{notice}</p>}
    {busy && !draft && <p role="status">正在读取设置…</p>}
    {client.typingStatistics && page === "typing-statistics" && <TypingStatisticsPage client={client.typingStatistics} />}
    {draft && page !== "typing-statistics" && <form onSubmit={event => { event.preventDefault(); void save(); }}>
      <fieldset disabled={busy} hidden={page !== "appearance"} aria-label="外观">
        <AppearanceCandidatePreview preferences={draft} scan={client.scanSkinCatalog} readImage={client.readSkinImage} active={page === "appearance"} revision={snapshot?.revision ?? 0} />
        <div className="section"><label className="section-header"><span className="section-title">工具栏主题<small>覆盖全局主题；当前影响工具栏设置预览，原生工具栏需宿主支持</small></span><select aria-label="工具栏主题" value={draft.toolbar_theme ?? "follow"} onChange={event => setDraft({ ...draft, toolbar_theme: event.target.value as SurfaceTheme })}><option value="follow">跟随全局</option><option value="dark">深色</option><option value="light">浅色</option></select></label></div>
        <div className="section"><label className="section-header"><span className="section-title">手写面板主题<small>覆盖手写识别板的明暗外观</small></span><select aria-label="手写面板主题" value={draft.handwriting_theme ?? "follow"} onChange={event => setDraft({ ...draft, handwriting_theme: event.target.value as SurfaceTheme })}><option value="follow">跟随全局</option><option value="dark">深色</option><option value="light">浅色</option></select></label></div>
        <div className="section"><label className="section-header"><span className="section-title">语音面板主题<small>覆盖语音输入面板的明暗外观</small></span><select aria-label="语音面板主题" value={draft.voice_theme ?? "follow"} onChange={event => setDraft({ ...draft, voice_theme: event.target.value as SurfaceTheme })}><option value="follow">跟随全局</option><option value="dark">深色</option><option value="light">浅色</option></select></label></div>
        <div className="section"><label className="section-header"><span className="section-title">Emoji 面板主题<small>覆盖 Emoji、颜文字和符号面板的明暗外观</small></span><select aria-label="Emoji 面板主题" value={draft.emoji_theme ?? "follow"} onChange={event => setDraft({ ...draft, emoji_theme: event.target.value as SurfaceTheme })}><option value="follow">跟随全局</option><option value="dark">深色</option><option value="light">浅色</option></select></label></div>
        <CandidateFontControls value={draft} onChange={patch => setDraft({ ...draft, ...patch })} readFonts={client.listFontFamilies} />
        <div className="section"><label className="section-header"><span className="section-title">全局主题<small>设置窗口和各界面的默认明暗模式</small></span><select aria-label="全局主题" value={themeMode} onChange={event => setDraft({ ...draft, theme: event.target.value as ThemeMode })}><option value="dark">深色</option><option value="light">浅色</option><option value="system">跟随系统</option></select></label></div>
        <div className="section"><label className="section-header"><span className="section-title">设置窗口主题<small>覆盖全局主题，仅影响当前设置窗口</small></span><select aria-label="设置窗口主题" value={settingsTheme} onChange={event => setDraft({ ...draft, settings_theme: event.target.value as SurfaceTheme })}><option value="follow">跟随全局</option><option value="dark">深色</option><option value="light">浅色</option></select></label></div>
        <div className="section"><label className="section-header"><span className="section-title">候选窗主题<small>预览跟随全局主题；Linux IBus panel 支持时使用，跟随时由桌面主题决定</small></span><select aria-label="候选窗主题" value={draft.candidate_theme ?? "follow"} onChange={event => setDraft({ ...draft, candidate_theme: event.target.value as SurfaceTheme })}><option value="follow">跟随</option><option value="dark">深色</option><option value="light">浅色</option></select></label></div>
        <div className="section"><label className="section-header"><span className="section-title">候选布局</span><select aria-label="候选布局" value={draft.candidate_layout ?? "vertical"} onChange={event => setDraft({ ...draft, candidate_layout: event.target.value as Preferences["candidate_layout"] })}>
          <option value="vertical">竖排</option><option value="horizontal">横排</option>
        </select></label></div>
        <div className="section"><label className="section-header"><span className="section-title">候选字号</span><select aria-label="候选字号" value={candidateFontSize(draft.candidate_font_size)} onChange={event => setDraft({ ...draft, candidate_font_size: Number(event.target.value) })}>
          {candidateFontSizes.map(size => <option key={size} value={size}>{size}</option>)}
        </select></label></div>
        <div className="section"><label className="section-header"><span className="section-title">候选窗预编辑字号</span><select aria-label="候选窗预编辑字号" value={candidateFontSize(draft.candidate_preedit_font_size)} onChange={event => setDraft({ ...draft, candidate_preedit_font_size: Number(event.target.value) })}>
          {candidateFontSizes.map(size => <option key={size} value={size}>{size}</option>)}
        </select></label></div>
        <div className="section"><div className="section-header"><span className="section-title">候选文字颜色</span><div className="candidate-color-control">
          <input aria-label="候选文字颜色" type="color" value={candidateTextColor(draft.candidate_text_color) ?? (candidatePreviewTheme === "light" ? "#1a1a1a" : "#e9e8e8")} onChange={event => setDraft({ ...draft, candidate_text_color: event.target.value })} />
          <button type="button" className={`candidate-color-reset${candidateTextColor(draft.candidate_text_color) ? "" : " is-active"}`} aria-pressed={!candidateTextColor(draft.candidate_text_color)} onClick={() => { if (candidateTextColor(draft.candidate_text_color)) setDraft({ ...draft, candidate_text_color: null }); }}>跟随主题</button>
        </div></div></div>
        <div className="section"><label className="section-header"><span className="section-title">候选窗预编辑</span><select aria-label="候选窗预编辑" value={draft.candidate_preedit_style ?? "pinyin"} onChange={event => setDraft({ ...draft, candidate_preedit_style: event.target.value as Preferences["candidate_preedit_style"] })}>
          <option value="pinyin">显示拼音</option><option value="empty">隐藏</option>
        </select></label></div>
        <div className="section"><label className="section-header"><span className="section-title">每页候选数量</span><select aria-label="每页候选数量" value={draft.candidate_page_size} onChange={event => setDraft({ ...draft, candidate_page_size: Number(event.target.value) })}>
          {Array.from({ length: 9 }, (_, index) => index + 1).map(size => <option key={size} value={size}>{size}</option>)}
        </select></label></div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "dictionary"} aria-label="词库">
        {client.dictionary && <div className="section quick-phrase-manager" role="region" aria-label="快捷短语管理">
          <div className="section-header"><span className="section-title">本地词库管理<small>查询、新增、编辑、导入、导出和删除 Engine 用户词库。导入支持标准、Windows TSV、Rime 和纯汉字自动注音。</small></span><span><button type="button" className="secondary" disabled={phraseBusy} onClick={() => void loadPhrases(dictionaryKind, 0)}>查询</button> <button type="button" className="secondary" disabled={phraseBusy} onClick={() => setPhraseForm({ key: "", value: "", weight: 100000, previous: null })}>新增词条</button> <button type="button" className="secondary" disabled={phraseBusy || dictionaryFormat === "hans"} onClick={() => void exportPhrases()}>导出</button><label className="secondary">导入<input hidden type="file" accept=".txt,.tsv,.yaml,.yml,text/plain" disabled={phraseBusy} onChange={event => { const file = event.target.files?.[0]; if (file) { const name = file.name.toLowerCase(); if (name.endsWith(".yaml") || name.endsWith(".yml")) setDictionaryFormat("rime"); void importPhrases(file); } event.currentTarget.value = ""; }} /></label></span></div>
          <div className="dictionary-manager-controls"><label>词库 <select aria-label="本地词库类型" value={dictionaryKind} disabled={phraseBusy} onChange={event => { const kind = event.target.value as LocalDictionaryKind; setDictionaryKind(kind); if (kind !== "pinyin" && dictionaryFormat === "hans") setDictionaryFormat("standard"); setPhrases([]); void loadPhrases(kind); }}>{localDictionaryKinds.map(([kind, label]) => <option key={kind} value={kind}>{label}</option>)}</select></label><label>文件格式 <select aria-label="本地词库文件格式" value={dictionaryFormat} disabled={phraseBusy} onChange={event => setDictionaryFormat(event.target.value as LocalDictionaryFormat)}><option value="standard">标准 TSV</option><option value="windows">Windows TSV</option><option value="rime">Rime userdb / dict.yaml</option>{dictionaryKind === "pinyin" && <option value="hans">汉字自动注音（仅导入）</option>}</select></label><label>编码前缀 <input value={phraseSearch} placeholder="留空查看全部" onChange={event => setPhraseSearch(event.target.value)} /></label></div>
          {phraseError && <p role="alert" className="error">{phraseError}</p>}
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
            <div className="skin-card-preview toolbar-settings-preview" data-preview-theme={toolbarPreviewTheme}>
              <SkinToolbarPreview preferences={floatingToolbar} />
            </div>
          </div>
        </div>
        <div className="section floating-toolbar-appearance">
          <label className="section-header"><span className="section-title">工具栏缩放<small>相对系统 DPI 的额外缩放，不改变系统显示缩放</small></span><select aria-label="工具栏缩放" value={floatingToolbar.scale_percent} onChange={event => setDraft({ ...draft, floating_toolbar: { ...floatingToolbar, scale_percent: Number(event.target.value) as FloatingToolbarPreferences["scale_percent"] } })}>{floatingToolbarScales.map(value => <option key={value} value={value}>{value}%</option>)}</select></label>
          <div className="input-option-divider" />
          <label className="section-header"><span className="section-title">图标尺寸<small>图标基准大小（像素），再乘以上方缩放</small></span><select aria-label="图标尺寸" value={floatingToolbar.font_size} onChange={event => setDraft({ ...draft, floating_toolbar: { ...floatingToolbar, font_size: Number(event.target.value) as FloatingToolbarPreferences["font_size"] } })}>{floatingToolbarFontSizes.map(value => <option key={value} value={value}>{value}</option>)}</select></label>
        </div>
        <div className="section floating-toolbar-components">
          <div className="section-title">工具栏组件<small>勾选要显示在悬浮工具栏中的功能</small></div>
          <div className="floating-toolbar-component-list">
            <label className="check-option floating-toolbar-required-option"><input type="checkbox" checked disabled /><span>中英文切换</span><span className="floating-toolbar-required-label">始终显示</span></label>
            {floatingToolbarOptions.map(([key, label]) => <div key={key}><div className="input-option-divider" /><label className="check-option"><input type="checkbox" checked={floatingToolbar[key]} onChange={event => setDraft({ ...draft, floating_toolbar: { ...floatingToolbar, [key]: event.target.checked } })} /><span>{label}</span></label></div>)}
          </div>
        </div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "input"} aria-label="输入">
        <div className="section"><label className="section-header"><span className="section-title">默认输入状态<small>新焦点会话开始时使用的中文或英文状态</small></span><select aria-label="默认输入状态" value={draft.default_ime_mode ?? "chinese"} onChange={event => setDraft({ ...draft, default_ime_mode: event.target.value as Preferences["default_ime_mode"] })}><option value="chinese">中文</option><option value="english">英文</option></select></label></div>
        {linuxPlatform && <div className="section"><label className="section-header"><span className="section-title">中英文状态范围<small>应用范围只影响当前输入上下文；全局范围在 Linux 输入法会话之间保持同一状态</small></span><select aria-label="中英文状态范围" value={draft.ime_mode_scope ?? "app"} onChange={event => setDraft({ ...draft, ime_mode_scope: event.target.value as Preferences["ime_mode_scope"] })}><option value="app">按应用</option><option value="global">全局</option></select></label></div>}
        <div className="section" role="group" aria-labelledby="input-mode-title">
          <div className="section-title" id="input-mode-title">输入模式</div>
          <div className="input-setting-description">切换中文或日文输入，并保留各模式上次选择的方案</div>
          <div className="input-option-content input-mode-options">
            <label className="radio-option"><input type="radio" name="input-mode" value="chinese" checked={draft.scheme !== "japanese"} onChange={() => setDraft({ ...draft, scheme: draft.last_chinese_scheme ?? "quanpin" })} /><span>中文</span></label>
            <div className="input-option-divider" />
            <label className="radio-option"><input type="radio" name="input-mode" value="japanese" checked={draft.scheme === "japanese"} onChange={() => setDraft({ ...draft, last_chinese_scheme: draft.scheme === "japanese" ? draft.last_chinese_scheme : draft.scheme, scheme: "japanese" })} /><span>日文</span></label>
          </div>
        </div>
        <div className="section" role="group" aria-labelledby="input-scheme-title" hidden={draft.scheme === "japanese"}>
          <div className="section-title" id="input-scheme-title">输入方案</div>
          <div className="input-option-content">
            {([["quanpin", "全拼"], ["shuangpin", "双拼"], ["wubi", "五笔"]] as const).map(([scheme, label], index) => <div className="input-option-item" key={scheme}>
              {index > 0 && <div className="input-option-divider" />}
              <label className="radio-option"><input type="radio" name="input-scheme" value={scheme} checked={draft.scheme === scheme} onChange={() => setDraft({ ...draft, scheme, last_chinese_scheme: scheme })} /><span>{label}</span></label>
            </div>)}
          </div>
        </div>
        <div className="section" hidden={draft.scheme === "japanese"}><label className="section-header"><span className="section-title">双拼方案</span><select value={draft.shuangpin_profile} onChange={event => setDraft({ ...draft, shuangpin_profile: event.target.value as Preferences["shuangpin_profile"] })}>
          <option value="xiaohe">小鹤双拼</option><option value="ziranma">自然码双拼</option>
          <option value="shoudao">首道双拼</option><option value="microsoft">微软双拼</option>
        </select></label></div>
        <div className="section" hidden={draft.scheme === "japanese"}><label className="section-header"><span className="section-title">五笔方案</span><select value="wubi86" onChange={() => {}}><option value="wubi86">86 五笔</option></select></label></div>
        <div className="section" role="group" aria-labelledby="japanese-scheme-title" hidden={draft.scheme !== "japanese"}>
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
        <div className="section"><label className="section-header"><span className="section-title">云联想<small>通过已配置的 Linux provider socket 请求额外候选</small></span><input className="toggle" type="checkbox" checked={cloudCandidates} onChange={event => setDraft({ ...draft, cloud_candidates: event.target.checked })} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">候选翻译<small>为当前候选请求翻译结果并显示在候选行</small></span><input className="toggle" type="checkbox" checked={candidateTranslations} onChange={event => setDraft({ ...draft, candidate_translations: event.target.checked })} /></label>
          <div className="input-option-divider" />
          <label className="section-header"><span className="section-title">目标语言</span><select aria-label="候选翻译目标语言" disabled={!candidateTranslations} value={translationTargetLanguage} onChange={event => setDraft({ ...draft, translation_target_language: event.target.value as Preferences["translation_target_language"] })}>{translationLanguages.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
        </div>
        <div className="section" role="group" aria-label="自定义翻译服务">
          <label className="section-header"><span className="section-title">自定义翻译服务<small>通过 Linux provider 使用兼容 DeepLX 的 HTTPS 服务</small></span><input aria-label="自定义翻译服务" className="toggle" type="checkbox" checked={customTranslation.enabled} onChange={event => setDraft({ ...draft, custom_translation: { ...customTranslation, enabled: event.target.checked } })} /></label>
          <div className="input-option-divider" />
          <label className="section-header"><span className="section-title">翻译 Endpoint</span><input aria-label="自定义翻译 Endpoint" type="url" value={customTranslation.endpoint} disabled={!customTranslation.enabled} onChange={event => setDraft({ ...draft, custom_translation: { ...customTranslation, endpoint: event.target.value } })} placeholder="https://example.com/translate" /></label>
          <div className="input-option-divider" />
          <label className="section-header"><span className="section-title">API Key</span><input aria-label="自定义翻译 API Key" type="password" value={customTranslation.api_key} disabled={!customTranslation.enabled} onChange={event => setDraft({ ...draft, custom_translation: { ...customTranslation, api_key: event.target.value } })} /></label>
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
        {linuxPlatform && <div className="section" role="group" aria-label="Linux 输入模式切换快捷键">
          <div className="section-title">Linux 输入模式切换</div>
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
        {linuxPlatform && <div className="section" role="group" aria-label="Linux 面板快捷键">
          <div className="section-title">Linux 面板快捷键</div>
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
        <div className="section shortcut-section">
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
        </div>
        {linuxPlatform && client.restartInputMethod && <div className="section shortcut-section">
          <div className="section-title">输入法服务</div>
          <small>IBus 配置支持热重载；需要重新启动输入法服务时可使用此按钮。</small>
          <div className="service-action-row">
            <span>立即重启输入法服务</span>
            <HostActionButton action={client.restartInputMethod} label="重启" success="已发送重启请求。" error="重启输入法服务失败，请稍后重试。" />
          </div>
        </div>}
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "tools"} aria-label="实用功能">
        <div className="section"><label className="section-header"><span className="section-title">剪贴板管理<small>开启后记录复制的文本；关闭后立即清空已保存记录，且只记录文本类型。</small></span><input aria-label="剪贴板管理" className="toggle" type="checkbox" checked={clipboardHistory} onChange={event => { setDraft({ ...draft, clipboard_history: event.target.checked }); if (!event.target.checked) { void client.clipboard?.clear(); setClipboardEntries([]); } }} /></label>
          {client.clipboard?.sync && <button type="button" className="secondary" disabled={!clipboardHistory} onClick={() => void client.clipboard!.sync!().then(setClipboardEntries)}>从系统剪贴板同步</button>}
          {client.clipboard?.list && <div className="clipboard-list" aria-label="剪贴板历史">{clipboardEntries.length === 0 ? <small>暂无历史记录</small> : clipboardEntries.map(entry => <div className="clipboard-row" key={entry}><span>{entry}</span>{client.clipboard?.copy && <button type="button" className="secondary" onClick={() => void client.clipboard!.copy!(entry)}>重新复制</button>}</div>)}</div>}
          {client.openCloudClipboard && <button type="button" className="secondary" onClick={() => void openPanel(client.openCloudClipboard)}>打开云剪贴板</button>}
          {client.openCloudDictionary && <button type="button" className="secondary" onClick={() => void openPanel(client.openCloudDictionary)}>打开云词典</button>}
        </div>
        {localModeRows.map(([key, label, description]) => <div className="section" key={key}>
          <label className="section-header"><span className="section-title">{label}<small>{description}</small></span><input className="toggle" type="checkbox" checked={localModes[key]} onChange={event => setDraft({ ...draft, local_modes: { ...localModes, [key]: event.target.checked } })} /></label>
        </div>)}
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "help"} aria-label="帮助">
        <div className="section document-page help-document">
          <p>{linuxPlatform ? "水杉输入法是一款 Linux 桌面环境下的中文输入法，通过 IBus 接入 GTK、Qt 等应用。" : "水杉输入法是一款 Windows 平台的中文输入法。目前支持 Windows 11/Windows 10 平台。"}</p>
          <div className="document-subsection"><div className="section-title">快速上手</div><p>{linuxPlatform ? "安装并启动 IBus 宿主后，在系统设置的输入法列表中添加水杉输入法，再使用桌面环境提供的输入法切换快捷键切换。默认是全拼输入法。" : "安装输入法后，可以使用 Win + Space 快捷键切换到水杉输入法。默认是全拼输入法。"}</p></div>
          <div className="document-subsection"><div className="section-title">基本功能</div>
            <p>支持全拼、双拼和五笔。可以在设置窗口下的输入功能分区进行切换。全拼和双拼均支持辅助码，辅助码方案目前支持自然码辅助码、蓝天小雨点、首右 2.0、首右 plus 和小鹤。</p>
            <p>{linuxPlatform ? "语音识别和云联想由用户自行管理的 provider 提供，设置页只保存行为选项，不保存或转发 provider 的凭据。" : "语音识别和 AI 联想需要自行填入 API 和 token。云联想目前支持谷歌的云接口，请注意网络问题。"}</p>
            <p>更多功能欢迎自由探索～</p>
          </div>
        </div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "about"} aria-label="关于">
        <div className="section document-hero about-hero"><div className="about-mark"><img src={logo} alt="水杉 IME" /></div><div><div className="document-eyebrow">Metasequoia IME</div><div className="document-hero-title">水杉 IME</div><p>{linuxPlatform ? "为 Linux 桌面输入体验打造的开放中文输入法。" : "为现代 Windows 桌面体验打造的开放中文输入法。"}</p></div></div>
        <div className="section about-links">
          <div className="about-link-row about-version-row"><div><div className="about-link-title">当前版本</div><div className="about-version">v{appVersion}</div>{updateStatus && <p className="about-update-status" role="status">{updateStatus}</p>}</div><button type="button" className="secondary about-update-button" disabled={updateBusy} onClick={() => void checkForUpdate()}>{updateBusy ? "正在检查…" : "检查更新"}</button></div>
          {availableUpdate && <div className="about-update-result"><p>水杉 IME v{availableUpdate.version.display} 已发布。</p>{installerTrust?.warning && <p className="about-update-warning">{installerTrust.warning}</p>}{installerTrust?.verify && <p>下载后请核对 SHA256：<code>{installerTrust.verify.sha256}</code></p>}<button type="button" className="secondary" onClick={() => void openExternalUrl(availableUpdate.releaseUrl)}>前往下载</button></div>}
          <button type="button" className="about-link-row about-document-link" onClick={() => void openExternalUrl(platformLicenseUrl)}><span className="about-link-title">开源许可协议</span><span aria-hidden="true">↗</span></button>
          {!linuxPlatform && <button type="button" className="about-link-row about-document-link" onClick={() => void openExternalUrl(privacyUrl)}><span className="about-link-title">隐私政策</span><span aria-hidden="true">↗</span></button>}
        </div>
        <div className="section" role="group" aria-label="诊断日志">
          <label className="section-header"><span className="section-title">Server 端日志<small>排查 Server 通信和输入延迟时开启。记录慢请求阶段、候选窗、悬浮工具栏、菜单、焦点会话和通信状态，不记录按键、输入内容或候选文本。</small></span><input aria-label="Server 端日志" className="toggle" type="checkbox" checked={diagnosticLog.server} onChange={event => setDraft({ ...draft, diagnostic_log: { ...diagnosticLog, server: event.target.checked } })} /></label>
          <div className="input-option-divider" />
          <label className="section-header"><span className="section-title">TSF 端日志<small>排查应用内预编辑和输入延迟时开启。日志在内存中限量缓冲，并通过独立管道批量汇总，不记录按键、输入内容或候选文本。</small></span><input aria-label="TSF 端日志" className="toggle" type="checkbox" checked={diagnosticLog.tsf} onChange={event => setDraft({ ...draft, diagnostic_log: { ...diagnosticLog, tsf: event.target.checked } })} /></label>
        </div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "screen-keyboard"} aria-label="屏幕键盘">
        <div className="section"><label className="section-header"><span className="section-title">屏幕键盘主题<small>覆盖全局主题；桌面屏幕键盘支持此设置</small></span><select aria-label="屏幕键盘主题" value={draft.screen_keyboard_theme ?? "follow"} onChange={event => setDraft({ ...draft, screen_keyboard_theme: event.target.value as SurfaceTheme })}><option value="follow">跟随全局</option><option value="dark">深色</option><option value="light">浅色</option></select></label></div>
        <div className="section" role="group" aria-labelledby="touch-keyboard-spacing-title">
          <div className="section-title" id="touch-keyboard-spacing-title">触屏键盘间距<small>与 Apple 键盘一致，只改变触屏键位外观，不改变输入方案或 Engine 组合状态</small></div>
          <label className="section-header"><span className="section-title">按键间距 <small>{(touchKeySpacingTenths / 10).toFixed(1)} dp</small></span><input aria-label="按键间距" type="range" min="30" max="60" step="1" value={touchKeySpacingTenths} onChange={event => setDraft({ ...draft, touch_key_spacing_tenths: Number(event.target.value) })} /></label>
          <div className="input-option-divider" />
          <label className="section-header"><span className="section-title">行间距 <small>{(touchRowSpacingTenths / 10).toFixed(1)} dp</small></span><input aria-label="行间距" type="range" min="40" max="100" step="1" value={touchRowSpacingTenths} onChange={event => setDraft({ ...draft, touch_row_spacing_tenths: Number(event.target.value) })} /></label>
          <div className="input-option-divider" />
          <label className="section-header"><span className="section-title">顶部语音入口 <small>在触屏键盘工具栏直接打开最近一次语音结果</small></span><input aria-label="顶部语音入口" className="toggle" type="checkbox" checked={draft.touch_voice_shortcut ?? false} onChange={event => setDraft({ ...draft, touch_voice_shortcut: event.target.checked })} /></label>
        </div>
        <div className="section panel-launch-card">
          <div className="section-header panel-launch-row"><span className="section-title">打开屏幕键盘<small>使用鼠标或触控方式输入文字与快捷按键</small></span><button type="button" className="secondary panel-open-button" disabled={!client.openScreenKeyboard} onClick={() => void openPanel(client.openScreenKeyboard)}>打开</button></div>
          <div className="panel-preview screen-keyboard-preview" aria-label="屏幕键盘预览"><div className="panel-preview-label">预览</div><ScreenKeyboardPreview theme={keyboardPreviewTheme} /></div>
        </div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "handwriting"} aria-label="手写识别板">
        <div className="section panel-launch-card">
          <div className="section-header panel-launch-row"><span className="section-title">打开手写识别板<small>使用鼠标或触控方式手写输入，自动识别候选汉字</small></span><button type="button" className="secondary panel-open-button" disabled={!client.openHandwriting} onClick={() => void openPanel(client.openHandwriting)}>打开</button></div>
          <div className="panel-preview handwriting-preview" aria-label="手写识别板预览"><div className="panel-preview-label">预览</div><div className="handwriting-mock"><div className="handwriting-canvas"><span className="handwriting-stroke">水</span></div><div className="handwriting-candidates"><span>水</span><span>永</span><span>木</span><span>未</span></div></div></div>
        </div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "voice"} aria-label="语音输入">
        <div className="section panel-launch-card"><div className="section-header panel-launch-row"><span className="section-title">打开语音输入<small>录音和识别由已配置的 Linux provider 服务完成</small></span><button type="button" className="secondary panel-open-button" disabled={!client.openVoice} onClick={() => void openPanel(client.openVoice)}>打开</button></div><p className="panel-inline-note">没有 provider 时可继续使用 IBus 属性中的入口；服务负责录音、模型和凭据。</p></div>
        <div className="section"><label className="section-header"><span className="section-title">语音输入<small>使用语音识别将录音转换为文字</small></span><input aria-label="启用语音输入" className="toggle" type="checkbox" checked={voiceInput.enabled} onChange={event => updateVoice({ enabled: event.target.checked })} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">识别服务</span><select aria-label="识别服务" value={String(voiceInput.asr_provider)} onChange={event => updateVoice({ asr_provider: event.target.value })}><option value="local_whisper">本地 Whisper</option><option value="cloud">云端服务</option><option value="doubao">豆包</option><option value="siliconflow">SiliconFlow</option></select></label></div>
        <div className="section"><label className="section-header"><span className="section-title">识别语言</span><input aria-label="识别语言" value={voiceInput.language} onChange={event => updateVoice({ language: event.target.value })} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">识别模型<small>由 provider 服务选择对应模型</small></span><input aria-label="识别模型" value={voiceInput.asr_model ?? ""} onChange={event => updateVoice({ asr_model: event.target.value })} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">Doubao 资源 ID<small>仅由 Doubao provider 使用</small></span><input aria-label="Doubao 资源 ID" value={voiceInput.asr_resource_id ?? ""} onChange={event => updateVoice({ asr_resource_id: event.target.value })} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">流式预编辑<small>provider 支持时显示实时识别片段</small></span><input aria-label="流式预编辑" className="toggle" type="checkbox" checked={voiceInput.stream_inline_preedit === true} onChange={event => updateVoice({ stream_inline_preedit: event.target.checked })} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">结果提交策略<small>由当前桌面宿主决定如何把识别结果交给前台窗口</small></span><select aria-label="结果提交策略" value={voiceInput.commit_mode ?? "tsf"} onChange={event => updateVoice({ commit_mode: event.target.value as VoiceInputPreferences["commit_mode"] })}><option value="tsf">输入法会话</option><option value="sendinput">系统按键</option><option value="ctrl_v">剪贴板粘贴</option></select></label></div>
        <div className="section"><div className="section-title">Linux provider 行为<small>这些选项会随请求传给用户管理的语音服务，不包含凭据</small></div>
          {([[
            "sound_enabled", "语音提示音", true,
          ], [
            "start_sound", "开始录音提示音", true,
          ], [
            "end_sound", "结束录音提示音", true,
          ], [
            "mute_system_audio", "录音时静音其他音频", false,
          ]] as const).map(([key, label, enabledByDefault]) => <label className="section-header" key={key}><span className="section-title">{label}</span><input aria-label={label} className="toggle" type="checkbox" checked={enabledByDefault ? voiceInput[key] !== false : voiceInput[key] === true} onChange={event => updateVoice({ [key]: event.target.checked })} /></label>)}
        </div>
        {voiceInput.asr_provider === "doubao" && <div className="section"><div className="section-title">豆包识别选项<small>由 Linux provider 服务应用</small></div>
          {([['doubao_enable_itn', '数字格式化', true], ['doubao_enable_punc', '标点预测', true], ['doubao_enable_ddc', '语义顺滑', false]] as const).map(([key, label, enabledByDefault]) => <label className="section-header" key={key}><span className="section-title">{label}</span><input aria-label={label} className="toggle" type="checkbox" checked={enabledByDefault ? voiceInput[key] !== false : voiceInput[key] === true} onChange={event => updateVoice({ [key]: event.target.checked })} /></label>)}
          <label className="section-header"><span className="section-title">热词表 ID</span><input aria-label="热词表 ID" value={voiceInput.doubao_boosting_table_id ?? ""} onChange={event => updateVoice({ doubao_boosting_table_id: event.target.value })} /></label>
        </div>}
        <div className="section"><div className="section-title">文本润色 provider<small>识别结果可交给用户管理的服务润色</small></div>
          <label className="section-header"><span className="section-title">启用润色</span><input aria-label="启用文本润色" className="toggle" type="checkbox" checked={voiceInput.polish_text === true || voiceInput.polish_enabled === true} onChange={event => updateVoice({ polish_text: event.target.checked, polish_enabled: event.target.checked })} /></label>
          <label className="section-header"><span className="section-title">服务提供商</span><select aria-label="文本润色服务提供商" value={voiceInput.polish_provider ?? "siliconflow"} onChange={event => updateVoice({ polish_provider: event.target.value })}><option value="siliconflow">SiliconFlow</option><option value="openai">OpenAI</option><option value="deepseek">DeepSeek</option><option value="groq">Groq</option></select></label>
          <label className="section-header"><span className="section-title">模型</span><input aria-label="文本润色模型" value={voiceInput.polish_model ?? ""} onChange={event => updateVoice({ polish_model: event.target.value })} /></label>
          <label className="section-header"><span className="section-title">润色方案</span><select aria-label="润色方案" value={voiceInput.polish_prompt_id ?? "cleanup"} onChange={event => updateVoice({ polish_prompt_id: event.target.value })}><option value="cleanup">清理口语</option><option value="faithful">忠实原文</option><option value="zh2en">中译英</option><option value="casual">自然口语</option><option value="custom">自定义提示词</option></select></label>
          <label className="section-header"><span className="section-title">润色提示词</span><textarea aria-label="润色提示词" value={voiceInput.polish_prompt ?? ""} onChange={event => updateVoice({ polish_prompt: event.target.value })} /></label>
          <label className="section-header"><span className="section-title">自定义提示词一</span><textarea aria-label="自定义提示词一" value={voiceInput.polish_prompt_custom_1 ?? ""} onChange={event => updateVoice({ polish_prompt_custom_1: event.target.value })} /></label>
          <label className="section-header"><span className="section-title">自定义提示词二</span><textarea aria-label="自定义提示词二" value={voiceInput.polish_prompt_custom_2 ?? ""} onChange={event => updateVoice({ polish_prompt_custom_2: event.target.value })} /></label>
          <label className="section-header"><span className="section-title">自定义提示词三</span><textarea aria-label="自定义提示词三" value={voiceInput.polish_prompt_custom_3 ?? ""} onChange={event => updateVoice({ polish_prompt_custom_3: event.target.value })} /></label>
        </div>
        <div className="section"><div className="section-title">Linux IBus 快捷键<small>在当前输入上下文中切换语音录音；没有 provider 时快捷键不会拦截编辑器输入</small></div>
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
        </div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "ai"} aria-label="AI 辅助">
        <div className="section"><label className="section-header"><span className="section-title">启用 AI 辅助<small>为拼音联想和 Android 选中文字润色提供共享配置</small></span><input aria-label="启用 AI 辅助" className="toggle" type="checkbox" checked={ai.enabled} onChange={event => updateAi({ enabled: event.target.checked })} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">服务提供商</span><select aria-label="AI 服务提供商" value={ai.provider} onChange={event => updateAi({ provider: event.target.value })}><option value="deepseek">DeepSeek</option><option value="openai">OpenAI</option><option value="siliconflow">SiliconFlow</option><option value="groq">Groq</option></select></label></div>
        <div className="section"><label className="section-header"><span className="section-title">模型</span><input aria-label="AI 模型" value={ai.model} onChange={event => updateAi({ model: event.target.value })} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">接口地址</span><input aria-label="AI 接口地址" type="url" value={ai.endpoint} onChange={event => updateAi({ endpoint: event.target.value })} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">API Token<small>{aiOrigin ? `只用于 ${aiOrigin}` : "请先填写有效的 HTTPS 接口地址"}</small></span><input aria-label="AI API Token" type="password" autoComplete="off" disabled={!aiOrigin} value={aiToken} onChange={event => updateAiToken(event.target.value)} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">候选数量</span><input aria-label="AI 候选数量" type="number" min="1" max="10" value={ai.candidate_limit} onChange={event => updateAi({ candidate_limit: Math.max(1, Math.min(10, Number(event.target.value) || 3)) })} /></label></div>
        <div className="section"><label className="section-title">AI 润色提示词<small>Android 只发送选中文字，并要求服务仅返回修改结果</small></label><textarea aria-label="AI 润色提示词" value={ai.prompt ?? defaultAiAssistant.prompt} onChange={event => updateAi({ prompt: event.target.value })} /></div>
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
    {page !== "typing-statistics" && <button className="secondary" disabled={busy} onClick={() => {
      if (!dirty || window.confirm("重新读取会放弃尚未保存的修改，是否继续？")) void reload();
    }}>重新读取</button>}
  </div></main></div></div>;
}
