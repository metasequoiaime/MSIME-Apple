import { useEffect, useRef, useState } from "react";
import { HostActionButton } from "./HostActionButton";
import type { KeyboardEvent } from "react";

export type HelpcodeSchema = "lantian" | "ziranma" | "shouyou2_0" | "shouyouplus" | "xiaohe";
export type HelpcodePreferences = { enabled: boolean; schema: HelpcodeSchema };
const defaultHelpcode: HelpcodePreferences = { enabled: true, schema: "ziranma" };
const helpcodeSchemas: [HelpcodeSchema, string][] = [["lantian", "蓝天小雨点"], ["ziranma", "自然码"], ["shouyou2_0", "首右2.0"], ["shouyouplus", "首右plus"], ["xiaohe", "小鹤"]];
const pages = [
  { id: "appearance", title: "外观", icon: new URL("./assets/appearance.svg", import.meta.url).href },
  { id: "skin", title: "皮肤", icon: new URL("./assets/appearance.svg", import.meta.url).href },
  { id: "about", title: "关于", icon: new URL("./assets/msime.svg", import.meta.url).href },
  { id: "feedback", title: "反馈", icon: new URL("./assets/utilities.svg", import.meta.url).href },
  { id: "help", title: "帮助", icon: new URL("./assets/helpcode.svg", import.meta.url).href },
  { id: "screen_keyboard", title: "屏幕键盘", icon: new URL("./assets/input.svg", import.meta.url).href },
  { id: "voice_input", title: "语音输入", icon: new URL("./assets/input.svg", import.meta.url).href },
  { id: "handwriting", title: "手写识别", icon: new URL("./assets/input.svg", import.meta.url).href },
  { id: "ai_assistant", title: "AI 辅助", icon: new URL("./assets/utilities.svg", import.meta.url).href },
  { id: "floating_toolbar", title: "悬浮工具栏", icon: new URL("./assets/utilities.svg", import.meta.url).href },
  { id: "input", title: "输入", icon: new URL("./assets/input.svg", import.meta.url).href },
  { id: "helpcode", title: "辅助码", icon: new URL("./assets/helpcode.svg", import.meta.url).href },
  { id: "dictionary", title: "词库", icon: new URL("./assets/utilities.svg", import.meta.url).href },
  { id: "cloud_dictionary", title: "云词库", icon: new URL("./assets/utilities.svg", import.meta.url).href },
  { id: "shortcuts", title: "快捷键", icon: new URL("./assets/shortcut.svg", import.meta.url).href },
  { id: "tools", title: "实用功能", icon: new URL("./assets/utilities.svg", import.meta.url).href },
] as const;
const logo = new URL("./assets/msime.svg", import.meta.url).href;

export type Preferences = {
  mixed_input?: MixedInputPreferences;
  frequency?: FrequencyPreferences;
  word_character?: { enabled: boolean; keys: "brackets" | "minus_equal" };
  navigation?: NavigationPreferences;
  scheme: "quanpin" | "shuangpin" | "wubi" | "japanese";
  default_ime_mode?: "chinese" | "english";
  last_chinese_scheme?: "quanpin" | "shuangpin" | "wubi" | null;
  shuangpin_profile: "xiaohe" | "ziranma" | "shoudao" | "microsoft";
  candidate_page_size: number;
  candidate_font_size?: number;
  candidate_preedit_font_size?: number;
  candidate_text_color?: string | null;
  candidate_font_family?: string;
  candidate_fallback_fonts?: string[];
  learning: boolean;
  autocorrect?: boolean;
  quanpin_helpcode?: HelpcodePreferences;
  shuangpin_helpcode?: HelpcodePreferences;
  chinese_punctuation: boolean;
  smart_punctuation?: boolean;
  smart_punctuation_repeat?: boolean;
  paired_punctuation?: boolean;
};
export type VoiceInputPreferences = { enabled: boolean; sound_enabled: boolean; start_sound: boolean; end_sound: boolean; mute_system_audio: boolean; language: string; commit_mode: string; asr_provider: string; asr_app_key: string; asr_token: string; asr_endpoint: string; asr_model: string; polish_enabled: boolean; polish_provider: string; polish_token: string; polish_endpoint: string; polish_model: string; polish_prompt_id: string; polish_prompt: string; hotkey_ralt: boolean; hotkey_ctrl_win: boolean; hotkey_rctrl_ralt: boolean; hotkey_hold_space_lock: boolean; hotkey_ctrl_f9: boolean; doubao_enable_itn: boolean; doubao_enable_punc: boolean; doubao_enable_ddc: boolean; doubao_boosting_table_id: string };
const defaultVoiceInput: VoiceInputPreferences = { enabled: true, sound_enabled: true, start_sound: true, end_sound: true, mute_system_audio: false, language: "zh-cn", commit_mode: "tsf", asr_provider: "doubao", asr_app_key: "", asr_token: "", asr_endpoint: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async", asr_model: "", polish_enabled: false, polish_provider: "siliconflow", polish_token: "", polish_endpoint: "https://api.siliconflow.cn/v1/chat/completions", polish_model: "Qwen/Qwen3-8B", polish_prompt_id: "cleanup", polish_prompt: "", hotkey_ralt: true, hotkey_ctrl_win: false, hotkey_rctrl_ralt: false, hotkey_hold_space_lock: true, hotkey_ctrl_f9: true, doubao_enable_itn: true, doubao_enable_punc: true, doubao_enable_ddc: false, doubao_boosting_table_id: "" };
const voicePromptPresets: Record<string, string> = { cleanup: "去掉口语填充词和无意义重复，修正错别字并补充标点。只输出整理后的文本。", faithful: "忠实保留原句顺序和语气，只做纠错、格式整理和标点补全。只输出校对后的文本。", zh2en: "将语音转写内容翻译成自然、专业的英文，保留原意和顺序。只输出译文。", casual: "整理口语表达，保留自然语气，删除明显重复和犹豫。只输出整理后的文本。" };
export type AiAssistantPreferences = { enabled: boolean; provider: string; model: string; token: string; tokens?: Record<string, string>; endpoint: string; candidate_limit: number; prompt_id: string; prompt: string; prompt_custom_1?: string; prompt_custom_2?: string; prompt_custom_3?: string };
const aiProviderDefaults: Record<string, { model: string; endpoint: string }> = { deepseek: { model: "deepseek-v4-flash", endpoint: "https://api.deepseek.com/chat/completions" }, openai: { model: "gpt-4o-mini", endpoint: "https://api.openai.com/v1/chat/completions" }, siliconflow: { model: "Qwen/Qwen3-8B", endpoint: "https://api.siliconflow.cn/v1/chat/completions" }, groq: { model: "llama-3.3-70b-versatile", endpoint: "https://api.groq.com/openai/v1/chat/completions" } };
const defaultAiAssistant: AiAssistantPreferences = { enabled: false, provider: "deepseek", model: aiProviderDefaults.deepseek.model, token: "", tokens: {}, endpoint: aiProviderDefaults.deepseek.endpoint, candidate_limit: 3, prompt_id: "custom_1", prompt: "", prompt_custom_1: "", prompt_custom_2: "", prompt_custom_3: "" };
const defaultCustomTranslation = { enabled: false, endpoint: "", api_key: "" };
export type ExternalSkinSummary = { id: string; name: string; version?: string; author?: string; description?: string; compatible: boolean; issues?: string[] };
export type Snapshot = { format_version: number; revision: number; preferences: Preferences };
export type MixedInputPreferences = { english: boolean; minimum_prefix: number; emoji: boolean; kaomoji: boolean };
const defaultMixedInput: MixedInputPreferences = { english: true, minimum_prefix: 2, emoji: false, kaomoji: false };
export type FrequencyPreferences = { mode: "disabled" | "pin" | "halve" | "linear" | "promote"; trigger_count: number; linear_step: number };
const defaultFrequency: FrequencyPreferences = { mode: "promote", trigger_count: 1, linear_step: 1 };
export type NavigationPreferences = { minus_equal: boolean; comma_period: boolean; brackets: boolean; tab: boolean; page_up_down: boolean; arrows: boolean };
const defaultNavigation: NavigationPreferences = { minus_equal: true, comma_period: true, brackets: false, tab: true, page_up_down: true, arrows: true };
const defaultWordCharacter = { enabled: false, keys: "brackets" as const };
const navigationOptions: [keyof NavigationPreferences, string][] = [["minus_equal", "- / ="], ["comma_period", ", / ."], ["brackets", "[ / ]"], ["tab", "Shift+Tab / Tab"], ["page_up_down", "PageUp / PageDown"], ["arrows", "上 / 下（移动候选项）"]];
export interface SettingsClient {
  load(): Promise<Snapshot>;
  save(revision: number, preferences: Preferences): Promise<Snapshot>;
  dictionary?: DictionaryClient;
  cloudDictionary?: CloudDictionaryClient;
  cloudClipboard?: CloudClipboardClient;
  screen_keyboard?: { open(): Promise<void> };
  handwriting?: { open(): Promise<void> };
  clipboard?: { clear(): Promise<void>; copy?(text: string): Promise<void>; list?(): Promise<string[]>; sync?(): Promise<string[]> };
  about?: { openExternalUrl(url: string): Promise<void> };
  update?: { check(): Promise<{ found: boolean; version?: string; installer_name?: string; installer_sha256?: string; signed?: boolean }> };
  diagnostics?: { server(enabled: boolean): Promise<void>; tsf(enabled: boolean): Promise<void>; state?(scope: "server" | "tsf"): Promise<boolean> };
  skin?: { openDirectory(): Promise<void>; refresh(): Promise<void>; list?(): Promise<ExternalSkinSummary[]>; selected?(): Promise<string | null>; select?(id: string): Promise<void> };
  feedback?: { openExternalUrl(url: string): Promise<void> };
}
export type DictionaryEntry = { kind: "pinyin" | "wubi" | "quick_phrase" | "english"; key: string; value: string; weight: number };
export interface DictionaryClient {
  list(offset: number, limit: number): Promise<{ entries: DictionaryEntry[]; has_more: boolean }>;
  edit(previous: DictionaryEntry | null, replacement: DictionaryEntry | null, request_id: string): Promise<void>;
}
export type CloudDictionaryKind = "pinyin" | "wubi" | "quick" | "english";
export type CloudDictionaryEntry = { id: string; kind: CloudDictionaryKind; code: string; word: string; weight: number; revision: number };
export type CloudClipboardItem = { id: string; text: string; created_at: string };
export interface CloudClipboardClient { get(search: string): Promise<{ enabled: boolean; items: CloudClipboardItem[] }>; setEnabled(enabled: boolean): Promise<void>; add(text: string): Promise<void>; remove(id?: string): Promise<void>; }
export type CloudDictionaryCatalog = { entries: CloudDictionaryEntry[]; offset: number; has_more: boolean; revision: number; normalized: string };
export type CloudDictionaryChange = { revision: number; previous?: CloudDictionaryEntry; replacement?: CloudDictionaryEntry; reset?: boolean };
export type CloudCandidate = { code: string; word: string; weight: number; canonical_pinyin?: string };
export type CloudFixedPosition = { context: string; code: string; word: string; position: number };
export interface CloudDictionaryClient {
  list(kind: CloudDictionaryKind, search: string, offset: number): Promise<{ entries: CloudDictionaryEntry[]; has_more: boolean; offset: number }>;
  add(kind: CloudDictionaryKind, value: Omit<CloudDictionaryEntry, "id" | "kind" | "revision">): Promise<void>;
  update(entry: CloudDictionaryEntry, value: Omit<CloudDictionaryEntry, "id" | "kind" | "revision">): Promise<void>;
  remove(entry: CloudDictionaryEntry): Promise<void>;
  import(kind: CloudDictionaryKind, text: string, format: "standard" | "windows" | "hans"): Promise<number>;
  export(kind: CloudDictionaryKind, format: "standard" | "windows"): Promise<string>;
  catalog(kind: CloudDictionaryKind, code: string, offset: number, scheme: string, profile: string): Promise<CloudDictionaryCatalog>;
  editCatalog(entry: CloudDictionaryEntry, revision: number, replacement: { code: string; word: string; weight: number } | null): Promise<void>;
  changes(after: number, limit: number): Promise<{ changes: CloudDictionaryChange[]; next: number; has_more: boolean }>;
  candidates(query: { text: string; kind: string; scheme: string; profile: string; limit: number }): Promise<{ candidates: CloudCandidate[]; context: string; revision: number }>;
  rank(candidate: CloudCandidate, query: { text: string; kind: string; scheme: string; profile: string; limit: number }, revision: number, mode: FrequencyPreferences["mode"], step: number, trigger: number, forceTop: boolean): Promise<void>;
  fixedPositions(context: string, offset: number): Promise<{ positions: CloudFixedPosition[]; offset: number; has_more: boolean }>;
  setFixedPosition(position: CloudFixedPosition, revision: number, value: number | null): Promise<void>;
  import(kind: CloudDictionaryKind, text: string, format: "standard" | "hans"): Promise<number>;
  export(kind: CloudDictionaryKind, format: "standard" | "hans"): Promise<string>;
}

function parseFontList(text: string): string[] {
  return text.split(",").map(font => font.trim()).filter(Boolean);
}

function FallbackFontInput({ value, onChange }: { value: string[]; onChange: (fonts: string[]) => void }) {
  const serialized = JSON.stringify(value);
  const [text, setText] = useState(() => value.join(", "));
  useEffect(() => {
    // Keep unfinished separators/whitespace while typing, but honor external reloads.
    setText(current => JSON.stringify(parseFontList(current)) === serialized
      ? current : (JSON.parse(serialized) as string[]).join(", "));
  }, [serialized]);
  return <input aria-label="候选窗补充字体" value={text} onChange={event => {
    setText(event.target.value);
    onChange(parseFontList(event.target.value));
  }} />;
}

function CustomDropdown({ value, options, onChange, ariaLabel, disabled = false }: { value: string; options: [string, string][]; onChange: (value: string) => void; ariaLabel?: string; disabled?: boolean }) {
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(() => Math.max(0, options.findIndex(([option]) => option === value)));
  const optionRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const selected = options.find(([option]) => option === value) ?? options[0];
  const choose = (next: string) => { onChange(next); setOpen(false); };
  useEffect(() => { setActive(Math.max(0, options.findIndex(([option]) => option === value))); }, [value]);
  useEffect(() => { if (open) optionRefs.current[active]?.focus(); }, [open, active]);
  const onKeyDown = (event: KeyboardEvent<HTMLButtonElement>) => {
    if (event.key === "Enter" || event.key === " ") { event.preventDefault(); setOpen(current => !current); }
    else if (event.key === "Escape") setOpen(false);
    else if (event.key === "ArrowDown" || event.key === "ArrowUp") { event.preventDefault(); setOpen(true); setActive(index => (index + (event.key === "ArrowDown" ? 1 : options.length - 1)) % options.length); }
    else if (event.key === "Home" || event.key === "End") { event.preventDefault(); setOpen(true); setActive(event.key === "Home" ? 0 : options.length - 1); }
  };
  return <div className="custom-dropdown">
    <button type="button" className="dropdown-toggle" aria-label={ariaLabel} disabled={disabled} aria-haspopup="listbox" aria-expanded={open} onClick={() => setOpen(current => !current)} onKeyDown={onKeyDown}>
      {selected?.[1] ?? value}<span aria-hidden="true" className="dropdown-chevron">⌄</span>
    </button>
    {open && <div className="dropdown-menu" role="listbox" aria-label={ariaLabel} aria-activedescendant={`${ariaLabel ?? "dropdown"}-option-${active}`}>
      {options.map(([option, label], index) => <button id={`${ariaLabel ?? "dropdown"}-option-${index}`} type="button" role="option" aria-selected={option === value} className="dropdown-item" key={option} ref={element => { optionRefs.current[index] = element; }} onMouseEnter={() => setActive(index)} onKeyDown={event => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); choose(option); } else if (event.key === "Escape") { event.preventDefault(); setOpen(false); } else if (event.key === "ArrowDown" || event.key === "ArrowUp") { event.preventDefault(); setActive((index + (event.key === "ArrowDown" ? 1 : options.length - 1)) % options.length); } else if (event.key === "Home" || event.key === "End") { event.preventDefault(); setActive(event.key === "Home" ? 0 : options.length - 1); } }} onClick={() => choose(option)}>{label}</button>)}
    </div>}
  </div>;
}

function message(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === "object" && error !== null && "code" in error) {
    switch (error.code) {
      case "conflict": return "设置已在其他窗口修改。请重新读取后再保存。";
      case "invalid": return "候选数量必须为 1 到 9。";
      case "candidate_font_size_invalid": return "候选窗字号必须为 12 到 32。";
      case "candidate_text_color_invalid": return "候选文字颜色格式无效。";
      case "candidate_font_family_invalid": return "候选字体名称必须为非空 ASCII，且不超过 128 字节。";
      case "candidate_skin_invalid": return "候选窗皮肤标识无效。";
      case "frequency_invalid": return "调频触发频次和步长必须为 1 到 10。";
      case "mixed_input_invalid": return "中英混输触发字符数必须为 1 到 8。";
      case "key_conflict": return "以词定字和翻页不能使用同一组快捷键。";
      case "format": return "配置文件无法读取或版本较新，原文件已保留。";
      case "unknown_skin": return "找不到该外部皮肤，请先刷新皮肤目录。";
      case "invalid_skin": return "皮肤标识无效，未执行应用。";
      case "unavailable": return "宿主动作不可用，请确认应用组件已安装。";
    }
  }
  return "无法访问设置，请重试。原有设置不会被自动重置。";
}

export function SettingsPage({ client }: { client: SettingsClient }) {
  const [snapshot, setSnapshot] = useState<Snapshot>();
  const [draft, setDraft] = useState<Preferences>();
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [page, setPage] = useState<(typeof pages)[number]["id"]>("appearance");
  const [clipboardEntries, setClipboardEntries] = useState<string[]>([]);
  const [externalSkins, setExternalSkins] = useState<ExternalSkinSummary[]>([]);
  const [selectedSkin, setSelectedSkin] = useState<string | null>(null);
  const [skinPreviewTheme, setSkinPreviewTheme] = useState<"dark" | "light">("dark");
  const [serverDiagnostics, setServerDiagnostics] = useState(false);
  const [tsfDiagnostics, setTsfDiagnostics] = useState(false);
  const [diagnosticError, setDiagnosticError] = useState("");
  const [updateStatus, setUpdateStatus] = useState("");
  const [updateDetails, setUpdateDetails] = useState<{ digest?: string; name?: string; signed?: boolean }>();
  const [phrases, setPhrases] = useState<DictionaryEntry[]>([]);
  const [phraseBusy, setPhraseBusy] = useState(false);
  const [phraseError, setPhraseError] = useState("");
  useEffect(() => {
    const mode = draft?.settings_theme && draft.settings_theme !== "follow" ? draft.settings_theme : (draft?.theme ?? "dark");
    const resolved = mode === "system" ? (window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark") : mode;
    document.documentElement.dataset.theme = resolved;
  }, [draft?.theme]);
  useEffect(() => {
    if (selectedSkin) setDraft(current => current ? { ...current, candidate_skin: selectedSkin } : current);
  }, [selectedSkin]);
  const [phraseForm, setPhraseForm] = useState<{ key: string; value: string; weight: number; previous: DictionaryEntry | null } | null>(null);
  const [phraseSearch, setPhraseSearch] = useState("");
  const [cloudKind, setCloudKind] = useState<CloudDictionaryKind>("pinyin");
  const [cloudSearch, setCloudSearch] = useState("");
  const [cloudEntries, setCloudEntries] = useState<CloudDictionaryEntry[]>([]);
  const [cloudOffset, setCloudOffset] = useState(0);
  const [cloudHasMore, setCloudHasMore] = useState(false);
  const [cloudError, setCloudError] = useState("");
  const [cloudForm, setCloudForm] = useState<{ code: string; word: string; weight: number } | null>(null);
  const [catalogEntries, setCatalogEntries] = useState<CloudDictionaryEntry[]>([]);
  const [cloudSyncStatus, setCloudSyncStatus] = useState(0);
  async function loadCloud(offset = 0) {
    if (!client.cloudDictionary) return;
    setCloudError("");
    try { const page = await client.cloudDictionary.list(cloudKind, cloudSearch, offset); setCloudEntries(page.entries); setCloudOffset(page.offset); setCloudHasMore(page.has_more); }
    catch (reason) { setCloudError(message(reason)); }
  }
  async function syncCloud() {
    if (!client.cloudDictionary) return;
    try { const result = await client.cloudDictionary.changes(cloudSyncStatus, 100); setCloudSyncStatus(result.next); await loadCloud(cloudOffset); }
    catch (reason) { setCloudError(message(reason)); }
  }
  async function loadCatalog() {
    if (!client.cloudDictionary) return;
    try { const result = await client.cloudDictionary.catalog(cloudKind, cloudSearch, 0, "pinyin", "xiaohe"); setCatalogEntries(result.entries); }
    catch (reason) { setCloudError(message(reason)); }
  }

  useEffect(() => {
    let active = true;
    client.load().then(value => {
      if (active) { setSnapshot(value); setDraft(value.preferences); }
    }).catch(reason => { if (active) setError(message(reason)); })
      .finally(() => { if (active) setBusy(false); });
    return () => { active = false; };
  }, [client]);

  useEffect(() => {
    if (!client.clipboard?.list) return;
    void client.clipboard.list().then(setClipboardEntries).catch(() => undefined);
  }, [client, page]);

  async function reload() {
    setBusy(true); setError(""); setNotice("");
    try {
      const value = await client.load();
      setSnapshot(value); setDraft(value.preferences);
    } catch (reason) { setError(message(reason)); }
    finally { setBusy(false); }
  }

  async function save() {
    if (!draft || !snapshot) return;
    setBusy(true); setError(""); setNotice("");
    try {
      const value = await client.save(snapshot.revision, draft);
      setSnapshot(value); setDraft(value.preferences); setNotice("设置已保存。");
    } catch (reason) { setError(message(reason)); }
    finally { setBusy(false); }
  }
  async function loadPhrases() {
    if (!client.dictionary) return;
    setPhraseBusy(true); setPhraseError("");
    try {
      const page = await client.dictionary.list(0, 100);
      setPhrases(page.entries.filter(entry => entry.kind === "quick_phrase"));
    } catch { setPhraseError("无法读取快捷短语。"); }
    finally { setPhraseBusy(false); }
  }
  async function removePhrase(entry: DictionaryEntry) {
    if (!client.dictionary) return;
    setPhraseBusy(true); setPhraseError("");
    try { await client.dictionary.edit(entry, null, `ui-remove-${entry.key}-${entry.value}`); await loadPhrases(); }
    catch { setPhraseError("快捷短语删除失败，请稍后重试。"); }
    finally { setPhraseBusy(false); }
  }
  async function savePhrase() {
    if (!client.dictionary || !phraseForm) return;
    const replacement: DictionaryEntry = { kind: "quick_phrase", key: phraseForm.key.trim(), value: phraseForm.value, weight: phraseForm.weight };
    if (!replacement.key || !replacement.value) { setPhraseError("编码和短语不能为空。"); return; }
    setPhraseBusy(true); setPhraseError("");
    try { await client.dictionary.edit(phraseForm.previous, replacement, `${phraseForm.previous ? "ui-edit" : "ui-add"}-${replacement.key}-${replacement.value}`); setPhraseForm(null); await loadPhrases(); }
    catch { setPhraseError("快捷短语保存失败，请稍后重试。"); }
    finally { setPhraseBusy(false); }
  }
  async function importPhrases(file: File) {
    if (!client.dictionary) return;
    setPhraseBusy(true); setPhraseError("");
    try {
      const rows = (await file.text()).split(/\r?\n/).filter(Boolean);
      for (const [index, row] of rows.entries()) {
        const [key, value, weightText] = row.split("\t");
        const weight = weightText === undefined ? 0 : Number(weightText);
        if (!/^[A-Za-z]+$/.test(key ?? "") || !value || !Number.isFinite(weight) || weight < 0) throw new Error(`row ${index + 1}`);
        await client.dictionary.edit(null, { kind: "quick_phrase", key, value, weight }, `ui-import-${index}-${key}`);
      }
      await loadPhrases();
    } catch { setPhraseError("批量导入失败，请检查格式（编码<Tab>短语<Tab>权重）。"); setPhraseBusy(false); }
  }
  function exportPhrases() {
    const body = phrases.map(entry => `${entry.key}\t${entry.value}\t${entry.weight}`).join("\n");
    const url = URL.createObjectURL(new Blob([body], { type: "text/plain;charset=utf-8" }));
    const anchor = document.createElement("a"); anchor.href = url; anchor.download = "quick-phrases.txt"; anchor.click(); URL.revokeObjectURL(url);
  }

  const dirty = !!draft && !!snapshot && JSON.stringify(draft) !== JSON.stringify(snapshot.preferences);
  useEffect(() => {
    let active = true;
    if (page === "skin" && client.skin?.list) void client.skin.list().then(value => { if (active) setExternalSkins(value); }).catch(() => { if (active) setExternalSkins([]); });
    if (page === "skin" && client.skin?.selected) void client.skin.selected().then(value => { if (active) setSelectedSkin(value); }).catch(() => { if (active) setSelectedSkin(null); });
    return () => { active = false; };
  }, [client, page]);
  useEffect(() => {
    if (page !== "about" || !client.diagnostics?.state) return;
    let active = true;
    Promise.all([client.diagnostics.state("server"), client.diagnostics.state("tsf")]).then(([server, tsf]) => {
      if (active) { setServerDiagnostics(server); setTsfDiagnostics(tsf); }
    }).catch(() => undefined);
    return () => { active = false; };
  }, [client, page]);
  const openExternalUrl = (url: string) => {
    if (client.about) void client.about.openExternalUrl(url);
  };
  const openFeedbackUrl = (url: string) => {
    if (client.feedback) void client.feedback.openExternalUrl(url);
  };
  async function setDiagnostic(kind: "server" | "tsf", enabled: boolean) {
    const action = kind === "server" ? client.diagnostics?.server : client.diagnostics?.tsf;
    if (!action) return;
    setDiagnosticError("");
    try {
      await action(enabled);
      (kind === "server" ? setServerDiagnostics : setTsfDiagnostics)(enabled);
    } catch {
      setDiagnosticError("诊断日志设置失败，请重试。");
    }
  }
  const wordCharacter = draft?.word_character ?? defaultWordCharacter;
  const frequency = draft?.frequency ?? defaultFrequency;
  const mixedInput = draft?.mixed_input ?? defaultMixedInput;
  return <div className="settings-shell">
    <nav className="sidebar" aria-label="设置分类">
      <div className="sidebar-header"><img src={logo} alt="" /><span>水杉 IME</span></div>
      {pages.map(item => <button key={item.id} type="button" className={`item${page === item.id ? " active" : ""}`}
        aria-current={page === item.id ? "page" : undefined} aria-controls="settings-content" onClick={() => setPage(item.id)}>
        <span className="icon"><img src={item.icon} alt="" /></span>{item.title}
      </button>)}
      <p className="preview-label">客户端预览版</p>
    </nav>
    <main id="settings-content" aria-labelledby="page-title"><div className="content">
    <header className="content-header"><h1 id="page-title">{pages.find(item => item.id === page)!.title}</h1></header>
    {error && <p role="alert" className="error">{error}</p>}
    {notice && <p role="status" className="notice">{notice}</p>}
    {busy && !draft && <p role="status">正在读取设置…</p>}
    {draft && <form onSubmit={event => { event.preventDefault(); void save(); }}>
      <fieldset disabled={busy} hidden={page !== "appearance"} aria-label="外观">
        <div className="section"><div className="section-header"><span className="section-title">主题模式<small>设置界面和候选预览的颜色主题</small></span><CustomDropdown ariaLabel="主题模式" value={draft.theme ?? "dark"} options={[["dark", "深色"], ["light", "浅色"], ["system", "跟随系统"]]} onChange={value => setDraft({ ...draft, theme: value as Preferences["theme"] })} /></div></div>
        <div className="section"><div className="section-header"><span className="section-title">设置界面主题<small>可覆盖全局主题，仅影响当前设置界面</small></span><CustomDropdown ariaLabel="设置界面主题" value={draft.settings_theme ?? "follow"} options={[["follow", "跟随全局"], ["dark", "深色"], ["light", "浅色"]]} onChange={value => setDraft({ ...draft, settings_theme: value as Preferences["settings_theme"] })} /></div></div>
        <div className="section"><div className="section-header"><span className="section-title">候选窗口主题<small>可覆盖全局主题，仅影响候选窗口</small></span><CustomDropdown ariaLabel="候选窗口主题" value={draft.candidate_theme ?? "follow"} options={[["follow", "跟随全局"], ["dark", "深色"], ["light", "浅色"]]} onChange={value => setDraft({ ...draft, candidate_theme: value as Preferences["candidate_theme"] })} /></div></div>
        <div className="section"><div className="section-header"><span className="section-title">候选窗口皮肤<small>选择候选窗口与工具栏的内置皮肤。</small></span><CustomDropdown ariaLabel="候选窗口皮肤" value={draft.candidate_skin ?? "fluent"} options={[["fluent", "Fluent"], ["wechat", "微信绿"], ["graphite", "Graphite"], ["willow_green", "杨柳青"]]} onChange={value => setDraft({ ...draft, candidate_skin: value })} /></div></div>
        <div className="section"><label className="section-header"><span className="section-title">候选词翻译<small>允许宿主在候选窗口旁显示在线翻译结果。</small></span><input aria-label="候选词翻译" className="toggle" type="checkbox" checked={draft.candidate_translations ?? true} onChange={event => setDraft({ ...draft, candidate_translations: event.target.checked })} /></label></div>
        <div className="section"><div className="section-header"><span className="section-title">翻译目标语言<small>候选词翻译服务使用的目标语言。</small></span><CustomDropdown ariaLabel="翻译目标语言" value={draft.translation_target_language ?? "en"} options={[["en", "英语"], ["fr", "法语"], ["ja", "日语"], ["es", "西班牙语"], ["ru", "俄语"], ["de", "德语"], ["ko", "韩语"]]} onChange={value => setDraft({ ...draft, translation_target_language: value as Preferences["translation_target_language"] })} /></div></div>
        <div className="section"><label className="section-header"><span className="section-title">自定义翻译服务<small>使用兼容 DeepLX 的 HTTPS 服务翻译候选词。</small></span><input aria-label="自定义翻译服务" className="toggle" type="checkbox" checked={customTranslation.enabled} onChange={event => setDraft({ ...draft, custom_translation: { ...customTranslation, enabled: event.target.checked } })} /></label><label className="field"><span>Endpoint</span><input aria-label="自定义翻译 Endpoint" type="url" value={customTranslation.endpoint} onChange={event => setDraft({ ...draft, custom_translation: { ...customTranslation, endpoint: event.target.value } })} placeholder="https://example.com/translate" /></label><label className="field"><span>API Key</span><input aria-label="自定义翻译 API Key" type="password" value={customTranslation.api_key} onChange={event => setDraft({ ...draft, custom_translation: { ...customTranslation, api_key: event.target.value } })} /></label></div>
        <div className="section"><div className="section-header"><span className="section-title">候选项排列方式</span><CustomDropdown value={draft.candidate_layout ?? "vertical"} options={[["horizontal", "横向"], ["vertical", "纵向"]]} onChange={value => setDraft({ ...draft, candidate_layout: value as Preferences["candidate_layout"] })} /></div></div>
        <div className="section"><div className="section-header"><span className="section-title">候选窗预编辑</span><CustomDropdown value={draft.candidate_preedit_style ?? "pinyin"} options={[["pinyin", "拼音分词"], ["empty", "不显示"]]} onChange={value => setDraft({ ...draft, candidate_preedit_style: value as Preferences["candidate_preedit_style"] })} /></div></div>
        <div className="section"><div className="section-header"><span className="section-title">行内预编辑</span><CustomDropdown ariaLabel="行内预编辑" value={draft.tsf_preedit_style ?? "raw"} options={[["raw", "原始按键"], ["pinyin", "拼音分词"], ["empty", "不显示"]]} onChange={value => setDraft({ ...draft, tsf_preedit_style: value as Preferences["tsf_preedit_style"] })} /></div></div>
        <div className="section"><div className="section-header"><span className="section-title">界面渲染<small>用于候选窗、悬浮工具栏和托盘菜单；更改后需重启输入法进程。</small></span><CustomDropdown ariaLabel="界面渲染" value={draft.ui_backend ?? "direct2d"} options={[["direct2d", "Direct2D（原生）"], ["webview2", "WebView2"]]} onChange={value => setDraft({ ...draft, ui_backend: value as Preferences["ui_backend"] })} /></div></div>
        <div className="section"><label className="section-header"><span className="section-title">候选窗口跟随光标<small>关闭后保持候选窗口首次位置，直到候选窗口消失。</small></span><input className="toggle" type="checkbox" checked={draft.candidate_follow_cursor ?? true} onChange={event => setDraft({ ...draft, candidate_follow_cursor: event.target.checked })} /></label></div>
        <div className="section candidate-preview-section" aria-label="候选窗口预览">
          <div className="section-title">候选窗口预览</div>
          <div className={`candidate-preview-card candidate-preview-${draft.candidate_layout ?? "vertical"}`} style={{ fontSize: `${draft.candidate_font_size ?? 16}px` }}>
            {draft.candidate_preedit_style !== "empty" && <span className="candidate-preview-preedit" style={{ fontSize: `${draft.candidate_preedit_font_size ?? 16}px` }}>ni'hao</span>}
            <span className="candidate-preview-item active"><b>1</b> 你好</span>
            <span className="candidate-preview-item"><b>2</b> 你号</span>
            <span className="candidate-preview-item"><b>3</b> 泥好</span>
          </div>
        </div>
        <div className="section"><div className="section-header"><span className="section-title">候选窗字号</span><CustomDropdown ariaLabel="候选窗字号" value={String(draft.candidate_font_size ?? 16)} options={Array.from({ length: 21 }, (_, index) => { const size = String(index + 12); return [size, size] as [string, string]; })} onChange={value => setDraft({ ...draft, candidate_font_size: Number(value) })} /></div></div>
        <div className="section"><label className="section-header"><span className="section-title">候选窗主字体<small>使用系统已安装字体名称</small></span><input aria-label="候选窗主字体" value={draft.candidate_font_family ?? "Segoe UI"} onChange={event => setDraft({ ...draft, candidate_font_family: event.target.value })} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">候选窗补充字体<small>按顺序回落，逗号分隔，最多 8 个</small></span><FallbackFontInput value={draft.candidate_fallback_fonts ?? []} onChange={fonts => setDraft({ ...draft, candidate_fallback_fonts: fonts })} /></label></div>
        <div className="section"><div className="section-header"><span className="section-title">候选窗预编辑字号</span><CustomDropdown ariaLabel="候选窗预编辑字号" value={String(draft.candidate_preedit_font_size ?? 16)} options={Array.from({ length: 21 }, (_, index) => { const size = String(index + 12); return [size, size] as [string, string]; })} onChange={value => setDraft({ ...draft, candidate_preedit_font_size: Number(value) })} /></div></div>
        <div className="section"><label className="section-header"><span className="section-title">候选文字颜色<small>留空时跟随系统主题</small></span><span><input aria-label="候选文字颜色" type="color" value={draft.candidate_text_color ?? "#ffffff"} onChange={event => setDraft({ ...draft, candidate_text_color: event.target.value })} /> <button type="button" className="secondary" onClick={() => setDraft({ ...draft, candidate_text_color: null })}>跟随主题</button></span></label></div>
        <div className="section"><div className="section-header"><span className="section-title">每页候选数量</span><CustomDropdown ariaLabel="每页候选数量" value={String(draft.candidate_page_size)} options={Array.from({ length: 9 }, (_, index) => { const size = String(index + 1); return [size, size] as [string, string]; })} onChange={value => setDraft({ ...draft, candidate_page_size: Number(value) })} /></div></div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "skin"} aria-label="皮肤">
        <div className="section skin-intro"><div className="section-title">候选窗口皮肤</div><small>选择候选窗口的颜色主题；保存后应用于原生候选窗口。</small></div>
        <div className="skin-grid" role="radiogroup" aria-label="候选窗口皮肤">
          {([['follow', '跟随全局', '使用主题模式的颜色'], ['dark', '深色', '深色背景与浅色文字'], ['light', '浅色', '浅色背景与深色文字']] as const).map(([value, label, description]) => <button type="button" className={`skin-card${(draft.candidate_theme ?? "follow") === value ? " selected" : ""}`} role="radio" aria-checked={(draft.candidate_theme ?? "follow") === value} key={value} onClick={() => setDraft({ ...draft, candidate_theme: value })}><span className={`skin-swatch skin-swatch-${value}`} aria-hidden="true" /><span className="skin-card-title">{label}</span><small>{description}</small></button>)}
        </div>
        <div className="section help-section"><div className="section-header"><span className="section-title">内置皮肤<small>候选窗与悬浮工具栏主题</small></span><button type="button" className="secondary" onClick={() => setSkinPreviewTheme(value => value === "dark" ? "light" : "dark")} aria-label="切换皮肤预览明暗">预览{skinPreviewTheme === "dark" ? "浅色" : "深色"}</button></div><div className="skin-grid" role="list" aria-label="内置皮肤"><div className={`skin-card skin-preview-${skinPreviewTheme}`}><span className="skin-card-title">Fluent</span><small>当前默认主题</small>{selectedSkin === "fluent" && <small role="status">当前皮肤</small>}<HostActionButton label="应用 Fluent" success="已应用" action={client.skin?.select ? async () => { await client.skin!.select!("fluent"); setSelectedSkin("fluent"); } : undefined} /></div><div className={`skin-card skin-preview-${skinPreviewTheme}`}><span className="skin-card-title">微信绿</span><small>微信绿候选窗与悬浮工具栏</small>{selectedSkin === "wechat" && <small role="status">当前皮肤</small>}<HostActionButton label="应用 微信绿" success="已应用" action={client.skin?.select ? async () => { await client.skin!.select!("wechat"); setSelectedSkin("wechat"); } : undefined} /></div><div className={`skin-card skin-preview-${skinPreviewTheme}`}><span className="skin-card-title">Graphite</span><small>克制、平直的候选窗与悬浮工具栏</small>{selectedSkin === "graphite" && <small role="status">当前皮肤</small>}<HostActionButton label="应用 Graphite" success="已应用" action={client.skin?.select ? async () => { await client.skin!.select!("graphite"); setSelectedSkin("graphite"); } : undefined} /></div><div className={`skin-card skin-preview-${skinPreviewTheme}`}><span className="skin-card-title">杨柳青</span><small>柔和圆角与柳绿色整行高亮</small>{selectedSkin === "willow_green" && <small role="status">当前皮肤</small>}<HostActionButton label="应用 杨柳青" success="已应用" action={client.skin?.select ? async () => { await client.skin!.select!("willow_green"); setSelectedSkin("willow_green"); } : undefined} /></div></div></div>
        <div className="section help-section"><div className="section-title">外部皮肤</div><p className="about-disclaimer">将包含 skin.toml 的皮肤文件夹复制到宿主皮肤目录，然后刷新皮肤。</p><div className="section-header"><span className="section-title">皮肤目录</span><span><HostActionButton label="打开目录" action={client.skin ? () => client.skin!.openDirectory() : undefined} /><HostActionButton label="刷新皮肤" action={client.skin ? async () => { await client.skin!.refresh(); if (client.skin!.list) setExternalSkins(await client.skin!.list()); if (client.skin!.selected) setSelectedSkin(await client.skin!.selected()); } : undefined} /></span></div>{externalSkins.map(skin => <div className="section" key={skin.id}><strong>{skin.name}</strong>{selectedSkin === skin.id && <span role="status">当前皮肤</span>}<small>{[skin.id, skin.version && `v${skin.version}`, skin.author].filter(Boolean).join(" · ")}</small><p>{skin.compatible ? (skin.description || "外部皮肤") : (skin.issues?.join("；") || "当前客户端不兼容此皮肤")}</p>{skin.compatible && <HostActionButton label="应用" success="已应用" action={client.skin?.select ? async () => { await client.skin!.select!(skin.id); setSelectedSkin(skin.id); } : undefined} />}</div>)}{client.skin && externalSkins.length === 0 && <p className="capability-status-inline">尚未扫描到外部皮肤</p>}{!client.skin && <p className="capability-status-inline">皮肤宿主尚未接入</p>}</div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "about"} aria-label="关于">
        <div className="section about-hero"><img src={logo} alt="水杉 IME" /><div><h2>水杉 IME</h2><p>跨平台中文输入法客户端预览版</p></div></div>
        <div className="section about-links">
          <div className="about-row"><span>当前版本</span><strong>客户端预览版</strong></div>
          <div className="about-row"><span>更新检查</span><span className="capability-status-inline">更新宿主尚未接入</span></div>
          <a className="about-row about-link" href="https://github.com/metasequoiaime/MSIME-Client" target="_blank" rel="noreferrer" onClick={event => { if (client.about) { event.preventDefault(); openExternalUrl("https://github.com/metasequoiaime/MSIME-Client"); } }}><span>开源项目</span><span aria-hidden="true">↗</span></a>
          <a className="about-row about-link" href="https://github.com/metasequoiaime/MSIME-Client/blob/develop/LICENSE" target="_blank" rel="noreferrer" onClick={event => { if (client.about) { event.preventDefault(); openExternalUrl("https://github.com/metasequoiaime/MSIME-Client/blob/develop/LICENSE"); } }}><span>开源许可协议</span><span aria-hidden="true">↗</span></a>
        </div>
        <div className="section help-section"><div className="section-title">版本更新</div><p className="about-disclaimer">检查远端版本 manifest；发现新版本时打开受信任的发布页。</p><button type="button" className="secondary" disabled={!client.update} aria-label="检查更新" onClick={() => { setUpdateStatus("检查中…"); void Promise.resolve(client.update?.check()).then(result => { setUpdateDetails(result?.found ? { digest: result.installer_sha256, name: result.installer_name, signed: result.signed } : undefined); setUpdateStatus(result?.found ? `发现 ${result.version ?? "新"} 版本${result.signed === false ? "（未签名，请谨慎核验）" : "，已打开发布页。"}` : "当前已是最新版本。"); }).catch(() => setUpdateStatus("检查更新失败，请稍后重试。")); }}>检查更新{client.update ? "" : "（待宿主接入）"}</button>{updateStatus && <p role="status">{updateStatus}</p>}{(updateDetails?.name || updateDetails?.digest) && <div className="update-digest">{updateDetails.name && <small>安装器：{updateDetails.name}</small>}{updateDetails.digest && <><small>SHA-256：{updateDetails.digest}</small>{client.clipboard?.copy && <button type="button" className="secondary" onClick={() => void client.clipboard!.copy!(updateDetails.digest!)}>复制摘要</button>}</>}</div>}</div>
        <div className="section help-section"><div className="section-title">诊断日志</div><p className="about-disclaimer">记录通信、候选窗和焦点状态，不记录按键、输入内容或候选文本。请在复现问题后关闭诊断。</p>{diagnosticError && <p role="alert" className="error">{diagnosticError}</p>}<label className="section-header"><span className="section-title">Server 日志</span><input aria-label="Server 诊断日志" type="checkbox" checked={serverDiagnostics} disabled={!client.diagnostics} onChange={event => void setDiagnostic("server", event.target.checked)} /></label><label className="section-header"><span className="section-title">TSF 日志</span><input aria-label="TSF 诊断日志" type="checkbox" checked={tsfDiagnostics} disabled={!client.diagnostics} onChange={event => void setDiagnostic("tsf", event.target.checked)} /></label>{!client.diagnostics && <p className="capability-status-inline">诊断宿主尚未接入</p>}</div>
        <p className="about-disclaimer">本客户端仍在持续迁移 Windows 版功能与界面；部分平台能力可能尚未接入。</p>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "feedback"} aria-label="反馈">
        <div className="section feedback-hero"><div className="section-title">告诉我们你的想法</div><p>遇到问题或有功能建议时，可以通过以下渠道提交和交流。</p></div>
        <div className="feedback-list">
          <div className="section feedback-card"><div className="feedback-icon">GH</div><div className="feedback-body"><div className="feedback-title">GitHub Issues</div><p>适合提交可复现的问题、功能建议和开发讨论。</p><a className="feedback-link" href="https://github.com/metasequoiaime/MSIME-Windows/issues" target="_blank" rel="noreferrer" onClick={event => { if (client.feedback) { event.preventDefault(); openFeedbackUrl("https://github.com/metasequoiaime/MSIME-Windows/issues"); } }}>查看 Issues ↗</a></div></div>
          <div className="section feedback-card"><div className="feedback-icon">QQ</div><div className="feedback-body"><div className="feedback-title">QQ 交流群</div><p>适合中文用户进行日常交流、测试反馈和使用讨论。</p><code>群号：829919142</code></div><HostActionButton label="复制群号" success="已复制" action={client.clipboard?.copy ? () => client.clipboard!.copy!("829919142") : undefined} /></div>
          <div className="section feedback-card"><div className="feedback-icon">TG</div><div className="feedback-body"><div className="feedback-title">Telegram 群组</div><p>面向国际用户和开发者的即时讨论频道。</p><a className="feedback-link" href="https://t.me/msimegroup" target="_blank" rel="noreferrer" onClick={event => { if (client.feedback) { event.preventDefault(); openFeedbackUrl("https://t.me/msimegroup"); } }}>打开群组 ↗</a></div></div>
        </div>
        <div className="section feedback-note"><strong>提交问题时建议附上</strong><span>系统版本、输入方案、复现步骤、相关截图，以及 Debug 输出中的关键日志。</span></div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "help"} aria-label="帮助">
        <div className="section help-hero"><div className="section-title">使用帮助</div><p>了解输入方案、候选操作和常见问题的处理方法。</p></div>
        <div className="section help-section"><div className="section-title">常用操作</div><div className="help-list"><div><strong>选择候选</strong><span>按数字键 1–9 或空格键提交候选。</span></div><div><strong>翻页和移动</strong><span>使用输入页启用的翻页键或上/下方向键。</span></div><div><strong>临时模式</strong><span>在实用功能页开启快捷输入模式后，按对应 Shift 快捷键进入。</span></div></div></div>
        <div className="section help-section"><div className="section-title">遇到问题</div><div className="help-list"><div><strong>设置无法保存</strong><span>检查设置页面是否有冲突提示，点击“重新读取”后再尝试保存。</span></div><div><strong>候选窗口未出现</strong><span>确认输入方案和候选窗口主题设置，再重启输入法进程。</span></div><div><strong>需要报告问题</strong><span>前往反馈页提交可复现步骤、系统版本和相关截图。</span></div></div></div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "screen_keyboard"} aria-label="屏幕键盘">
        <div className="section capability-hero"><div className="section-title">屏幕键盘</div><p>使用屏幕上的虚拟键盘输入字符，适合触控设备或无法使用实体键盘的场景。</p></div>
        <div className="section capability-status"><span className="capability-dot" aria-hidden="true" /><div><strong>{client.screen_keyboard ? "宿主已提供屏幕键盘" : "宿主尚未接入"}</strong><small>当前客户端已预留设置入口，屏幕键盘运行时将在后续平台增量中接入。</small></div>{client.screen_keyboard && <HostActionButton label="打开" action={() => client.screen_keyboard!.open()} />}</div>
        <div className="section"><div className="section-title">屏幕键盘预览</div><div className="screen-keyboard-preview" role="grid" aria-label="屏幕键盘预览">{[["Esc", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "退格"], ["Tab", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"], ["Caps", "A", "S", "D", "F", "G", "H", "J", "K", "L", ";"], ["Shift", "Z", "X", "C", "V", "B", "N", "M", ",", ".", "/"], ["中/英", "空格", "回车"]].map((row, rowIndex) => <div className="screen-keyboard-row" role="row" key={rowIndex}>{row.map(key => <button type="button" className="screen-key" disabled key={key} role="gridcell">{key}</button>)}</div>)}</div></div>
        <div className="section"><div className="section-title">使用说明</div><div className="help-list"><div><strong>打开方式</strong><span>接入后可从输入法工具栏或系统托盘打开屏幕键盘。</span></div><div><strong>主题同步</strong><span>屏幕键盘将跟随全局主题和字号设置。</span></div></div></div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "voice_input"} aria-label="语音输入">
        <div className="section capability-hero"><div className="section-title">语音输入</div><p>按住快捷键录音，将语音转换为文字并插入当前应用。</p></div>
        <div className="section"><label className="section-header"><span className="section-title">启用语音输入<small>在右键菜单中开始或停止录音</small></span><input aria-label="启用语音输入" type="checkbox" checked={voice.enabled} onChange={event => updateVoice({ enabled: event.target.checked })} /></label></div>
        <div className="section"><div className="section-title">语音输入快捷键<small>勾选启用对应快捷键；长按快捷键松开后停止录音</small></div><label className="check-option"><input aria-label="RAlt（长按录音）" type="checkbox" checked={voice.hotkey_ralt} onChange={event => updateVoice({ hotkey_ralt: event.target.checked })} /><span>RAlt（长按录音）</span></label><label className="check-option"><input aria-label="Ctrl + Win（长按录音）" type="checkbox" checked={voice.hotkey_ctrl_win} onChange={event => updateVoice({ hotkey_ctrl_win: event.target.checked })} /><span>Ctrl + Win（长按录音）</span></label><label className="check-option"><input aria-label="RCtrl + RAlt（长按录音）" type="checkbox" checked={voice.hotkey_rctrl_ralt} onChange={event => updateVoice({ hotkey_rctrl_ralt: event.target.checked })} /><span>RCtrl + RAlt（长按录音）</span></label><label className="check-option"><input aria-label="长按快捷键 + Space（锁定录音）" type="checkbox" checked={voice.hotkey_hold_space_lock} onChange={event => updateVoice({ hotkey_hold_space_lock: event.target.checked })} /><span>长按快捷键 + Space（锁定录音）</span></label><label className="check-option"><input aria-label="Ctrl + F9（开始 / 停止录音）" type="checkbox" checked={voice.hotkey_ctrl_f9} onChange={event => updateVoice({ hotkey_ctrl_f9: event.target.checked })} /><span>Ctrl + F9（开始 / 停止录音）</span></label></div>
        <div className="section"><div className="section-title">录音提示音</div><label className="section-header"><span>提示音总开关</span><input aria-label="录音提示音总开关" type="checkbox" checked={voice.sound_enabled} onChange={event => updateVoice({ sound_enabled: event.target.checked })} /></label><label className="section-header"><span>开始录音时播放</span><input aria-label="开始录音时播放" type="checkbox" checked={voice.start_sound} onChange={event => updateVoice({ start_sound: event.target.checked })} /></label><label className="section-header"><span>结束录音时播放</span><input aria-label="结束录音时播放" type="checkbox" checked={voice.end_sound} onChange={event => updateVoice({ end_sound: event.target.checked })} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">录音时静音其他声音<small>录音期间暂时关闭其他应用播放声音</small></span><input aria-label="录音时静音其他声音" type="checkbox" checked={voice.mute_system_audio} onChange={event => updateVoice({ mute_system_audio: event.target.checked })} /></label></div>
        <div className="section"><div className="section-header"><span className="section-title">识别语言</span><CustomDropdown ariaLabel="识别语言" value={voice.language} options={[["zh-cn", "简体中文"], ["en", "English"], ["auto", "自动"]]} onChange={value => updateVoice({ language: value })} /></div><div className="section-header"><span className="section-title">识别结果上屏方式</span><CustomDropdown ariaLabel="识别结果上屏方式" value={voice.commit_mode} options={[["tsf", "TSF 上屏"], ["sendinput", "SendInput"], ["ctrl_v", "Ctrl+V 上屏"]]} onChange={value => updateVoice({ commit_mode: value })} /></div></div>
        <div className="section"><div className="section-title">录音与识别预览</div><div className="voice-waveform-preview" role="img" aria-label="录音波形预览">{[18, 34, 22, 48, 30, 58, 40, 26, 52, 36, 20, 44, 28, 50, 24, 38, 18].map((height, index) => <i key={index} style={{ height: `${height}px` }} />)}</div><div className="help-list"><div><strong>录音</strong><span>按住快捷键开始录音，松开后停止；Space 可锁定录音。</span></div><div><strong>识别流程</strong><span>录音 → ASR 转写 → 可选文本润色 → 提交到当前应用。</span></div></div></div>
        <div className="section"><label className="section-header"><span className="section-title">启用文本润色<small>ASR 转写后整理文本</small></span><input aria-label="启用文本润色" type="checkbox" checked={voice.polish_enabled} onChange={event => updateVoice({ polish_enabled: event.target.checked })} /></label><div className="section-header"><span>润色服务提供商</span><CustomDropdown ariaLabel="润色服务提供商" value={voice.polish_provider} options={[["siliconflow", "SiliconFlow"], ["openai", "OpenAI"], ["deepseek", "DeepSeek"], ["groq", "Groq"]]} onChange={value => updateVoice({ polish_provider: value })} /></div><label>润色模型<input aria-label="润色模型" value={voice.polish_model} onChange={event => updateVoice({ polish_model: event.target.value })} /></label><label>润色 API Token<input aria-label="润色 API Token" type="password" value={voice.polish_token} onChange={event => updateVoice({ polish_token: event.target.value })} /></label><label>润色接口地址<input aria-label="润色接口地址" type="url" value={voice.polish_endpoint} onChange={event => updateVoice({ polish_endpoint: event.target.value })} /></label><div className="section-header"><span>润色提示词</span><CustomDropdown ariaLabel="润色提示词" value={voice.polish_prompt_id} options={[["cleanup", "精炼整理"], ["faithful", "忠实校对"], ["zh2en", "中翻英"], ["casual", "口语整理"], ["custom_1", "自定义一"], ["custom_2", "自定义二"], ["custom_3", "自定义三"]]} onChange={value => updateVoice({ polish_prompt_id: value, polish_prompt: voicePromptPresets[value] ?? voice.polish_prompt })} /></div><textarea aria-label="润色提示词内容" value={voice.polish_prompt} onChange={event => updateVoice({ polish_prompt: event.target.value })} /></div>
        <div className="section"><div className="section-title">豆包识别选项</div><label className="section-header"><span>数字格式化</span><input aria-label="豆包数字格式化" type="checkbox" checked={voice.doubao_enable_itn} onChange={event => updateVoice({ doubao_enable_itn: event.target.checked })} /></label><label className="section-header"><span>标点预测</span><input aria-label="豆包标点预测" type="checkbox" checked={voice.doubao_enable_punc} onChange={event => updateVoice({ doubao_enable_punc: event.target.checked })} /></label><label className="section-header"><span>语义顺滑</span><input aria-label="豆包语义顺滑" type="checkbox" checked={voice.doubao_enable_ddc} onChange={event => updateVoice({ doubao_enable_ddc: event.target.checked })} /></label><label>热词表 ID<input aria-label="豆包热词表 ID" value={voice.doubao_boosting_table_id} onChange={event => updateVoice({ doubao_boosting_table_id: event.target.value })} /></label></div>
        <div className="section"><div className="section-title">文本润色预览</div><div className="help-list"><div><strong>ASR 原文</strong><span>嗯 我们明天呃下午三点开会</span></div><div><strong>润色结果</strong><span>我们明天下午三点开会。</span></div><div><strong>上屏方式</strong><span>接入后可选择 TSF、SendInput 或 Ctrl+V 上屏。</span></div></div></div>
        <div className="section"><div className="section-title">ASR API 配置</div><div className="help-list"><div className="section-header"><span className="section-title">服务提供商</span><CustomDropdown ariaLabel="ASR 服务提供商" value={voice.asr_provider} options={[["doubao", "豆包"], ["openai", "OpenAI"], ["siliconflow", "SiliconFlow"], ["groq", "Groq"]]} onChange={value => updateVoice({ asr_provider: value })} /></div><label>App ID / App Key<input aria-label="ASR App ID / App Key" value={voice.asr_app_key} onChange={event => updateVoice({ asr_app_key: event.target.value })} /></label><label>模型<input aria-label="ASR 模型" value={voice.asr_model} onChange={event => updateVoice({ asr_model: event.target.value })} /></label><label>Access Token / API Key<input aria-label="ASR Access Token / API Key" type="password" value={voice.asr_token} onChange={event => updateVoice({ asr_token: event.target.value })} /></label><label>接口地址<input aria-label="ASR 接口地址" type="url" value={voice.asr_endpoint} onChange={event => updateVoice({ asr_endpoint: event.target.value })} /></label></div></div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "handwriting"} aria-label="手写识别">
        <div className="section capability-hero"><div className="section-title">手写识别</div><p>在手写面板中书写汉字，识别结果将作为候选项插入当前应用。</p></div>
        <div className="section capability-status"><span className="capability-dot" aria-hidden="true" /><div><strong>{client.handwriting ? "宿主已提供手写识别板" : "手写宿主尚未接入"}</strong><small>Windows 版通过系统手写识别面板提供此能力；当前客户端尚未接入原生手写面板。</small></div>{client.handwriting && <HostActionButton label="打开" action={() => client.handwriting!.open()} />}</div>
        <div className="section"><div className="section-title">手写识别板预览</div><div className="handwriting-preview-board" role="img" aria-label="手写识别板预览"><span className="handwriting-crosshair" aria-hidden="true">十</span><svg viewBox="0 0 160 160" aria-hidden="true"><path d="M35 45 Q80 20 125 45 M45 75 Q80 55 115 75 M35 105 Q80 130 125 105 M80 25 L80 135" /></svg><div className="handwriting-candidates"><span>中</span><span>申</span><span>仲</span></div></div></div>
        <div className="section"><div className="section-title">使用准备</div><div className="help-list"><div><strong>安装语言组件</strong><span>Windows 用户需安装“中文手写包”：设置 → 时间和语言 → 语言和区域 → 中文 → 语言选项 → 手写。</span></div><div><strong>打开方式</strong><span>接入后可从输入法工具栏或托盘菜单打开手写识别面板。</span></div><div><strong>识别结果</strong><span>面板返回的候选项会交给输入运行时，确认后提交到当前应用。</span></div></div></div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "ai_assistant"} aria-label="AI 辅助">
        <div className="section capability-hero"><div className="section-title">AI 辅助</div><p>使用兼容 Chat Completions 的服务异步生成联想候选，帮助快速完成输入。</p></div>
        <div className="section capability-status"><span className="capability-dot" aria-hidden="true" /><div><strong>AI 宿主尚未接入</strong><small>Windows 版支持 DeepSeek、OpenAI、SiliconFlow 和 Groq；当前客户端尚未接入在线 AI 请求与候选管线。</small></div></div>
        <div className="section"><div className="section-title">联想候选预览</div><div className="candidate-preview-card" aria-label="AI 联想候选预览"><span className="candidate-preview-preedit">ni'hao</span><span className="candidate-preview-item active"><b>1</b> 你好</span><span className="candidate-preview-item"><b>3</b> AI 联想候选</span></div><div className="help-list"><div><strong>服务商</strong><span>DeepSeek · OpenAI · SiliconFlow · Groq</span></div><div><strong>候选位置</strong><span>在本地候选之后异步插入额外联想项。</span></div></div></div>
        <div className="section"><label className="section-header"><span className="section-title">启用 AI 联想<small>在全拼和双拼输入时异步生成额外候选</small></span><input aria-label="启用 AI 联想" type="checkbox" checked={ai.enabled} onChange={event => updateAi({ enabled: event.target.checked })} /></label></div>
        <div className="section"><div className="section-title">API 配置</div><div className="help-list"><label>服务提供商<CustomDropdown ariaLabel="服务提供商" value={ai.provider} options={[["deepseek", "DeepSeek"], ["openai", "OpenAI"], ["siliconflow", "SiliconFlow"], ["groq", "Groq"]]} onChange={value => updateAi({ provider: value, model: aiProviderDefaults[value]?.model ?? ai.model, endpoint: aiProviderDefaults[value]?.endpoint ?? ai.endpoint })} /></label><label>模型<input aria-label="AI 模型" value={ai.model} onChange={event => updateAi({ model: event.target.value })} /></label><label>API Token<input aria-label="AI API Token" type="password" value={ai.tokens?.[ai.provider] ?? ai.token} onChange={event => updateAi({ token: event.target.value, tokens: { ...(ai.tokens ?? {}), [ai.provider]: event.target.value } })} /></label><label>候选数量<input aria-label="AI 候选数量" type="number" min={1} max={10} value={ai.candidate_limit} onChange={event => updateAi({ candidate_limit: Math.max(1, Math.min(10, Number(event.target.value) || 3)) })} /></label><label>接口地址<input aria-label="AI 接口地址" type="url" value={ai.endpoint} onChange={event => updateAi({ endpoint: event.target.value })} /></label></div></div>
        <div className="section"><div className="section-title">自定义提示词</div><CustomDropdown ariaLabel="提示词槽位" value={ai.prompt_id} options={[["custom_1", "自定义一"], ["custom_2", "自定义二"], ["custom_3", "自定义三"]]} onChange={value => updateAi({ prompt_id: value, prompt: value === "custom_2" ? (ai.prompt_custom_2 ?? "") : value === "custom_3" ? (ai.prompt_custom_3 ?? "") : (ai.prompt_custom_1 ?? "") })} /><textarea aria-label="AI 自定义提示词" value={selectedPrompt} onChange={event => updatePrompt(event.target.value)} /></div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "floating_toolbar"} aria-label="悬浮工具栏">
        <div className="section capability-hero"><div className="section-title">悬浮工具栏</div><p>在桌面显示输入法状态和常用功能，便于快速切换输入模式。</p></div>
        <div className="section capability-status"><span className="capability-dot" aria-hidden="true" /><div><strong>工具栏宿主尚未接入</strong><small>Windows 版支持工具栏显示、缩放、位置和组件选择；当前客户端尚未接入原生桌面工具栏。</small></div></div>
        <div className="section"><div className="section-header"><span className="section-title">在桌面显示悬浮工具栏<small>偏好会保存；原生窗口将在宿主接入后使用</small></span><input aria-label="在桌面显示悬浮工具栏" type="checkbox" checked={draft.floating_toolbar?.enabled ?? true} onChange={event => setDraft({ ...draft, floating_toolbar: { ...draft.floating_toolbar, enabled: event.target.checked, scale_percent: draft.floating_toolbar?.scale_percent ?? 100, font_size: draft.floating_toolbar?.font_size ?? 24 } })} /></div></div>
        <div className="section"><div className="section-header"><span className="section-title">工具栏缩放<small>相对系统 DPI 的额外缩放</small></span><CustomDropdown ariaLabel="工具栏缩放" value={String(draft.floating_toolbar?.scale_percent ?? 100)} options={[50, 75, 100, 125, 150, 175, 200].map(value => [String(value), `${value}%`] as [string, string])} onChange={value => setDraft({ ...draft, floating_toolbar: { ...draft.floating_toolbar, enabled: draft.floating_toolbar?.enabled ?? true, scale_percent: Number(value), font_size: draft.floating_toolbar?.font_size ?? 24 } })} /></div></div>
        <div className="section"><div className="section-header"><span className="section-title">图标字号<small>工具栏图标基准大小</small></span><CustomDropdown ariaLabel="图标字号" value={String(draft.floating_toolbar?.font_size ?? 24)} options={[12, 16, 20, 24, 28, 32, 40, 48].map(value => [String(value), `${value}px`] as [string, string])} onChange={value => setDraft({ ...draft, floating_toolbar: { ...draft.floating_toolbar, enabled: draft.floating_toolbar?.enabled ?? true, scale_percent: draft.floating_toolbar?.scale_percent ?? 100, font_size: Number(value) } })} /></div></div>
        <div className="section"><div className="section-title">工具栏组件</div><div className="help-list">{([['fullwidth', '全角 / 半角'], ['punctuation', '中英文标点'], ['character_set', '简繁切换'], ['emoji', '表情与符号'], ['screen_keyboard', '屏幕键盘'], ['settings', '设置']] as const).map(([key, label]) => <label className="check-option" key={key}><input type="checkbox" checked={draft.floating_toolbar?.[key] ?? (key !== 'screen_keyboard')} onChange={event => setDraft({ ...draft, floating_toolbar: { enabled: draft.floating_toolbar?.enabled ?? true, scale_percent: draft.floating_toolbar?.scale_percent ?? 100, font_size: draft.floating_toolbar?.font_size ?? 24, fullwidth: draft.floating_toolbar?.fullwidth ?? true, punctuation: draft.floating_toolbar?.punctuation ?? true, character_set: draft.floating_toolbar?.character_set ?? true, emoji: draft.floating_toolbar?.emoji ?? true, screen_keyboard: draft.floating_toolbar?.screen_keyboard ?? false, settings: draft.floating_toolbar?.settings ?? true, [key]: event.target.checked } })} /><span>{label}</span></label>)}</div></div>
        <div className="section"><div className="section-title">悬浮工具栏预览</div><div className="candidate-preview-card" aria-label="悬浮工具栏预览"><span className="candidate-preview-item active">中</span>{([['fullwidth', '全角'], ['punctuation', '标点'], ['character_set', '简繁'], ['emoji', '表情'], ['screen_keyboard', '键盘'], ['settings', '设置']] as const).filter(([key]) => draft.floating_toolbar?.[key] ?? (key !== 'screen_keyboard')).map(([key, label]) => <span className="candidate-preview-item" key={key}>{label}</span>)}</div></div>
        <div className="section"><div className="section-title">功能预览</div><div className="help-list"><div><strong>显示与缩放</strong><span>接入后可控制工具栏显示状态、相对系统 DPI 的缩放和图标基准大小。</span></div><div><strong>常用组件</strong><span>可选择全角/半角、中英文标点、简繁切换、表情符号、屏幕键盘和设置入口。</span></div><div><strong>工具栏主题同步</strong><span>工具栏将跟随候选窗口主题和系统颜色设置。</span></div></div></div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "input"} aria-label="输入">
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
        <div className="section"><div className="section-header"><span className="section-title">默认输入模式<small>新会话打开时使用中文或英文模式。</small></span><CustomDropdown ariaLabel="默认输入模式" value={draft.default_ime_mode ?? "chinese"} options={[["chinese", "中文"], ["english", "英文"]]} onChange={value => setDraft({ ...draft, default_ime_mode: value as Preferences["default_ime_mode"] })} /></div></div>
        <div className="section" hidden={draft.scheme === "japanese"}><div className="section-header"><span className="section-title">双拼方案</span><CustomDropdown ariaLabel="双拼方案" value={draft.shuangpin_profile} options={[["xiaohe", "小鹤双拼"], ["ziranma", "自然码双拼"], ["shoudao", "首道双拼"], ["microsoft", "微软双拼"]]} onChange={value => setDraft({ ...draft, shuangpin_profile: value as Preferences["shuangpin_profile"] })} /></div></div>
        <div className="section" hidden={draft.scheme === "japanese"}><div className="section-header"><span className="section-title">五笔方案</span><CustomDropdown ariaLabel="五笔方案" value="wubi86" options={[["wubi86", "86 五笔"]]} onChange={() => {}} /></div></div>
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
        <div className="section"><label className="section-header"><span className="section-title">全拼纠错<small>自动纠正常见拼音输入错误</small></span><input className="toggle" type="checkbox" checked={draft.autocorrect ?? true} onChange={event => setDraft({ ...draft, autocorrect: event.target.checked })} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">学习选词习惯<small>根据选词调整候选顺序</small></span><input className="toggle" type="checkbox" checked={draft.learning} onChange={event => setDraft({ ...draft, learning: event.target.checked })} /></label></div>
        <div className="section"><label className="section-header"><span className="section-title">中文标点<small>默认使用中文标点符号</small></span><input className="toggle" type="checkbox" checked={draft.chinese_punctuation} onChange={event => setDraft({ ...draft, chinese_punctuation: event.target.checked })} /></label></div>
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
            <div className="section-header frequency-option-row"><span className="section-title">调频方式</span><CustomDropdown ariaLabel="调频方式" value={frequency.mode} options={[["disabled", "关闭"], ["pin", "一次置顶"], ["halve", "折半调频"], ["linear", "线性调频"], ["promote", "一次置前"]]} onChange={value => setDraft({ ...draft, frequency: { ...frequency, mode: value as FrequencyPreferences["mode"] } })} /></div>
            {([["trigger_count", "触发频次(第几次上屏触发)"], ["linear_step", "线性调频步长"]] as const).map(([key, label]) => <div key={key}>
              <div className="input-option-divider" />
              <div className="section-header frequency-option-row"><span className="section-title">{label}</span><CustomDropdown ariaLabel={label} value={String(frequency[key])} options={[1, 2, 3, 4, 5, 6, ...(frequency[key] > 6 ? [frequency[key]] : [])].map(value => [String(value), String(value)] as [string, string])} onChange={value => setDraft({ ...draft, frequency: { ...frequency, [key]: Number(value) } })} /></div>
            </div>)}
          </div>
        </div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "shortcuts"} aria-label="快捷键">
        <div className="section shortcut-intro">输入法快捷键仅在对应输入状态或候选窗口显示时生效。翻页方式可在“输入”中启用或关闭。</div>
        <div className="section shortcut-section"><div className="section-title">候选操作</div><small>输入和选取候选词时使用</small><div className="shortcut-list">
          <div className="shortcut-row"><span>选择候选</span><kbd>Space 或 1–9</kbd></div>
          {(draft.navigation ?? defaultNavigation).minus_equal && <div className="shortcut-row"><span>向前 / 向后翻页</span><kbd>- / =</kbd></div>}
          {(draft.navigation ?? defaultNavigation).comma_period && <div className="shortcut-row"><span>向前 / 向后翻页</span><kbd>, / .</kbd></div>}
          {(draft.navigation ?? defaultNavigation).tab && <div className="shortcut-row"><span>向前 / 向后翻页</span><kbd>Shift+Tab / Tab</kbd></div>}
          {(draft.navigation ?? defaultNavigation).page_up_down && <div className="shortcut-row"><span>向前 / 向后翻页</span><kbd>Page Up / Page Down</kbd></div>}
          {(draft.navigation ?? defaultNavigation).arrows && <div className="shortcut-row"><span>移动候选项</span><kbd>↑ / ↓</kbd></div>}
          <div className="shortcut-row"><span>提交 / 取消输入</span><kbd>Enter / Esc</kbd></div>
        </div></div>
        <div className="section shortcut-section"><div className="section-title">全局维护快捷键</div><small>程序运行时全局生效</small><div className="shortcut-list">
          <div className="shortcut-row"><span>清除输入法引擎缓存</span><kbd>Ctrl+Shift+Alt+C</kbd></div>
          <div className="shortcut-row"><span>重启输入法服务</span><kbd>Ctrl+Shift+Alt+R</kbd></div>
        </div></div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "helpcode"} aria-label="辅助码">
        {([['shuangpin_helpcode', '双拼'], ['quanpin_helpcode', '全拼']] as const).map(([key, label]) => {
          const value = draft[key] ?? defaultHelpcode;
          return <div className="section" key={key}>
            <label className="section-header"><span className="section-title">{label}辅助码</span><input className="toggle" type="checkbox" checked={value.enabled} onChange={event => setDraft({ ...draft, [key]: { ...value, enabled: event.target.checked } })} /></label>
            <div className="section-header helpcode-schema"><span className="section-title">{label}辅助码方案</span><CustomDropdown ariaLabel={`${label}辅助码方案`} disabled={!value.enabled} value={value.schema} options={helpcodeSchemas} onChange={schema => setDraft({ ...draft, [key]: { ...value, schema: schema as HelpcodeSchema } })} /></div>
          </div>;
        })}
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "dictionary"} aria-label="词库">
        {client.dictionary ? <div className="section quick-phrase-manager" role="region" aria-label="快捷短语管理">
          <div className="section-header"><span className="section-title">快捷短语管理<small>查询、新增、编辑、导入、导出和删除 Engine 用户词库中的快捷短语</small></span><span><button type="button" className="secondary" disabled={phraseBusy} onClick={() => void loadPhrases()}>查询</button> <button type="button" className="secondary" disabled={phraseBusy} onClick={() => setPhraseForm({ key: "", value: "", weight: 0, previous: null })}>新增短语</button> <button type="button" className="secondary" disabled={phraseBusy} onClick={exportPhrases}>导出</button><label className="secondary">导入<input hidden type="file" accept=".txt,text/plain" disabled={phraseBusy} onChange={event => { const file = event.target.files?.[0]; if (file) void importPhrases(file); event.currentTarget.value = ""; }} /></label></span></div>
          <label>编码前缀 <input value={phraseSearch} placeholder="留空查看全部" onChange={event => setPhraseSearch(event.target.value)} /></label>
          {phraseError && <p role="alert" className="error">{phraseError}</p>}
          {phraseForm && <div className="quick-phrase-form"><label>编码 <input value={phraseForm.key} onChange={event => setPhraseForm({ ...phraseForm, key: event.target.value })} /></label><label>短语 <input value={phraseForm.value} onChange={event => setPhraseForm({ ...phraseForm, value: event.target.value })} /></label><label>权重 <input type="number" value={phraseForm.weight} onChange={event => setPhraseForm({ ...phraseForm, weight: Number(event.target.value) })} /></label><button type="button" disabled={phraseBusy} onClick={() => void savePhrase()}>保存</button><button type="button" className="secondary" disabled={phraseBusy} onClick={() => setPhraseForm(null)}>取消</button></div>}
          {phrases.length === 0 ? <p className="dict-empty">点击查询后查看快捷短语</p> : <ul className="quick-phrase-list">{phrases.filter(entry => entry.key.startsWith(phraseSearch)).map((entry, index) => <li key={`${entry.key}-${entry.value}-${index}`}><span><code>{entry.key}</code>　{entry.value}　<small>{entry.weight}</small></span><span><button type="button" className="secondary" disabled={phraseBusy} onClick={() => setPhraseForm({ key: entry.key, value: entry.value, weight: entry.weight, previous: entry })}>编辑</button> <button type="button" className="secondary" disabled={phraseBusy} onClick={() => void removePhrase(entry)}>删除</button></span></li>)}</ul>}
        </div> : <div className="section"><div className="section-title">用户词库</div><p className="notice">当前宿主未提供词库管理接口。</p></div>}
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "cloud_dictionary"} aria-label="云词库">
        {client.cloudDictionary ? <div className="section" role="region" aria-label="云词库管理">
          <div className="section-header"><span className="section-title">云词库<small>管理当前账户的云端词条。</small></span><span><button type="button" className="secondary" onClick={() => void loadCloud(0)}>查询</button> <button type="button" className="secondary" onClick={() => void loadCatalog()}>完整目录</button> <button type="button" className="secondary" onClick={() => void syncCloud()}>同步变更</button> <button type="button" className="secondary" onClick={() => setCloudForm({ code: "", word: "", weight: 100000 })}>新增</button></span></div>
          <label>词库 <select value={cloudKind} onChange={event => setCloudKind(event.target.value as CloudDictionaryKind)}><option value="pinyin">拼音</option><option value="wubi">五笔</option><option value="quick">快捷短语</option><option value="english">英文</option></select></label>
          <label>搜索 <input value={cloudSearch} onChange={event => setCloudSearch(event.target.value)} onKeyDown={event => { if (event.key === "Enter") void loadCloud(0); }} /></label>
          {cloudError && <p role="alert" className="error">{cloudError}</p>}
          <ul className="quick-phrase-list">{cloudEntries.map(entry => <li key={entry.id}><span><code>{entry.code}</code>　{entry.word}　<small>{entry.weight}</small></span><span><button type="button" className="secondary" onClick={() => { const word = window.prompt("词条", entry.word); if (word && client.cloudDictionary) void client.cloudDictionary.update(entry, { code: entry.code, word, weight: entry.weight }).then(() => loadCloud(cloudOffset)); }}>编辑</button> <button type="button" className="secondary" onClick={() => { if (client.cloudDictionary && window.confirm("删除此云词条？")) void client.cloudDictionary.remove(entry).then(() => loadCloud(cloudOffset)); }}>删除</button></span></li>)}</ul>
          {catalogEntries.length > 0 && <p className="notice">目录查询返回 {catalogEntries.length} 条候选。</p>}
          {cloudForm && <div className="quick-phrase-form"><label>编码 <input value={cloudForm.code} onChange={event => setCloudForm({ ...cloudForm, code: event.target.value })} /></label><label>词条 <input value={cloudForm.word} onChange={event => setCloudForm({ ...cloudForm, word: event.target.value })} /></label><label>权重 <input type="number" value={cloudForm.weight} onChange={event => setCloudForm({ ...cloudForm, weight: Number(event.target.value) })} /></label><button type="button" onClick={() => { if (client.cloudDictionary && cloudForm.code && cloudForm.word) void client.cloudDictionary.add(cloudKind, cloudForm).then(() => { setCloudForm(null); return loadCloud(cloudOffset); }); }}>保存</button><button type="button" className="secondary" onClick={() => setCloudForm(null)}>取消</button></div>}
          <div><button type="button" className="secondary" disabled={cloudOffset === 0} onClick={() => void loadCloud(Math.max(0, cloudOffset - 100))}>上一页</button> <button type="button" className="secondary" disabled={!cloudHasMore} onClick={() => void loadCloud(cloudOffset + 100)}>下一页</button></div>
        </div> : <div className="section"><p className="notice">当前宿主未提供云词库接口。</p></div>}
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "tools"} aria-label="实用功能">
        <div className="section"><label className="section-header"><span className="section-title">剪贴板管理<small>开启后记录复制的文本；关闭后立即清空已保存记录。</small></span><input aria-label="剪贴板管理" className="toggle" type="checkbox" checked={draft.clipboard_history ?? true} onChange={event => { setDraft({ ...draft, clipboard_history: event.target.checked }); if (!event.target.checked) { void client.clipboard?.clear(); setClipboardEntries([]); } }} /></label>{client.clipboard?.sync && <button type="button" className="secondary" onClick={() => void client.clipboard!.sync!().then(setClipboardEntries)}>从系统剪贴板同步</button>}{client.clipboard?.list && <div className="help-list" aria-label="剪贴板历史">{clipboardEntries.length === 0 ? <small>暂无历史记录</small> : clipboardEntries.map(entry => <div key={entry}><span>{entry}</span>{client.clipboard?.copy && <button type="button" className="secondary" onClick={() => void client.clipboard!.copy!(entry)}>重新复制</button>}</div>)}</div>}</div>
        <div className="section"><label className="section-header"><span className="section-title">云候选<small>输入组合期间向云端请求一个额外候选；请求不包含已上屏文本。</small></span><input aria-label="云候选" className="toggle" type="checkbox" checked={draft.cloud_candidates ?? true} onChange={event => setDraft({ ...draft, cloud_candidates: event.target.checked })} /></label></div>
        {localModeRows.map(([key, label, description]) => <div className="section" key={key}>
          <label className="section-header"><span className="section-title">{label}<small>{description}</small></span><input className="toggle" type="checkbox" checked={localModes[key]} onChange={event => setDraft({ ...draft, local_modes: { ...localModes, [key]: event.target.checked } })} /></label>
        </div>)}
      </fieldset>
      <footer className="settings-actions"><span>{dirty ? "有未保存的修改" : ""}</span><button type="submit" disabled={busy || !dirty}>{busy ? "处理中…" : "保存设置"}</button></footer>
    </form>}
    <button className="secondary" disabled={busy} onClick={() => {
      if (!dirty || window.confirm("重新读取会放弃尚未保存的修改，是否继续？")) void reload();
    }}>重新读取</button>
  </div></main></div>;
}
