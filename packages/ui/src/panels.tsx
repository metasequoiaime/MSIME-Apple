import { useEffect, useState, type PointerEvent } from "react";
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
  rememberInputTarget?(): Promise<void>;
  sendKey?(request: KeyboardInputRequest): Promise<void>;
  recognizeHandwriting?(request: HandwritingRecognitionRequest): Promise<HandwritingRecognitionResult>;
  submitHandwritingCandidate?(candidate: string): Promise<void>;
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
  [key("`", 0xc0, "~"), ...[..."1234567890"].map((label, index) => key(label, 0x31 + index, ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")"][index])), key("-", 0xbd, "_"), key("=", 0xbb, "+"), key("Backspace", 0x08)],
  [key("Tab", 0x09), ...[..."QWERTYUIOP"].map(label => key(label.toLowerCase(), label.charCodeAt(0))), key("[", 0xdb, "{"), key("]", 0xdd, "}"), key("\\", 0xdc, "|")],
  [modifier("Caps Lock", 0x14), ...[..."ASDFGHJKL"].map(label => key(label.toLowerCase(), label.charCodeAt(0))), key(";", 0xba, ":"), key("'", 0xde, '"'), key("Enter", 0x0d)],
  [modifier("Shift", 0x10), ...[..."ZXCVBNM"].map(label => key(label.toLowerCase(), label.charCodeAt(0))), key(",", 0xbc, "<"), key(".", 0xbe, ">"), key("/", 0xbf, "?"), modifier("Shift", 0x10)],
  [modifier("Ctrl", 0x11), modifier("Win", 0x5b), modifier("Alt", 0x12), key("Space", 0x20, " "), modifier("Alt", 0x12), modifier("Win", 0x5b), key("Del", 0x2e), modifier("Ctrl", 0x11)],
];

function modifierPrefix(modifiers: Set<Modifier>) {
  return ["Ctrl", "Alt", "Win", "Shift"].filter(value => modifiers.has(value as Modifier)).join("+");
}
function isImeCommitKey(virtualKey: number) {
  return [0x20, 0x0d, 0x09, 0x08, 0x2e].includes(virtualKey) || (virtualKey >= 0x30 && virtualKey <= 0x39);
}

export function KeyboardPanel({ client }: { client: PanelClient }) {
  const [activeModifiers, setActiveModifiers] = useState<Set<Modifier>>(new Set());
  const [notice, setNotice] = useState("使用鼠标或触控方式输入文字与快捷按键");
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
    const withShift = letter ? caps !== shift : shift;
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
  return <main className="native-panel keyboard-panel" aria-label="屏幕键盘">
    <header className="native-panel-header"><span>水杉屏幕键盘</span><button type="button" aria-label="关闭" onClick={() => void client.close()}>×</button></header>
    <div className="keyboard-panel-body">
      <div className="keyboard-panel-notice" role="status">{notice}</div>
      <div className="keyboard-layout">
        {keyboardRows.map((row, rowIndex) => <div className="keyboard-row" key={rowIndex}>{row.map((keyToRender, keyIndex) => {
          const letter = keyToRender.label.length === 1 && /[a-z]/i.test(keyToRender.label);
          const uppercase = letter && activeModifiers.has("Caps Lock") !== activeModifiers.has("Shift");
          const label = keyToRender.label === "Space" ? "" : uppercase ? keyToRender.label.toUpperCase() : keyToRender.label;
          return <button type="button" key={`${keyToRender.label}-${keyIndex}`} aria-pressed={keyToRender.modifier ? activeModifiers.has(keyToRender.modifier) : undefined} className={`keyboard-key${keyToRender.modifier ? " modifier" : ""}${keyToRender.label === "Space" ? " space" : ""}${keyToRender.label.length > 1 ? " wide" : ""}${keyToRender.modifier && activeModifiers.has(keyToRender.modifier) ? " active" : ""}`} onClick={() => pressKey(keyToRender)}>{label}</button>;
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
  async function recognize(nextStrokes: InkStroke[]) {
    if (!client.recognizeHandwriting) { setCandidates([]); setNotice("识别结果需由 Windows 原生宿主提供"); return; }
    try {
      const result = await client.recognizeHandwriting({ language: "zh-CN", strokes: nextStrokes });
      setCandidates(result.candidates);
      setNotice(result.candidates.length ? "点击候选结果即可提交" : "未识别到内容，请确认已安装中文手写包");
    } catch { setCandidates([]); setNotice("Windows Ink 识别失败"); }
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
  function clear() { setStrokes([]); setDrawing([]); setCandidates([]); setNotice("请在左侧书写，松开鼠标后自动识别"); }
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
