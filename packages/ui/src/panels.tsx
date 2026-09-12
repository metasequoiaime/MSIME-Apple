import { useEffect, useRef, useState, type PointerEvent } from "react";
import { fallbackEmojiGroups, fallbackKaomojiGroups, fallbackSymbolGroups, type EmojiCatalogGroup, type EmojiCatalogItem } from "./emoji-catalog";

export interface KeyboardInputRequest {
  virtual_key: number;
  shift: boolean;
  modifiers: { ctrl: boolean; alt: boolean; win: boolean };
  include_sticky_modifiers: boolean;
}

export interface InkPoint { x: number; y: number; }
export interface InkStroke { points: InkPoint[]; }
export interface HandwritingRecognitionRequest { language: string; strokes: InkStroke[]; }
export interface HandwritingRecognitionResult { candidates: string[]; }

export interface PanelClient {
  close(): Promise<void>;
  beginWindowDrag?(): Promise<void>;
  rememberInputTarget?(): Promise<void>;
  sendKey?(request: KeyboardInputRequest): Promise<void>;
  sendText?(text: string): Promise<void>;
  recognizeHandwriting?(request: HandwritingRecognitionRequest): Promise<HandwritingRecognitionResult>;
  submitHandwritingCandidate?(candidate: string): Promise<void>;
}

export interface VoicePanelClient extends PanelClient {
  loadVoiceLanguage?(): Promise<string>;
  recognizeVoice?(language: string): Promise<{ text: string }>;
  onVoiceUpdate?(listener: (update: { text: string; final: boolean }) => void): Promise<() => void>;
  cancelVoice?(): Promise<void>;
  sendVoiceText?(text: string): Promise<void>;
}

function validVoiceLanguage(value: string) {
  return value.length > 0 && value.length <= 64 && !Array.from(value).some(character => {
    const code = character.codePointAt(0) ?? 0;
    return code <= 0x1f || code === 0x7f;
  });
}

export type CloudClipboardAction =
  | { operation: "list"; search: string }
  | { operation: "add"; text: string }
  | { operation: "delete"; id: string }
  | { operation: "set_enabled"; enabled: boolean };
export type CloudClipboardItem = { id: string; text: string };
export interface CloudClipboardPanelClient extends PanelClient {
  request(action: CloudClipboardAction): Promise<{ items?: CloudClipboardItem[]; enabled?: boolean }>;
}

export type CloudDictionaryKind = "pinyin" | "wubi" | "quick" | "english";
export type CloudDictionaryFileFormat = "standard" | "windows" | "hans";
export type CloudDictionaryAction =
  | { operation: "list"; kind: CloudDictionaryKind; offset: number; search: string }
  | { operation: "add"; kind: CloudDictionaryKind; code: string; word: string; weight: number }
  | { operation: "update"; kind: CloudDictionaryKind; id: string; code: string; word: string; weight: number; revision: number }
  | { operation: "delete"; kind: CloudDictionaryKind; id: string; revision: number }
  | { operation: "import"; kind: CloudDictionaryKind; format: CloudDictionaryFileFormat; text: string }
  | { operation: "export"; kind: CloudDictionaryKind; format: Exclude<CloudDictionaryFileFormat, "hans"> };
export type CloudDictionaryEntry = { id: string; kind: CloudDictionaryKind; code: string; word: string; weight: number; revision: number };
export type CloudDictionaryResponse = { entries?: CloudDictionaryEntry[]; has_more?: boolean; offset?: number; text?: string; content?: string; filename?: string };
export interface CloudDictionaryPanelClient extends PanelClient {
  request(action: CloudDictionaryAction): Promise<CloudDictionaryResponse>;
}

export interface EmojiPanelClient extends PanelClient {
  copyText?(text: string): Promise<void>;
  clipboard?: {
    list?(): Promise<string[]>;
    sync?(): Promise<string[]>;
    copy?(text: string): Promise<void>;
  };
  loadCatalog?(): Promise<{
    emoji: EmojiCatalogGroup[];
    kaomoji: EmojiCatalogGroup[];
    symbols: EmojiCatalogGroup[];
  }>;
}

type Modifier = "Shift" | "Caps Lock" | "Ctrl" | "Alt" | "Win";
type KeyboardKey = { label: string; shifted?: string; virtualKey: number; modifier?: Modifier; };
const key = (label: string, virtualKey: number, shifted?: string): KeyboardKey => ({ label, virtualKey, shifted });
const modifier = (label: Modifier, virtualKey: number): KeyboardKey => ({ label, virtualKey, modifier: label });
const keyboardRows: KeyboardKey[][] = [
  [key("Num Lock", 0x90), key("Num 0", 0x60), key("Num 1", 0x61), key("Num 2", 0x62), key("Num 3", 0x63), key("Num 4", 0x64), key("Num 5", 0x65), key("Num 6", 0x66), key("Num 7", 0x67), key("Num 8", 0x68), key("Num 9", 0x69), key("Num *", 0x6a), key("Num +", 0x6b), key("Num -", 0x6d), key("Num /", 0x6f), key("Num .", 0x6e)],
  [key("Esc", 0x1b), key("F1", 0x70), key("F2", 0x71), key("F3", 0x72), key("F4", 0x73), key("F5", 0x74), key("F6", 0x75), key("F7", 0x76), key("F8", 0x77), key("F9", 0x78), key("F10", 0x79), key("F11", 0x7a), key("F12", 0x7b), key("PrtSc", 0x2c), key("Scroll", 0x91), key("Pause", 0x13), key("Ins", 0x2d), key("Home", 0x24), key("End", 0x23), key("PgUp", 0x21), key("PgDn", 0x22)],
  [key("`", 0xc0, "~"), ...[..."1234567890"].map((label, index) => key(label, label.charCodeAt(0), ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")"][index])), key("-", 0xbd, "_"), key("=", 0xbb, "+"), key("Backspace", 0x08)],
  [key("Tab", 0x09), ...[..."QWERTYUIOP"].map(label => key(label.toLowerCase(), label.charCodeAt(0))), key("[", 0xdb, "{"), key("]", 0xdd, "}"), key("\\", 0xdc, "|")],
  [modifier("Caps Lock", 0x14), ...[..."ASDFGHJKL"].map(label => key(label.toLowerCase(), label.charCodeAt(0))), key(";", 0xba, ":"), key("'", 0xde, '"'), key("Enter", 0x0d)],
  [modifier("Shift", 0x10), ...[..."ZXCVBNM"].map(label => key(label.toLowerCase(), label.charCodeAt(0))), key(",", 0xbc, "<"), key(".", 0xbe, ">"), key("/", 0xbf, "?"), modifier("Shift", 0x10)],
  [modifier("Ctrl", 0x11), modifier("Win", 0x5b), modifier("Alt", 0x12), key("Space", 0x20, " "), modifier("Alt", 0x12), modifier("Win", 0x5b), key("Del", 0x2e), key("←", 0x25), key("↑", 0x26), key("↓", 0x28), key("→", 0x27), modifier("Ctrl", 0x11)],
];
const nineKeyRows: KeyboardKey[][] = [
  [key("1", 0x31), key("2", 0x32), key("3", 0x33)],
  [key("4", 0x34), key("5", 0x35), key("6", 0x36)],
  [key("7", 0x37), key("8", 0x38), key("9", 0x39)],
  [key("Backspace", 0x08), key("0", 0x30), key("Enter", 0x0d)],
  [key("Space", 0x20, " ")],
];

function modifierPrefix(modifiers: Set<Modifier>) {
  return ["Ctrl", "Alt", "Win", "Shift"].filter(value => modifiers.has(value as Modifier)).join("+");
}
// Width ratios from Windows KeyboardPanel.cpp at 04a8df56f86312474a069f4335a1b58da7afaa9e.
function keyboardKeyWeight(label: string, row: number, index: number) {
  if (row === 4) return label === "Space" ? 6.7 : 1.25;
  if (label === "Backspace") return 1.9;
  if (label === "Tab") return 1.5;
  if (label === "\\") return 1.4;
  if (label === "Caps Lock") return 1.85;
  if (label === "Enter") return 2;
  if (label === "Shift") return index === 0 ? 2.35 : 2.15;
  return 1;
}
function isImeCommitKey(virtualKey: number) {
  return [0x20, 0x0d, 0x09, 0x08, 0x2e].includes(virtualKey) || (virtualKey >= 0x30 && virtualKey <= 0x39);
}

export function KeyboardPanel({ client, theme = "dark", layout = "twenty_six_key" }: { client: PanelClient; theme?: "dark" | "light"; layout?: "twenty_six_key" | "nine_key" }) {
  const [activeLayout, setActiveLayout] = useState(layout);
  const rows = activeLayout === "nine_key" ? nineKeyRows : keyboardRows;
  const pendingDrag = useRef<{ id: number; x: number; y: number } | null>(null);
  useEffect(() => {
    const reset = () => { pendingDrag.current = null; };
    window.addEventListener("blur", reset);
    return () => { reset(); window.removeEventListener("blur", reset); };
  }, [client]);
  const [activeModifiers, setActiveModifiers] = useState<Set<Modifier>>(new Set());
  const [notice, setNotice] = useState("Touch keyboard");
  useEffect(() => {
    if (client.rememberInputTarget) void client.rememberInputTarget().catch(() => setNotice("未能记录前台输入窗口"));
  }, [client]);
  function toggleModifier(keyToToggle: Modifier) {
    setActiveModifiers(current => {
      const next = new Set(current);
      if (next.has(keyToToggle)) next.delete(keyToToggle); else next.add(keyToToggle);
      return next;
    });
  }
  function pressKey(keyToPress: KeyboardKey) {
    if (keyToPress.modifier) { toggleModifier(keyToPress.modifier); return; }
    const shift = activeModifiers.has("Shift");
    const caps = activeModifiers.has("Caps Lock");
    const letter = keyToPress.label.length === 1 && /[a-z]/i.test(keyToPress.label);
    // Upstream shifted key faces take precedence over Caps/Shift inversion.
    const withShift = shift || (letter && caps);
    const modifiers = { ctrl: activeModifiers.has("Ctrl"), alt: activeModifiers.has("Alt"), win: activeModifiers.has("Win") };
    const includeStickyModifiers = !isImeCommitKey(keyToPress.virtualKey);
    const prefix = modifierPrefix(activeModifiers);
    const displayedLabel = withShift ? (keyToPress.shifted || (letter ? keyToPress.label.toUpperCase() : keyToPress.label)) : keyToPress.label;
    const description = `${prefix}${prefix ? "+" : ""}${displayedLabel}`;
    const request: KeyboardInputRequest = { virtual_key: keyToPress.virtualKey, shift: withShift && includeStickyModifiers, modifiers, include_sticky_modifiers: includeStickyModifiers };
    setNotice(client.sendKey ? `正在发送：${description}` : `已准备：${description}（等待宿主注入能力）`);
    if (client.sendKey) void client.sendKey(request).then(() => setNotice(`已发送：${description}`)).catch(() => setNotice(`发送失败：${description}`));
    if (shift) setActiveModifiers(current => { const next = new Set(current); next.delete("Shift"); return next; });
  }
  return <main className="native-panel keyboard-panel" data-keyboard-theme={theme} data-keyboard-layout={activeLayout} aria-label="屏幕键盘">
    <header className="native-panel-header"
      onPointerDown={event => {
        pendingDrag.current = null;
        if (!client.beginWindowDrag || event.button !== 0 || (event.target as Element).closest("button")) return;
        pendingDrag.current = { id: event.pointerId, x: event.clientX, y: event.clientY };
      }}
      onPointerMove={event => {
        const pending = pendingDrag.current;
        if (!pending || pending.id !== event.pointerId) return;
        if (event.buttons !== 1) { pendingDrag.current = null; return; }
        if (Math.abs(event.clientX - pending.x) + Math.abs(event.clientY - pending.y) < 2) return;
        pendingDrag.current = null;
        void (async () => {
          try { await client.beginWindowDrag?.(); }
          catch { setNotice("无法移动窗口，请重试。"); }
        })();
      }}
      onPointerUp={() => { pendingDrag.current = null; }}
      onPointerCancel={() => { pendingDrag.current = null; }}
      onPointerLeave={() => { pendingDrag.current = null; }}>
      <span className="keyboard-panel-notice" role="status" title={notice}>{notice}</span><button type="button" aria-label="切换键盘布局" onClick={() => setActiveLayout(value => value === "nine_key" ? "twenty_six_key" : "nine_key")}>{activeLayout === "nine_key" ? "全键" : "九宫格"}</button><button type="button" aria-label="关闭" onClick={() => void client.close()}>×</button></header>
    <div className="keyboard-panel-body">
      <div className="keyboard-layout">
        {rows.map((row, rowIndex) => <div className="keyboard-row" key={rowIndex}>{row.map((keyToRender, keyIndex) => {
          const letter = keyToRender.label.length === 1 && /[a-z]/i.test(keyToRender.label);
          const shifted = activeModifiers.has("Shift") && keyToRender.label.length === 1;
          const label = shifted ? (keyToRender.shifted || (letter ? keyToRender.label.toUpperCase() : keyToRender.label)) : keyToRender.label;
          return <button type="button" key={`${keyToRender.label}-${keyIndex}`} style={{ flexGrow: keyboardKeyWeight(keyToRender.label, rowIndex, keyIndex) }} aria-pressed={keyToRender.modifier ? activeModifiers.has(keyToRender.modifier) : undefined} className={`keyboard-key${keyToRender.modifier ? " modifier" : ""}${keyToRender.label === "Space" ? " space" : ""}${keyToRender.label.length > 1 ? " wide" : ""}${keyToRender.modifier && activeModifiers.has(keyToRender.modifier) ? " active" : ""}`} onClick={() => pressKey(keyToRender)}>{label}</button>;
        })}</div>)}
      </div>
    </div>
  </main>;
}

type Point = InkPoint;
function pointFromEvent(event: PointerEvent<SVGSVGElement>): Point {
  const rect = event.currentTarget.getBoundingClientRect();
  const width = rect.width || 420;
  const height = rect.height || 420;
  return { x: Math.max(0, Math.min(420, ((event.clientX - rect.left) / width) * 420)), y: Math.max(0, Math.min(420, ((event.clientY - rect.top) / height) * 420)) };
}

export function HandwritingPanel({ client }: { client: PanelClient }) {
  const [strokes, setStrokes] = useState<InkStroke[]>([]);
  const [drawing, setDrawing] = useState<Point[]>([]);
  const [candidates, setCandidates] = useState<string[]>([]);
  const [notice, setNotice] = useState("请在左侧书写，松开鼠标后自动识别");
  const recognitionRevision = useRef(0);
  async function recognize(nextStrokes: InkStroke[]) {
    const revision = ++recognitionRevision.current;
    if (!client.recognizeHandwriting) { setCandidates([]); setNotice("识别结果需由宿主提供"); return; }
    try {
      const result = await client.recognizeHandwriting({ language: "zh-CN", strokes: nextStrokes });
      if (revision !== recognitionRevision.current) return;
      setCandidates(result.candidates);
      setNotice(result.candidates.length ? "点击候选结果即可提交" : "未识别到内容，请确认已安装中文手写包");
    } catch { if (revision === recognitionRevision.current) { setCandidates([]); setNotice("手写识别失败，请确认识别服务已启动"); } }
  }
  function start(event: PointerEvent<SVGSVGElement>) { event.currentTarget.setPointerCapture?.(event.pointerId); setDrawing([pointFromEvent(event)]); }
  function move(event: PointerEvent<SVGSVGElement>) {
    if (!drawing.length) return;
    const nextPoint = pointFromEvent(event);
    setDrawing(current => [...current, nextPoint]);
  }
  function end() {
    if (!drawing.length) return;
    const nextStrokes = [...strokes, { points: drawing }];
    setStrokes(nextStrokes); setDrawing([]); void recognize(nextStrokes);
  }
  function undo() {
    const nextStrokes = strokes.slice(0, -1);
    setStrokes(nextStrokes); setCandidates([]);
    if (!nextStrokes.length) setNotice("请在左侧书写，松开鼠标后自动识别"); else void recognize(nextStrokes);
  }
  function clear() { recognitionRevision.current++; setStrokes([]); setDrawing([]); setCandidates([]); setNotice("请在左侧书写，松开鼠标后自动识别"); }
  function chooseCandidate(candidate: string) {
    if (!client.submitHandwritingCandidate) { setNotice(`已选择：${candidate}（等待宿主提交能力）`); return; }
    void client.submitHandwritingCandidate(candidate).then(() => setNotice(`已提交：${candidate}`)).catch(() => setNotice(`提交失败：${candidate}`));
  }
  const renderStrokes = [...strokes, ...(drawing.length ? [{ points: drawing }] : [])];
  return <main className="native-panel handwriting-panel" aria-label="手写识别板">
    <header className="native-panel-header"><span>水杉手写识别板</span><button type="button" aria-label="关闭" onClick={() => void client.close()}>×</button></header>
    <div className="handwriting-panel-body">
      <section className="ink-canvas-section"><svg className="ink-canvas" viewBox="0 0 420 420" onPointerDown={start} onPointerMove={move} onPointerUp={end} onPointerCancel={end} aria-label="手写画布">{renderStrokes.map((stroke, index) => <polyline key={index} points={stroke.points.map(({ x, y }) => `${x},${y}`).join(" ")} />)}{!renderStrokes.length && <text x="210" y="215" textAnchor="middle">请在这里书写</text>}</svg><div className="handwriting-actions"><button type="button" onClick={undo}>↶ 撤销</button><button type="button" onClick={clear}>× 重写</button></div></section>
      <section className="recognition-section"><h2>识别结果</h2><div className="handwriting-candidate-grid">{candidates.map(candidate => <button type="button" key={candidate} onClick={() => chooseCandidate(candidate)}>{candidate}</button>)}</div><p role="status">{notice}</p></section>
    </div>
  </main>;
}

export function VoicePanel({ client }: { client: VoicePanelClient }) {
  const [language, setLanguage] = useState("zh-CN");
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const busyRef = useRef(false);
  const [notice, setNotice] = useState("点击开始后由宿主录音并进行语音识别");

  useEffect(() => {
    if (!client.loadVoiceLanguage) return;
    void client.loadVoiceLanguage().then(next => {
      if (validVoiceLanguage(next)) setLanguage(next);
    }).catch(() => undefined);
  }, [client]);

  useEffect(() => {
    if (!client.rememberInputTarget) return;
    void client.rememberInputTarget().catch(() => setNotice("未能记录前台输入窗口"));
  }, [client]);

  useEffect(() => () => {
    if (busyRef.current && client.cancelVoice) void client.cancelVoice().catch(() => undefined);
  }, [client]);

  useEffect(() => {
    if (!client.onVoiceUpdate) return;
    let active = true;
    let unlisten: (() => void) | undefined;
    void client.onVoiceUpdate(update => {
      if (!active) return;
      setText(update.text);
      setNotice(update.final ? (update.text ? "识别完成，点击提交即可输入" : "没有识别到内容") : "正在录音并识别…");
    }).then(stop => {
      if (active) unlisten = stop;
      else stop();
    }).catch(() => undefined);
    return () => {
      active = false;
      unlisten?.();
    };
  }, [client]);

  async function recognize() {
    if (!client.recognizeVoice) {
      setNotice("当前宿主未提供语音识别能力");
      return;
    }
    if (!validVoiceLanguage(language)) {
      setNotice("请输入有效的识别语言码");
      return;
    }
    busyRef.current = true;
    setBusy(true);
    setText("");
    setNotice("正在录音并识别…");
    try {
      const result = await client.recognizeVoice(language);
      setText(result.text);
      setNotice(result.text ? "识别完成，点击提交即可输入" : "没有识别到内容");
    } catch {
      setNotice("语音识别失败，请确认录音服务已启动");
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }

  async function submit() {
    const send = client.sendVoiceText ?? client.sendText;
    if (!text || !send) return;
    try {
      await send(text);
      setNotice(`已提交：${text}`);
      setText("");
    } catch {
      setNotice("提交失败，前台输入窗口可能已关闭");
    }
  }

  async function close() {
    if (busy && client.cancelVoice) {
      try { await client.cancelVoice(); } catch { /* close even if provider is gone */ }
    }
    await client.close();
  }

  return <main className="native-panel voice-panel" aria-label="语音输入">
    <header className="native-panel-header"><span>水杉语音输入</span><button type="button" aria-label="关闭" onClick={() => void close()}>×</button></header>
    <div className="voice-panel-body">
      <div className="voice-panel-icon" aria-hidden="true">🎙</div>
      <h1>语音输入</h1>
      <p className="voice-panel-description">录音和识别由已配置的 Linux provider 服务完成，输入法不会保存原始音频。</p>
      <label className="voice-panel-language">识别语言<input value={language} maxLength={64} list="voice-language-options" onChange={event => setLanguage(event.target.value)} disabled={busy} /><datalist id="voice-language-options"><option value="zh-CN">中文（普通话）</option><option value="en-US">English</option><option value="ja-JP">日本語</option></datalist></label>
      <button type="button" className="voice-panel-record" onClick={() => void recognize()} disabled={busy}>{busy ? "正在识别…" : "开始录音"}</button>
      <textarea aria-label="识别结果" value={text} maxLength={4096} onChange={event => setText(event.target.value)} placeholder="识别结果会显示在这里" rows={4} />
      <button type="button" className="voice-panel-submit" onClick={() => void submit()} disabled={!text || !(client.sendVoiceText ?? client.sendText) || busy}>提交到当前窗口</button>
      <p className="voice-panel-notice" role="status">{notice}</p>
    </div>
  </main>;
}

function cloudClipboardItems(value: { items?: CloudClipboardItem[] }) {
  return Array.isArray(value.items)
    ? value.items.filter(item => item && typeof item.id === "string" && typeof item.text === "string")
    : [];
}

export function CloudClipboardPanel({ client }: { client: CloudClipboardPanelClient }) {
  const [search, setSearch] = useState("");
  const [format, setFormat] = useState<CloudDictionaryFileFormat>("standard");
  const [items, setItems] = useState<CloudClipboardItem[]>([]);
  const [draft, setDraft] = useState("");
  const [enabled, setEnabled] = useState(true);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("只上传你明确选择的内容");

  async function refresh(nextSearch = search) {
    setBusy(true);
    try {
      const result = await client.request({ operation: "list", search: nextSearch });
      setItems(cloudClipboardItems(result));
      if (typeof result.enabled === "boolean") setEnabled(result.enabled);
      setNotice("云剪贴板已刷新");
    } catch { setNotice("无法访问云剪贴板服务"); }
    finally { setBusy(false); }
  }

  useEffect(() => {
    if (client.rememberInputTarget) void client.rememberInputTarget().catch(() => setNotice("未能记录前台输入窗口"));
    void refresh("");
  }, [client]);

  async function add() {
    if (!draft) return;
    setBusy(true);
    try {
      await client.request({ operation: "add", text: draft });
      setDraft("");
      await refresh(search);
    } catch { setNotice("上传失败，请确认账户 provider 已连接"); setBusy(false); }
  }

  async function remove(id: string) {
    setBusy(true);
    try { await client.request({ operation: "delete", id }); await refresh(search); }
    catch { setNotice("删除失败"); setBusy(false); }
  }

  async function toggle() {
    const next = !enabled;
    setBusy(true);
    try { const result = await client.request({ operation: "set_enabled", enabled: next }); setEnabled(typeof result.enabled === "boolean" ? result.enabled : next); setNotice(next ? "云剪贴板已开启" : "云剪贴板已关闭"); }
    catch { setNotice("更新云剪贴板设置失败"); }
    finally { setBusy(false); }
  }

  async function choose(item: CloudClipboardItem) {
    if (!client.sendText) { setNotice("当前宿主未提供目标窗口提交能力"); return; }
    try { await client.sendText(item.text); setNotice(`已输入：${item.text}`); }
    catch { setNotice("提交失败，前台输入窗口可能已关闭"); }
  }

  return <main className="native-panel cloud-clipboard-panel" aria-label="云剪贴板">
    <header className="native-panel-header"><span>水杉云剪贴板</span><button type="button" aria-label="关闭" onClick={() => void client.close()}>×</button></header>
    <div className="cloud-clipboard-body">
      <p className="cloud-clipboard-description">只上传你明确选择的文本，不自动读取本地剪贴板。</p>
      <label className="cloud-clipboard-toggle"><span>启用云剪贴板</span><input type="checkbox" checked={enabled} onChange={() => void toggle()} disabled={busy} /></label>
      <div className="cloud-clipboard-search"><input aria-label="搜索云端历史" value={search} onChange={event => setSearch(event.target.value)} onKeyDown={event => { if (event.key === "Enter") void refresh(); }} placeholder="搜索云端历史" /><button type="button" onClick={() => void refresh()} disabled={busy}>刷新</button></div>
      <div className="cloud-clipboard-add"><textarea aria-label="待上传文本" value={draft} onChange={event => setDraft(event.target.value)} placeholder="输入要上传的文本" rows={3} /><button type="button" onClick={() => void add()} disabled={!enabled || !draft || busy}>上传明确选择的文本</button></div>
      <div className="cloud-clipboard-list" aria-label="云端历史">{items.length ? items.map(item => <article className="cloud-clipboard-item" key={item.id}><button type="button" onClick={() => void choose(item)}>{item.text}</button><button type="button" className="cloud-clipboard-delete" aria-label={`删除 ${item.text}`} onClick={() => void remove(item.id)} disabled={busy}>删除</button></article>) : <p className="cloud-clipboard-empty">暂无云端历史</p>}</div>
      <p className="cloud-clipboard-notice" role="status">{notice}</p>
    </div>
  </main>;
}

const cloudDictionaryKinds: [CloudDictionaryKind, string][] = [
  ["pinyin", "拼音"], ["wubi", "五笔"], ["quick", "快捷短语"], ["english", "英文"],
];

function cloudDictionaryEntries(value: CloudDictionaryResponse) {
  return Array.isArray(value.entries)
    ? value.entries.filter(entry => entry && typeof entry.id === "string" && typeof entry.code === "string" && typeof entry.word === "string")
    : [];
}

export function CloudDictionaryPanel({ client }: { client: CloudDictionaryPanelClient }) {
  const [kind, setKind] = useState<CloudDictionaryKind>("pinyin");
  const [search, setSearch] = useState("");
  const [format, setFormat] = useState<CloudDictionaryFileFormat>("standard");
  const [offset, setOffset] = useState(0);
  const [entries, setEntries] = useState<CloudDictionaryEntry[]>([]);
  const [hasMore, setHasMore] = useState(false);
  const [form, setForm] = useState<{ entry: CloudDictionaryEntry | null; code: string; word: string; weight: number } | null>(null);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("管理当前账号的云端词条");

  async function refresh(nextOffset = 0, nextSearch = search, nextKind = kind) {
    setBusy(true);
    try {
      const result = await client.request({ operation: "list", kind: nextKind, offset: nextOffset, search: nextSearch });
      setEntries(cloudDictionaryEntries(result));
      setOffset(typeof result.offset === "number" ? result.offset : nextOffset);
      setHasMore(result.has_more === true);
      setNotice("云词典已刷新");
    } catch { setNotice("无法访问云词典服务，请确认 provider 已连接"); }
    finally { setBusy(false); }
  }

  useEffect(() => { void refresh(0, ""); }, [client]);

  function beginAdd() { setForm({ entry: null, code: "", word: "", weight: 100000 }); }
  function beginEdit(entry: CloudDictionaryEntry) { setForm({ entry, code: entry.code, word: entry.word, weight: entry.weight }); }

  async function save() {
    if (!form || !form.code.trim() || !form.word.trim()) { setNotice("编码和词条不能为空"); return; }
    setBusy(true);
    try {
      const code = form.code.trim();
      const word = form.word;
      if (form.entry) {
        await client.request({ operation: "update", kind, id: form.entry.id, code, word, weight: form.weight, revision: form.entry.revision });
      } else {
        await client.request({ operation: "add", kind, code, word, weight: form.weight });
      }
      setForm(null); setNotice("云词条已保存"); await refresh(offset, search);
    } catch { setNotice("云词条保存失败，请刷新后重试"); setBusy(false); }
  }

  async function remove(entry: CloudDictionaryEntry) {
    setBusy(true);
    try { await client.request({ operation: "delete", kind, id: entry.id, revision: entry.revision }); setNotice("云词条已删除"); await refresh(offset, search); }
    catch { setNotice("云词条删除失败，请刷新后重试"); setBusy(false); }
  }

  async function importFile(file: File) {
    if (file.size > 65536) { setNotice("导入文件不能超过 64 KiB"); return; }
    setBusy(true);
    try { await client.request({ operation: "import", kind, format, text: await file.text() }); setNotice("云词库已导入"); await refresh(offset, search); }
    catch { setNotice("导入失败，请检查 UTF-8 TSV 文件格式"); setBusy(false); }
  }

  async function exportDictionary() {
    setBusy(true);
    try {
      if (format === "hans") throw new Error("format cannot be exported");
      const result = await client.request({ operation: "export", kind, format });
      const text = typeof result.text === "string" ? result.text : result.content;
      if (typeof text !== "string") throw new Error("provider returned no file");
      const anchor = document.createElement("a");
      anchor.href = URL.createObjectURL(new Blob([text], { type: "text/plain;charset=utf-8" }));
      anchor.download = result.filename || `msime-${kind}-dictionary.tsv`;
      anchor.click(); URL.revokeObjectURL(anchor.href); setNotice("云词库已导出");
    } catch { setNotice("导出失败，请确认 provider 已连接"); }
    finally { setBusy(false); }
  }

  function changeKind(next: CloudDictionaryKind) { setKind(next); if (next !== "pinyin" && format === "hans") setFormat("standard"); setOffset(0); setEntries([]); void refresh(0, search, next); }
  return <main className="native-panel cloud-dictionary-panel" aria-label="云词典">
    <header className="native-panel-header"><span>水杉云词典</span><button type="button" aria-label="关闭" onClick={() => void client.close()}>×</button></header>
    <div className="cloud-dictionary-body">
      <p className="cloud-dictionary-description">管理当前账号的云端词条。修改需要 provider 提供登录态和同步服务。</p>
      <div className="cloud-dictionary-toolbar"><label>词库<select aria-label="词库类型" value={kind} onChange={event => changeKind(event.target.value as CloudDictionaryKind)} disabled={busy}>{cloudDictionaryKinds.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label><label className="cloud-dictionary-search">搜索<input aria-label="搜索云词条" value={search} onChange={event => setSearch(event.target.value)} onKeyDown={event => { if (event.key === "Enter") void refresh(0); }} placeholder="词条或编码" /></label><button type="button" onClick={() => void refresh(0)} disabled={busy}>查询</button><button type="button" onClick={beginAdd} disabled={busy}>添加词条</button></div>
      <div className="cloud-dictionary-actions"><label>文件格式<select aria-label="文件格式" value={format} onChange={event => setFormat(event.target.value as CloudDictionaryFileFormat)} disabled={busy}><option value="standard">标准 TSV</option><option value="windows">Windows TSV</option>{kind === "pinyin" && <option value="hans">汉字自动注音（仅导入）</option>}</select></label><button type="button" onClick={() => void exportDictionary()} disabled={busy || format === "hans"}>导出</button><label className="secondary">导入<input hidden type="file" accept=".txt,.tsv,text/plain" disabled={busy} onChange={event => { const file = event.target.files?.[0]; if (file) void importFile(file); event.currentTarget.value = ""; }} /></label></div>
      {form && <div className="cloud-dictionary-form"><label>编码<input value={form.code} onChange={event => setForm({ ...form, code: event.target.value })} /></label><label className="cloud-dictionary-word">词条<input value={form.word} onChange={event => setForm({ ...form, word: event.target.value })} /></label><label>权重<input type="number" min="0" value={form.weight} onChange={event => setForm({ ...form, weight: Number(event.target.value) })} /></label><button type="button" onClick={() => void save()} disabled={busy}>保存</button><button type="button" className="secondary" onClick={() => setForm(null)} disabled={busy}>取消</button></div>}
      <div className="cloud-dictionary-list" aria-label="云词条">{entries.length ? entries.map(entry => <article className="cloud-dictionary-item" key={entry.id}><div><strong>{entry.word}</strong><small>{entry.code} · 权重 {entry.weight}</small></div><span><button type="button" className="secondary" onClick={() => beginEdit(entry)} disabled={busy}>编辑</button><button type="button" className="secondary" onClick={() => void remove(entry)} disabled={busy}>删除</button></span></article>) : <p className="cloud-dictionary-empty">暂无词条</p>}</div>
      <div className="cloud-dictionary-pagination"><button type="button" onClick={() => void refresh(Math.max(0, offset - 100))} disabled={busy || offset === 0}>上一页</button><span>第 {Math.floor(offset / 100) + 1} 页</span><button type="button" onClick={() => void refresh(offset + 100)} disabled={busy || !hasMore}>下一页</button></div>
      <p className="cloud-dictionary-notice" role="status">{notice}</p>
    </div>
  </main>;
}

type EmojiPage = "home" | "emoji" | "sticker" | "gif" | "kaomoji" | "symbols" | "clipboard";

const emojiPages: { id: EmojiPage; label: string; icon: string }[] = [
  { id: "home", label: "最近使用", icon: "◷" },
  { id: "emoji", label: "Emoji", icon: "😀" },
  { id: "sticker", label: "贴纸", icon: "🖼" },
  { id: "gif", label: "GIF", icon: "GIF" },
  { id: "kaomoji", label: "颜文字", icon: "ヾ" },
  { id: "symbols", label: "符号", icon: "★" },
  { id: "clipboard", label: "剪贴板", icon: "▣" },
];

function matchesEmojiItem(item: EmojiCatalogItem, query: string) {
  return !query || `${item.text} ${item.keywords}`.toLocaleLowerCase().includes(query.toLocaleLowerCase());
}

function flattenGroups(groups: EmojiCatalogGroup[]) {
  return groups.flatMap(group => group.items);
}

export function EmojiPanel({ client }: { client: EmojiPanelClient }) {
  const [page, setPage] = useState<EmojiPage>("home");
  const [query, setQuery] = useState("");
  const [recent, setRecent] = useState<EmojiCatalogItem[]>([]);
  const [clipboard, setClipboard] = useState<string[]>([]);
  const [notice, setNotice] = useState("点击项目即可复制");
  const [catalog, setCatalog] = useState({ emoji: fallbackEmojiGroups, kaomoji: fallbackKaomojiGroups, symbols: fallbackSymbolGroups });

  useEffect(() => {
    if (!client.rememberInputTarget) return;
    void client.rememberInputTarget().catch(() => setNotice("未能记录前台输入窗口"));
  }, [client]);

  useEffect(() => {
    if (!client.loadCatalog) return;
    void client.loadCatalog().then(setCatalog).catch(() => setNotice("目录不可用，已使用内置目录"));
  }, [client]);

  useEffect(() => {
    if (!client.clipboard?.list) return;
    void client.clipboard.list().then(setClipboard).catch(() => setClipboard([]));
  }, [client]);

  useEffect(() => {
    if (page !== "clipboard" || !client.clipboard?.list) return;
    void client.clipboard.list().then(setClipboard).catch(() => setClipboard([]));
  }, [client, page]);

  const groups = page === "emoji" ? catalog.emoji : page === "kaomoji" ? catalog.kaomoji : catalog.symbols;
  const filteredGroups = groups.map(group => ({ ...group, items: group.items.filter(item => matchesEmojiItem(item, query)) })).filter(group => group.items.length);
  const homeGroups: EmojiCatalogGroup[] = [
    ...(recent.length ? [{ title: "Recently used", icon: "◷", items: recent }] : []),
    { title: "Emoji", icon: catalog.emoji[0]?.icon ?? "😀", items: flattenGroups(catalog.emoji).filter(item => matchesEmojiItem(item, query)).slice(0, 18) },
    { title: "Kaomoji", icon: catalog.kaomoji[0]?.icon ?? "ヾ", items: flattenGroups(catalog.kaomoji).filter(item => matchesEmojiItem(item, query)).slice(0, 12) },
    { title: "Symbols", icon: catalog.symbols[0]?.icon ?? "★", items: flattenGroups(catalog.symbols).filter(item => matchesEmojiItem(item, query)).slice(0, 12) },
  ].filter(group => group.items.length);

  async function copy(text: string, isClipboardItem = false) {
    if (!isClipboardItem && client.sendText) {
      try {
        await client.sendText(text);
        setNotice(`已输入：${text}`);
        setRecent(current => [{ text, keywords: text }, ...current.filter(item => item.text !== text)].slice(0, 28));
        return;
      } catch {
        // Fall back to clipboard when the captured Linux input target is gone.
      }
    }
    const copyAction = isClipboardItem ? client.clipboard?.copy ?? client.copyText : client.copyText ?? client.clipboard?.copy;
    if (!copyAction) {
      setNotice(`已选择：${text}（等待宿主复制能力）`);
      return;
    }
    try {
      await copyAction(text);
      setNotice(`已复制：${text}`);
      if (!isClipboardItem) setRecent(current => [{ text, keywords: text }, ...current.filter(item => item.text !== text)].slice(0, 28));
    } catch {
      setNotice("无法访问剪贴板");
    }
  }

  async function syncClipboard() {
    if (!client.clipboard?.sync) return;
    try {
      setClipboard(await client.clipboard.sync());
      setNotice("剪贴板已同步");
    } catch {
      setNotice("无法同步剪贴板");
    }
  }

  function selectPage(next: EmojiPage) {
    setPage(next);
    setQuery("");
    setNotice(next === "clipboard" ? "点击项目即可复制" : "点击项目即可复制");
  }

  const isDetail = page !== "home";
  const displayGroups = page === "home" ? homeGroups : filteredGroups;
  return <main className="native-panel emoji-panel" aria-label="表情与符号">
    <header className="native-panel-header"><span>Emoji and more</span><button type="button" aria-label="关闭" onClick={() => void client.close()}>×</button></header>
    <div className="emoji-panel-search"><span aria-hidden="true">⌕</span><input aria-label="搜索" value={query} onChange={event => setQuery(event.target.value)} placeholder={page === "clipboard" ? "搜索剪贴板" : "Search emoji, kaomoji, and symbols"} /></div>
    <nav className="emoji-panel-tabs" aria-label="面板分类">
      {emojiPages.map(item => <button type="button" key={item.id} className={page === item.id ? "active" : ""} aria-label={item.label} aria-pressed={page === item.id} onClick={() => selectPage(item.id)}><span aria-hidden="true">{item.icon}</span><small>{item.label}</small></button>)}
    </nav>
    {isDetail && <div className="emoji-panel-back"><button type="button" aria-label="返回" onClick={() => selectPage("home")}>‹ 返回</button></div>}
    {page === "clipboard" ? <section className="emoji-panel-content clipboard-panel-content" aria-label="剪贴板历史">
      <div className="emoji-panel-toolbar"><h2>剪贴板</h2>{client.clipboard?.sync && <button type="button" onClick={() => void syncClipboard()}>同步</button>}</div>
      {clipboard.length ? <div className="clipboard-panel-list">{clipboard.filter(item => matchesEmojiItem({ text: item, keywords: item }, query)).map(item => <button type="button" className="clipboard-panel-item" key={item} onClick={() => void copy(item, true)}>{item}</button>)}</div> : <p className="emoji-panel-empty">暂无剪贴板记录</p>}
    </section> : page === "sticker" || page === "gif" ? <p className="emoji-panel-empty">{page === "sticker" ? "贴纸来源可在这里接入" : "GIF 来源可在这里接入"}</p> : <section className="emoji-panel-content" aria-label={page === "home" ? "最近使用与目录" : page === "emoji" ? "Emoji 目录" : page === "kaomoji" ? "颜文字目录" : "符号目录"}>
      {displayGroups.map((group, groupIndex) => <div className="emoji-panel-group" key={group.title}><div className="emoji-panel-group-title"><span>{group.icon}</span><h2>{group.title}</h2>{page === "home" && groupIndex > 0 && <button type="button" onClick={() => selectPage(group.title === "Emoji" ? "emoji" : group.title === "Kaomoji" ? "kaomoji" : "symbols")}>更多</button>}</div><div className="emoji-panel-grid">{group.items.map(item => <button type="button" className="emoji-panel-item" key={`${group.title}-${item.text}`} title={item.keywords} onClick={() => void copy(item.text)}>{item.text}</button>)}</div></div>)}
      {!displayGroups.length && <p className="emoji-panel-empty">{query ? "No results" : "暂无可显示内容"}</p>}
    </section>}
    <p className="emoji-panel-notice" role="status">{notice}</p>
  </main>;
}
