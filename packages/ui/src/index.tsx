import { useEffect, useRef, useState } from "react";
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
  { id: "shortcuts", title: "快捷键", icon: new URL("./assets/shortcut.svg", import.meta.url).href },
  { id: "tools", title: "实用功能", icon: new URL("./assets/utilities.svg", import.meta.url).href },
] as const;
const logo = new URL("./assets/msime.svg", import.meta.url).href;

export type Preferences = {
  theme?: "dark" | "light" | "system";
  settings_theme?: "follow" | "dark" | "light";
  candidate_theme?: "follow" | "dark" | "light";
  candidate_layout?: "horizontal" | "vertical";
  candidate_preedit_style?: "pinyin" | "empty";
  tsf_preedit_style?: "raw" | "pinyin" | "empty";
  ui_backend?: "direct2d" | "webview2";
  candidate_follow_cursor?: boolean;
  local_modes?: LocalModePreferences;
  clipboard_history?: boolean;
  mixed_input?: MixedInputPreferences;
  frequency?: FrequencyPreferences;
  word_character?: { enabled: boolean; keys: "brackets" | "minus_equal" };
  navigation?: NavigationPreferences;
  scheme: "quanpin" | "shuangpin" | "wubi" | "japanese";
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
};
export type Snapshot = { format_version: number; revision: number; preferences: Preferences };
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
}
export type DictionaryEntry = { kind: "pinyin" | "wubi" | "quick_phrase" | "english"; key: string; value: string; weight: number };
export interface DictionaryClient {
  list(offset: number, limit: number): Promise<{ entries: DictionaryEntry[]; has_more: boolean }>;
  edit(previous: DictionaryEntry | null, replacement: DictionaryEntry | null, request_id: string): Promise<void>;
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
  useEffect(() => { setActive(Math.max(0, options.findIndex(([option]) => option === value))); }, [value, options]);
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
      case "frequency_invalid": return "调频触发频次和步长必须为 1 到 10。";
      case "mixed_input_invalid": return "中英混输触发字符数必须为 1 到 8。";
      case "key_conflict": return "以词定字和翻页不能使用同一组快捷键。";
      case "format": return "配置文件无法读取或版本较新，原文件已保留。";
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
  const [phrases, setPhrases] = useState<DictionaryEntry[]>([]);
  const [phraseBusy, setPhraseBusy] = useState(false);
  const [phraseError, setPhraseError] = useState("");
  useEffect(() => {
    const mode = draft?.settings_theme && draft.settings_theme !== "follow" ? draft.settings_theme : (draft?.theme ?? "dark");
    const resolved = mode === "system" ? (window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark") : mode;
    document.documentElement.dataset.theme = resolved;
  }, [draft?.theme]);
  const [phraseForm, setPhraseForm] = useState<{ key: string; value: string; weight: number; previous: DictionaryEntry | null } | null>(null);
  const [phraseSearch, setPhraseSearch] = useState("");

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
  const wordCharacter = draft?.word_character ?? defaultWordCharacter;
  const frequency = draft?.frequency ?? defaultFrequency;
  const mixedInput = draft?.mixed_input ?? defaultMixedInput;
  const localModes = draft?.local_modes ?? defaultLocalModes;
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
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "about"} aria-label="关于">
        <div className="section about-hero"><img src={logo} alt="水杉 IME" /><div><h2>水杉 IME</h2><p>跨平台中文输入法客户端预览版</p></div></div>
        <div className="section about-links">
          <div className="about-row"><span>当前版本</span><strong>客户端预览版</strong></div>
          <a className="about-row about-link" href="https://github.com/metasequoiaime/MSIME-Client" target="_blank" rel="noreferrer"><span>开源项目</span><span aria-hidden="true">↗</span></a>
          <a className="about-row about-link" href="https://github.com/metasequoiaime/MSIME-Client/blob/develop/LICENSE" target="_blank" rel="noreferrer"><span>开源许可协议</span><span aria-hidden="true">↗</span></a>
        </div>
        <p className="about-disclaimer">本客户端仍在持续迁移 Windows 版功能与界面；部分平台能力可能尚未接入。</p>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "feedback"} aria-label="反馈">
        <div className="section feedback-hero"><div className="section-title">告诉我们你的想法</div><p>遇到问题或有功能建议时，可以通过以下渠道提交和交流。</p></div>
        <div className="feedback-list">
          <div className="section feedback-card"><div className="feedback-icon">GH</div><div className="feedback-body"><div className="feedback-title">GitHub Issues</div><p>适合提交可复现的问题、功能建议和开发讨论。</p><a className="feedback-link" href="https://github.com/metasequoiaime/MSIME-Windows/issues" target="_blank" rel="noreferrer">查看 Issues ↗</a></div></div>
          <div className="section feedback-card"><div className="feedback-icon">TG</div><div className="feedback-body"><div className="feedback-title">Telegram 群组</div><p>面向国际用户和开发者的即时讨论频道。</p><a className="feedback-link" href="https://t.me/msimegroup" target="_blank" rel="noreferrer">打开群组 ↗</a></div></div>
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
        <div className="section capability-status"><span className="capability-dot" aria-hidden="true" /><div><strong>宿主尚未接入</strong><small>当前客户端已预留设置入口，屏幕键盘运行时将在后续平台增量中接入。</small></div></div>
        <div className="section"><div className="section-title">使用说明</div><div className="help-list"><div><strong>打开方式</strong><span>接入后可从输入法工具栏或系统托盘打开屏幕键盘。</span></div><div><strong>主题同步</strong><span>屏幕键盘将跟随全局主题和字号设置。</span></div></div></div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "voice_input"} aria-label="语音输入">
        <div className="section capability-hero"><div className="section-title">语音输入</div><p>按住快捷键录音，将语音转换为文字并插入当前应用。</p></div>
        <div className="section capability-status"><span className="capability-dot" aria-hidden="true" /><div><strong>语音宿主尚未接入</strong><small>Windows 版支持豆包、OpenAI、SiliconFlow 和 Groq 等服务；当前客户端尚未接入录音与语音服务配置。</small></div></div>
        <div className="section"><div className="section-title">接入准备</div><div className="help-list"><div><strong>服务凭据</strong><span>接入后将在此配置 ASR 提供商和 API Token。请勿把凭据提交到日志或代码仓库。</span></div><div><strong>隐私提示</strong><span>启用后录音会上传到所选服务；离线状态下不会产生语音识别结果。</span></div><div><strong>输入方式</strong><span>接入后支持批量识别和流式预编辑，并可取消当前语音会话。</span></div></div></div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "handwriting"} aria-label="手写识别">
        <div className="section capability-hero"><div className="section-title">手写识别</div><p>在手写面板中书写汉字，识别结果将作为候选项插入当前应用。</p></div>
        <div className="section capability-status"><span className="capability-dot" aria-hidden="true" /><div><strong>手写宿主尚未接入</strong><small>Windows 版通过系统手写识别面板提供此能力；当前客户端尚未接入原生手写面板。</small></div></div>
        <div className="section"><div className="section-title">使用准备</div><div className="help-list"><div><strong>安装语言组件</strong><span>Windows 用户需安装“中文手写包”：设置 → 时间和语言 → 语言和区域 → 中文 → 语言选项 → 手写。</span></div><div><strong>打开方式</strong><span>接入后可从输入法工具栏或托盘菜单打开手写识别面板。</span></div><div><strong>识别结果</strong><span>面板返回的候选项会交给输入运行时，确认后提交到当前应用。</span></div></div></div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "ai_assistant"} aria-label="AI 辅助">
        <div className="section capability-hero"><div className="section-title">AI 辅助</div><p>使用兼容 Chat Completions 的服务异步生成联想候选，帮助快速完成输入。</p></div>
        <div className="section capability-status"><span className="capability-dot" aria-hidden="true" /><div><strong>AI 宿主尚未接入</strong><small>Windows 版支持 DeepSeek、OpenAI、SiliconFlow 和 Groq；当前客户端尚未接入在线 AI 请求与候选管线。</small></div></div>
        <div className="section"><div className="section-title">配置项预览</div><div className="help-list"><div><strong>启用 AI 联想</strong><span>接入后可在全拼和双拼输入时异步生成额外候选。</span></div><div><strong>API 配置</strong><span>每个服务商独立保存 Token，并支持自定义模型与接口地址。</span></div><div><strong>提示词</strong><span>可选择预设提示词或编辑自定义提示词；敏感凭据不会写入日志。</span></div></div></div>
      </fieldset>
      <fieldset disabled={busy} hidden={page !== "floating_toolbar"} aria-label="悬浮工具栏">
        <div className="section capability-hero"><div className="section-title">悬浮工具栏</div><p>在桌面显示输入法状态和常用功能，便于快速切换输入模式。</p></div>
        <div className="section capability-status"><span className="capability-dot" aria-hidden="true" /><div><strong>工具栏宿主尚未接入</strong><small>Windows 版支持工具栏显示、缩放、位置和组件选择；当前客户端尚未接入原生桌面工具栏。</small></div></div>
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
          <div className="section-header frequency-option-row"><span className="section-title">触发字符数<small>预编辑字母达到该长度后才出现英文候选项</small></span><CustomDropdown ariaLabel="触发字符数" disabled={!mixedInput.english} value={String(mixedInput.minimum_prefix)} options={[1, 2, 3, 4, 5, 6, 7, 8].map(value => [String(value), String(value)] as [string, string])} onChange={value => setDraft({ ...draft, mixed_input: { ...mixedInput, minimum_prefix: Number(value) } })} /></div>
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
      <fieldset disabled={busy} hidden={page !== "tools"} aria-label="实用功能">
        <div className="section"><label className="section-header"><span className="section-title">剪贴板管理<small>开启后记录复制的文本；关闭后立即清空已保存记录。</small></span><input className="toggle" type="checkbox" checked={draft.clipboard_history ?? true} onChange={event => setDraft({ ...draft, clipboard_history: event.target.checked })} /></label></div>
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
