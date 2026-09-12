import { usePanelDrag } from "./use-panel-drag";
import { useEmojiNavigation } from "./use-emoji-navigation";
import { useEffect, useRef, useState, type CSSProperties, type PointerEvent } from "react";
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
  openVoice?(): Promise<void>;
  beginWindowDrag?(): Promise<void>;
  rememberInputTarget?(): Promise<void>;
  sendKey?(request: KeyboardInputRequest): Promise<void>;
  sendText?(text: string): Promise<void>;
  recognizeHandwriting?(request: HandwritingRecognitionRequest): Promise<HandwritingRecognitionResult>;
  submitHandwritingCandidate?(candidate: string): Promise<void>;
  copyHandwritingCandidate?(candidate: string): Promise<void>;
}

export interface VoicePanelClient extends PanelClient {
  maxSubmitBytes?: number;
  loadVoiceLanguage?(): Promise<string>;
  recognizeVoice?(language: string): Promise<{ text: string }>;
  onVoiceUpdate?(listener: (update: { text: string; final: boolean; phase?: "recording" | "recognizing" | "polishing"; level?: number }) => void): Promise<() => void>;
  cancelVoice?(): Promise<void>;
  stopVoice?(): Promise<void>;
  sendVoiceText?(text: string): Promise<void>;
  copyText?(text: string): Promise<void>;
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
  copyText?(text: string): Promise<void>;
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
    isEnabled?(): Promise<boolean>;
    enable?(): Promise<void>;
    onChanged?(listener: () => void): Promise<() => void>;
    sync?(): Promise<string[]>;
    remove?(text: string): Promise<void>;
    clear?(): Promise<void>;
    copy?(text: string): Promise<void>;
    paste?(text: string): Promise<void>;
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
  [modifier("Ctrl", 0x11), modifier("Win", 0x5b), modifier("Alt", 0x12), key("Space", 0x20, " "), modifier("Alt", 0x12), modifier("Win", 0x5b), key("Menu", 0x5d), key("Del", 0x2e), key("←", 0x25), key("↑", 0x26), key("↓", 0x28), key("→", 0x27), modifier("Ctrl", 0x11)],
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
// Width ratios from Windows KeyboardPanel.cpp at 7fa6fb1a7862c5ca1541b9cb839d9bea3a06e2c6.
// Identify the space row by its content: Linux adds function and numpad rows.
function keyboardKeyWeight(label: string, index: number, spaceRow: boolean) {
  if (spaceRow) return label === "Space" ? 6.7 : 1.25;
  if (label === "Backspace") return 1.9;
  if (label === "Tab") return 1.5;
  if (label === "\\") return 1.4;
  if (label === "Caps Lock") return 1.85;
  if (label === "Enter") return 2;
  if (label === "Shift") return index === 0 ? 2.35 : 2.15;
  return 1;
}
function isImeCommitKey(virtualKey: number) {
  return [0x20, 0x0d, 0x09, 0x08, 0x2e, 0x6a, 0x6b, 0x6d, 0x6e, 0x6f].includes(virtualKey) || (virtualKey >= 0x30 && virtualKey <= 0x39) || (virtualKey >= 0x60 && virtualKey <= 0x69);
}

export function KeyboardPanel({ client, theme = "dark", layout = "twenty_six_key", keySpacingTenths = 60, rowSpacingTenths = 70, voiceShortcut = false }: { client: PanelClient; theme?: "dark" | "light"; layout?: "twenty_six_key" | "nine_key"; keySpacingTenths?: number; rowSpacingTenths?: number; voiceShortcut?: boolean }) {
  const [activeLayout, setActiveLayout] = useState<"twenty_six_key" | "nine_key">(() => {
    let saved: string | null = null;
    try { saved = typeof window !== "undefined" ? window.localStorage.getItem("msime.keyboard.layout") : null; } catch { /* restricted webviews may deny storage */ }
    return saved === "nine_key" || saved === "twenty_six_key" ? saved : layout;
  });
  function switchLayout() {
    const next = activeLayout === "nine_key" ? "twenty_six_key" : "nine_key";
    setActiveLayout(next);
    try { window.localStorage.setItem("msime.keyboard.layout", next); } catch { /* preference is optional */ }
  }
  const previousHostLayout = useRef(layout);
  useEffect(() => {
    // Initial mounting (including StrictMode replay) must preserve the saved preference.
    if (previousHostLayout.current === layout) return;
    previousHostLayout.current = layout;
    setActiveLayout(layout);
  }, [layout]);
  const rows = activeLayout === "nine_key" ? nineKeyRows : keyboardRows;
  const [activeModifiers, setActiveModifiers] = useState<Set<Modifier>>(new Set());
  const modifiersRef = useRef<Set<Modifier>>(new Set());
  const [notice, setNotice] = useState("Touch keyboard");
  const [openingVoice, setOpeningVoice] = useState(false);
  type QueuedKey = { request: KeyboardInputRequest; description: string };
  const inputQueue = useRef<{ active: boolean; running: boolean; openingVoice: boolean; pending: QueuedKey[] }>({ active: true, running: false, openingVoice: false, pending: [] });
  const drag = usePanelDrag(client, () => setNotice("无法移动窗口，请重试。"));
  useEffect(() => {
    const queue = { active: true, running: false, openingVoice: false, pending: [] as QueuedKey[] };
    setOpeningVoice(false);
    inputQueue.current = queue;
    modifiersRef.current = new Set();
    setActiveModifiers(new Set());
    if (client.rememberInputTarget) void client.rememberInputTarget().catch(() => {
      if (queue.active) setNotice("未能记录前台输入窗口");
    });
    return () => { queue.active = false; queue.pending = []; };
  }, [client]);
  function toggleModifier(keyToToggle: Modifier) {
    const next = new Set(modifiersRef.current);
    if (next.has(keyToToggle)) next.delete(keyToToggle); else next.add(keyToToggle);
    modifiersRef.current = next;
    setActiveModifiers(next);
  }
  async function drainKeys() {
    const queue = inputQueue.current;
    if (!queue.active || queue.running || !client.sendKey) return;
    queue.running = true;
    try {
      while (queue.active && queue.pending.length) {
        const next = queue.pending.shift()!;
        setNotice(`正在发送：${next.description}`);
        try { await client.sendKey(next.request); }
        catch {
          // Delivery may have partially succeeded; never replay a failed key.
          queue.pending = [];
          if (queue.active) setNotice("按键发送失败，后续排队按键已取消，请确认输入位置后继续");
          return;
        }
        if (queue.active) setNotice(`已发送：${next.description}`);
      }
    } finally { queue.running = false; }
  }
  async function openVoiceKeyboard() {
    const queue = inputQueue.current;
    if (!queue.active || queue.openingVoice || !client.openVoice) return;
    if (queue.running || queue.pending.length) {
      setNotice("请等待按键发送完成后打开语音输入");
      return;
    }
    queue.openingVoice = true;
    setOpeningVoice(true);
    setNotice("正在打开语音输入…");
    try {
      await client.openVoice();
      if (queue.active) setNotice("已打开语音输入");
    } catch {
      if (queue.active) setNotice("无法打开语音输入，请重试");
    } finally {
      queue.openingVoice = false;
      if (queue.active && inputQueue.current === queue) setOpeningVoice(false);
    }
  }
  function closeKeyboard() {
    const queue = inputQueue.current;
    queue.active = false;
    queue.pending = [];
    void client.close().catch(() => {
      if (inputQueue.current === queue) {
        queue.active = true;
        setNotice("无法关闭键盘，请重试");
      }
    });
  }
  function pressKey(keyToPress: KeyboardKey) {
    const queue = inputQueue.current;
    if (!queue.active || queue.openingVoice) return;
    if (keyToPress.modifier) { toggleModifier(keyToPress.modifier); return; }
    if (queue.pending.length >= 64) { setNotice("按键正在发送，请稍候再继续输入"); return; }
    const activeModifiers = modifiersRef.current;
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
    if (client.sendKey) {
      queue.pending.push({ request, description });
      void drainKeys();
    }
    if (shift) {
      const next = new Set(activeModifiers);
      next.delete("Shift");
      modifiersRef.current = next;
      setActiveModifiers(next);
    }
  }
  const keyGap = Math.max(3, Math.min(6, keySpacingTenths / 10));
  const rowGap = Math.max(4, Math.min(10, rowSpacingTenths / 10));
  const keyboardStyle = { "--keyboard-key-gap": `${keyGap}px`, "--keyboard-row-gap": `${rowGap}px` } as CSSProperties;
  return <main className="native-panel keyboard-panel" data-keyboard-theme={theme} data-keyboard-layout={activeLayout} aria-label="屏幕键盘">
    <header className="native-panel-header" {...drag}>
      <span className="keyboard-panel-notice" role="status" title={notice}>{notice}</span><button type="button" aria-label="切换键盘布局" onClick={switchLayout}>{activeLayout === "nine_key" ? "全键" : "九宫格"}</button>{voiceShortcut && client.openVoice && <button type="button" aria-label="打开语音输入" disabled={openingVoice} onClick={() => void openVoiceKeyboard()}>语音</button>}<button type="button" aria-label="关闭" disabled={openingVoice} onClick={closeKeyboard}>×</button></header>
    <div className="keyboard-panel-body">
      <div className="keyboard-layout" style={keyboardStyle}>
        {rows.map((row, rowIndex) => <div className="keyboard-row" key={rowIndex}>{row.map((keyToRender, keyIndex) => {
          const letter = keyToRender.label.length === 1 && /[a-z]/i.test(keyToRender.label);
          const shifted = activeModifiers.has("Shift") && keyToRender.label.length === 1;
          const label = shifted ? (keyToRender.shifted || (letter ? keyToRender.label.toUpperCase() : keyToRender.label)) : keyToRender.label;
          return <button type="button" disabled={openingVoice} key={`${keyToRender.label}-${keyIndex}`} style={{ flexGrow: activeLayout === "nine_key" ? 1 : keyboardKeyWeight(keyToRender.label, keyIndex, row.some(item => item.virtualKey === 0x20)) }} aria-pressed={keyToRender.modifier ? activeModifiers.has(keyToRender.modifier) : undefined} className={`keyboard-key${keyToRender.modifier ? " modifier" : ""}${keyToRender.label === "Space" ? " space" : ""}${keyToRender.label.length > 1 ? " wide" : ""}${keyToRender.modifier && activeModifiers.has(keyToRender.modifier) ? " active" : ""}`} onClick={() => pressKey(keyToRender)}>{label}</button>;
        })}</div>)}
      </div>
    </div>
  </main>;
}

type Point = InkPoint;
// Keep captured ink within the Linux provider's 32-stroke and 256 KiB envelope.
// Two decimal places retain subpixel precision in the 420-unit drawing space.
const MAX_HANDWRITING_STROKES = 32;
const MAX_CAPTURED_POINTS = 256;
function appendInkPoint(points: Point[], point: Point, endpoint = false): Point[] {
  if (!Number.isFinite(point.x) || !Number.isFinite(point.y)) return points;
  const next = { x: Math.round(point.x * 100) / 100, y: Math.round(point.y * 100) / 100 };
  const last = points[points.length - 1];
  if (last?.x === next.x && last?.y === next.y) return points;
  // Match the Windows panel's half-unit movement threshold while keeping the
  // final pen position and Linux touch/stylus dots available to recognition.
  if (last && !endpoint && Math.abs(last.x - next.x) + Math.abs(last.y - next.y) < 0.5) return points;
  if (points.length < MAX_CAPTURED_POINTS) return [...points, next];
  // Thin older samples while retaining both the original start and latest end.
  return [...points.filter((_, index) => index % 2 === 0), last, next];
}

function pointFromCoordinates(canvas: SVGSVGElement, event: { clientX: number; clientY: number }): Point {
  // The SVG matrix accounts for borders, viewBox letterboxing, window zoom
  // and CSS transforms; the bounding rectangle alone cannot represent these.
  const matrix = canvas.getScreenCTM?.();
  if (matrix && canvas.createSVGPoint) {
    try {
      const pointer = canvas.createSVGPoint();
      pointer.x = event.clientX;
      pointer.y = event.clientY;
      const local = pointer.matrixTransform(matrix.inverse());
      if (Number.isFinite(local.x) && Number.isFinite(local.y)) {
        return { x: Math.max(0, Math.min(420, local.x)), y: Math.max(0, Math.min(420, local.y)) };
      }
    } catch { /* A detached or non-invertible canvas uses the bounded fallback. */ }
  }
  const rect = canvas.getBoundingClientRect();
  const width = rect.width || 420;
  const height = rect.height || 420;
  return { x: Math.max(0, Math.min(420, ((event.clientX - rect.left) / width) * 420)), y: Math.max(0, Math.min(420, ((event.clientY - rect.top) / height) * 420)) };
}

function appendPointerSamples(points: Point[], event: PointerEvent<SVGSVGElement>, endpoint = false): Point[] {
  let next = points;
  for (const sample of event.nativeEvent.getCoalescedEvents?.() ?? []) {
    if (sample.pointerId === event.pointerId) {
      next = appendInkPoint(next, pointFromCoordinates(event.currentTarget, sample));
    }
  }
  return appendInkPoint(next, pointFromCoordinates(event.currentTarget, event), endpoint);
}

function HandwritingCandidateButton({ candidate, copy, disabled, onChoose }: {
  candidate: string; copy: boolean; disabled: boolean; onChoose: () => void;
}) {
  const button = useRef<HTMLButtonElement>(null);
  const [width, setWidth] = useState(64);
  useEffect(() => {
    const element = button.current;
    if (!element) return;
    const resize = () => setWidth(element.getBoundingClientRect().width);
    resize();
    if (typeof ResizeObserver !== "undefined") {
      const observer = new ResizeObserver(resize);
      observer.observe(element);
      return () => observer.disconnect();
    }
    window.addEventListener("resize", resize);
    return () => window.removeEventListener("resize", resize);
  }, []);
  // Use Unicode code points so supplementary Han does not count as two glyphs.
  const length = Math.max(1, Array.from(candidate).length);
  const fontSize = Math.max(13, Math.min(34, width * 0.52, (width - 12) / length));
  return <button ref={button} type="button" className="handwriting-candidate-submit"
    style={{ fontSize }} title={`${copy ? "复制" : "输入"}：${candidate}`}
    disabled={disabled} onClick={onChoose}>{candidate}</button>;
}

export function HandwritingPanel({ client, theme = "dark" }: { client: PanelClient; theme?: "dark" | "light" }) {
  const [activationMode, setActivationMode] = useState<"copy" | "input">(() => {
    try { return window.localStorage.getItem("msime.handwriting.activation") === "input" ? "input" : "copy"; }
    catch { return "copy"; }
  });
  const effectiveMode = activationMode === "copy" && !client.copyHandwritingCandidate
    ? "input" : activationMode === "input" && !client.submitHandwritingCandidate ? "copy" : activationMode;
  function selectActivation(mode: "copy" | "input") {
    if (!recognitionQueue.current.active || closingRef.current) return;
    setActivationMode(mode);
    try { window.localStorage.setItem("msime.handwriting.activation", mode); } catch { /* optional preference */ }
  }
  const [strokes, setStrokes] = useState<InkStroke[]>([]);
  const [redoStrokes, setRedoStrokes] = useState<InkStroke[]>([]);
  const [drawing, setDrawing] = useState<Point[]>([]);
  const [candidates, setCandidates] = useState<string[]>([]);
  const [notice, setNotice] = useState("请在左侧书写，松开鼠标后自动识别");
  const drag = usePanelDrag(client, () => setNotice("无法移动窗口，请重试。"));
  const recognitionRevision = useRef(0);
  const [recognizing, setRecognizing] = useState(false);
  const recognitionQueue = useRef<{ active: boolean; running: boolean; pending: { revision: number; strokes: InkStroke[] } | null }>({ active: true, running: false, pending: null });
  const submissionRevision = useRef(0);
  const closingRef = useRef(false);
  const [closing, setClosing] = useState(false);
  const submittingRef = useRef(false);
  const [submitting, setSubmitting] = useState(false);
  const activeStroke = useRef<{ pointerId: number; canvas: SVGSVGElement; points: Point[] } | null>(null);
  function releaseStroke() {
    const active = activeStroke.current;
    activeStroke.current = null;
    if (active?.canvas.hasPointerCapture?.(active.pointerId)) active.canvas.releasePointerCapture(active.pointerId);
  }
  useEffect(() => {
    const queue = { active: true, running: false, pending: null } as typeof recognitionQueue.current;
    recognitionQueue.current = queue;
    setRecognizing(false);
    closingRef.current = false;
    setClosing(false);
    submittingRef.current = false;
    setSubmitting(false);
    return () => {
      queue.active = false;
      queue.pending = null;
      recognitionRevision.current++;
      submissionRevision.current++;
      submittingRef.current = false;
      releaseStroke();
    };
  }, [client]);
  async function closeHandwriting() {
    const queue = recognitionQueue.current;
    if (!queue.active || closingRef.current) return;
    if (activeStroke.current) {
      setNotice("请完成当前笔画后关闭手写识别板");
      return;
    }
    closingRef.current = true;
    setClosing(true);
    try {
      await client.close();
      if (queue.active && recognitionQueue.current === queue) {
        queue.active = false;
        queue.pending = null;
        recognitionRevision.current++;
        submissionRevision.current++;
        releaseStroke();
      }
    } catch {
      if (queue.active && recognitionQueue.current === queue) {
        setNotice("无法关闭手写识别板，请重试");
      }
    } finally {
      if (queue.active && recognitionQueue.current === queue) {
        closingRef.current = false;
        setClosing(false);
      }
    }
  }
  function recognize(nextStrokes: InkStroke[]) {
    if (!recognitionQueue.current.active || closingRef.current) return;
    const revision = ++recognitionRevision.current;
    setCandidates([]);
    setNotice("正在识别…");
    const recognizeInk = client.recognizeHandwriting;
    if (!recognizeInk) { setNotice("识别结果需由宿主提供"); return; }
    const queue = recognitionQueue.current;
    queue.pending = { revision, strokes: nextStrokes };
    setRecognizing(true);
    if (queue.running) return;
    queue.running = true;
    void (async () => {
      try {
        while (queue.active && queue === recognitionQueue.current && queue.pending) {
          const request = queue.pending;
          queue.pending = null;
          if (request.revision !== recognitionRevision.current) continue;
          try {
            const result = await recognizeInk({ language: "zh-CN", strokes: request.strokes });
            if (request.revision !== recognitionRevision.current) continue;
            setCandidates(result.candidates);
            setNotice(result.candidates.length ? "选择候选可复制或输入" : "未识别到内容，请确认已安装中文手写包");
          } catch {
            if (request.revision === recognitionRevision.current) {
              setCandidates([]);
              setNotice("手写识别失败，请确认手写模型或识别服务可用，然后重新识别");
            }
          }
        }
      } finally {
        queue.running = false;
        if (queue.active && queue === recognitionQueue.current) setRecognizing(false);
      }
    })();
  }
  function retryRecognition() {
    if (!recognitionQueue.current.active || closingRef.current) return;
    if (!strokes.length || activeStroke.current || recognitionQueue.current.running || submittingRef.current) return;
    recognize(strokes);
  }
  function start(event: PointerEvent<SVGSVGElement>) {
    if (!recognitionQueue.current.active || closingRef.current || activeStroke.current || event.isPrimary === false || (event.button !== undefined && event.button !== 0)) return;
    if (strokes.length >= MAX_HANDWRITING_STROKES) {
      setNotice("笔画已达上限，请选择候选、撤销或重写");
      return;
    }
    event.currentTarget.focus({ preventScroll: true });
    recognitionRevision.current++;
    setCandidates([]);
    setNotice("书写中，松开后自动识别");
    const points = appendPointerSamples([], event);
    if (!points.length) return;
    activeStroke.current = { pointerId: event.pointerId, canvas: event.currentTarget, points };
    event.currentTarget.setPointerCapture?.(event.pointerId);
    setDrawing(points);
  }
  function move(event: PointerEvent<SVGSVGElement>) {
    const active = activeStroke.current;
    if (!active || active.pointerId !== event.pointerId) return;
    active.points = appendPointerSamples(active.points, event);
    setDrawing(active.points);
  }
  function recognizeRemaining(nextStrokes: InkStroke[]) {
    setCandidates([]);
    if (!nextStrokes.length) setNotice("请在左侧书写，松开鼠标后自动识别");
    else void recognize(nextStrokes);
  }
  function end(event: PointerEvent<SVGSVGElement>) {
    const active = activeStroke.current;
    if (!active || active.pointerId !== event.pointerId) return;
    active.points = appendPointerSamples(active.points, event, true);
    const nextStrokes = active.points.length > 0 ? [...strokes, { points: active.points }] : strokes;
    releaseStroke();
    setStrokes(nextStrokes);
    if (active.points.length > 0) setRedoStrokes([]);
    setDrawing([]);
    recognizeRemaining(nextStrokes);
  }
  function cancel(event: PointerEvent<SVGSVGElement>) {
    if (!activeStroke.current || activeStroke.current.pointerId !== event.pointerId) return;
    recognitionRevision.current++;
    releaseStroke();
    setDrawing([]);
    recognizeRemaining(strokes);
  }
  function undo() {
    if (!recognitionQueue.current.active || closingRef.current) return;
    const wasDrawing = activeStroke.current !== null;
    recognitionRevision.current++;
    recognitionQueue.current.pending = null;
    releaseStroke();
    setDrawing([]);
    if (wasDrawing) {
      // Cancel only the unfinished stroke; completed ink stays available.
      recognizeRemaining(strokes);
      return;
    }
    if (!strokes.length) return;
    setRedoStrokes(current => [...current, strokes[strokes.length - 1]]);
    const nextStrokes = strokes.slice(0, -1);
    setStrokes(nextStrokes);
    recognizeRemaining(nextStrokes);
  }
  function redo() {
    if (!recognitionQueue.current.active || closingRef.current) return;
    if (activeStroke.current || !redoStrokes.length || strokes.length >= MAX_HANDWRITING_STROKES) return;
    recognitionRevision.current++;
    const nextStrokes = [...strokes, redoStrokes[redoStrokes.length - 1]];
    setRedoStrokes(current => current.slice(0, -1));
    setStrokes(nextStrokes);
    recognizeRemaining(nextStrokes);
  }
  function clear() {
    if (!recognitionQueue.current.active || closingRef.current) return;
    recognitionRevision.current++;
    recognitionQueue.current.pending = null;
    releaseStroke();
    setStrokes([]);
    setRedoStrokes([]);
    setDrawing([]);
    setCandidates([]);
    setNotice("请在左侧书写，松开鼠标后自动识别");
  }
  function editInk(event: import("react").KeyboardEvent<HTMLElement>) {
    if (event.defaultPrevented || event.nativeEvent.isComposing || event.keyCode === 229 || event.altKey) return;
    const target = event.target as HTMLElement;
    if (target.closest("input, textarea, select, [contenteditable=true]")) return;
    const key = event.key.toLowerCase();
    if ((event.ctrlKey || event.metaKey) && (key === "z" || key === "y")) {
      event.preventDefault();
      if (key === "y" || event.shiftKey) redo(); else undo();
    } else if (event.key === "Escape" && activeStroke.current) {
      event.preventDefault();
      undo();
    }
  }
  function navigateCandidates(event: import("react").KeyboardEvent<HTMLDivElement>) {
    if (event.defaultPrevented || event.nativeEvent.isComposing || event.keyCode === 229 ||
        event.ctrlKey || event.metaKey || event.altKey || event.shiftKey ||
        closingRef.current || submittingRef.current) return;
    if (!["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Home", "End"].includes(event.key)) return;
    const buttons = Array.from(event.currentTarget.querySelectorAll<HTMLButtonElement>(
      ".handwriting-candidate-submit:not(:disabled)"));
    const index = buttons.indexOf(event.target as HTMLButtonElement);
    if (index < 0) return;
    // The candidate grid has four columns; keep a partial final row reachable.
    const next = event.key === "Home" ? 0 : event.key === "End" ? buttons.length - 1
      : index + (event.key === "ArrowLeft" ? -1 : event.key === "ArrowRight" ? 1
        : event.key === "ArrowUp" ? -4 : 4);
    event.preventDefault();
    const target = buttons[Math.max(0, Math.min(buttons.length - 1, next))];
    target.focus({ preventScroll: true });
    target.scrollIntoView({ block: "nearest", inline: "nearest" });
  }
  async function chooseCandidate(candidate: string, copyOnly = false) {
    if (!recognitionQueue.current.active || closingRef.current || submittingRef.current || !candidates.includes(candidate)) return;
    const action = copyOnly ? client.copyHandwritingCandidate : client.submitHandwritingCandidate;
    if (!action) { setNotice(`已选择：${candidate}（等待宿主提交能力）`); return; }
    const revision = ++submissionRevision.current;
    const inkRevision = recognitionRevision.current;
    submittingRef.current = true;
    setSubmitting(true);
    setNotice(copyOnly ? "正在复制候选…" : "正在提交候选…");
    try {
      await action(candidate);
      if (revision === submissionRevision.current && inkRevision === recognitionRevision.current) {
        setNotice(copyOnly ? `已复制：${candidate}` : `已提交：${candidate}`);
      }
    } catch {
      if (revision === submissionRevision.current && inkRevision === recognitionRevision.current) {
        setNotice(copyOnly ? "复制失败，候选和笔画已保留，请重试" : "提交失败，可复制候选后手动粘贴，或重试");
      }
    } finally {
      if (revision === submissionRevision.current) {
        submittingRef.current = false;
        setSubmitting(false);
      }
    }
  }

  const renderStrokes = [...strokes, ...(drawing.length ? [{ points: drawing }] : [])];
  return <main className="native-panel handwriting-panel" onKeyDown={editInk} data-panel-theme={theme} aria-label="手写识别板">
    <header className="native-panel-header" {...drag}><span>水杉手写识别板</span><button type="button" aria-label="关闭" disabled={closing} onClick={() => void closeHandwriting()}>×</button></header>
    <div className="handwriting-panel-body">
      <section className="ink-canvas-section"><svg className="ink-canvas" tabIndex={0} viewBox="0 0 420 420" onPointerDown={start} onPointerMove={move} onPointerUp={end} onPointerCancel={cancel} onLostPointerCapture={cancel} aria-label="手写画布" aria-disabled={closing}>{renderStrokes.map((stroke, index) => stroke.points.length === 1 ? <circle key={index} cx={stroke.points[0].x} cy={stroke.points[0].y} r={2} /> : <polyline key={index} points={stroke.points.map(({ x, y }) => `${x},${y}`).join(" ")} />)}{!renderStrokes.length && <text x="210" y="215" textAnchor="middle">请在这里书写</text>}</svg><div className="handwriting-actions"><button type="button" onClick={undo} disabled={closing || (!strokes.length && !drawing.length)} aria-keyshortcuts="Control+z Meta+z">↶ 撤销</button><button type="button" onClick={redo} disabled={closing || !redoStrokes.length || drawing.length > 0} aria-keyshortcuts="Control+Shift+z Meta+Shift+z Control+y">↷ 重做</button><button type="button" onClick={clear} disabled={closing || (!strokes.length && !drawing.length && !redoStrokes.length)}>× 重写</button>{client.recognizeHandwriting && <button type="button" onClick={retryRecognition} disabled={closing || !strokes.length || drawing.length > 0 || recognizing || submitting}>{recognizing ? "识别中…" : "重新识别"}</button>}</div></section>
      <section className="recognition-section"><h2>识别结果</h2>
        <div className="handwriting-actions" role="group" aria-label="点击手写候选的操作">
          <span>点击候选：</span>
          <button type="button" aria-pressed={effectiveMode === "copy"} disabled={closing || submitting || !client.copyHandwritingCandidate} onClick={() => selectActivation("copy")}>复制</button>
          <button type="button" aria-pressed={effectiveMode === "input"} disabled={closing || submitting || !client.submitHandwritingCandidate} onClick={() => selectActivation("input")}>输入</button>
        </div>
        <div className="handwriting-candidate-grid" onKeyDown={navigateCandidates}>{candidates.map(candidate => <div className="handwriting-candidate" key={candidate}>
          <HandwritingCandidateButton candidate={candidate} copy={effectiveMode === "copy"} disabled={closing || submitting} onChoose={() => void chooseCandidate(candidate, effectiveMode === "copy")} />
          {effectiveMode === "copy" && client.submitHandwritingCandidate
            ? <button type="button" className="handwriting-candidate-copy" aria-label={`输入候选 ${candidate}`} disabled={closing || submitting} onClick={() => void chooseCandidate(candidate)}>输入</button>
            : effectiveMode === "input" && client.copyHandwritingCandidate && <button type="button" className="handwriting-candidate-copy" aria-label={`复制候选 ${candidate}`} disabled={closing || submitting} onClick={() => void chooseCandidate(candidate, true)}>复制</button>}
        </div>)}</div><p role="status">{notice}</p></section>
    </div>
  </main>;
}

export function VoicePanel({ client, theme = "dark" }: { client: VoicePanelClient; theme?: "dark" | "light" }) {
  const [inputLevel, setInputLevel] = useState<number | undefined>();
  const [language, setLanguage] = useState("zh-cn");
  const [text, setText] = useState("");
  const exceedsSubmitLimit = client.maxSubmitBytes !== undefined
    && new TextEncoder().encode(text).length > client.maxSubmitBytes;
  const textRevision = useRef(0);
  function updateText(value: string) { textRevision.current++; setText(value); }
  const [submitting, setSubmitting] = useState(false);
  const [copying, setCopying] = useState(false);
  const submittingRef = useRef(false);
  const submissionRevision = useRef(0);
  const [busy, setBusy] = useState(false);
  const busyRef = useRef(false);
  const [stopping, setStopping] = useState(false);
  const stoppingRef = useRef(false);
  const recognitionRevision = useRef(0);
  const [notice, setNotice] = useState("点击开始后由宿主录音并进行语音识别");
  const drag = usePanelDrag(client, () => setNotice("无法移动窗口，请重试。"));

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

  useEffect(() => {
    submittingRef.current = false;
    setSubmitting(false);
    setCopying(false);
    setBusy(false);
    stoppingRef.current = false;
    setStopping(false);
    return () => {
      submissionRevision.current++;
      submittingRef.current = false;
      recognitionRevision.current++;
      const wasBusy = busyRef.current;
      busyRef.current = false;
      if (wasBusy && client.cancelVoice) void client.cancelVoice().catch(() => undefined);
    };
  }, [client]);

  useEffect(() => {
    if (!client.onVoiceUpdate) return;
    let active = true;
    let unlisten: (() => void) | undefined;
    void client.onVoiceUpdate(update => {
      if (!active || !busyRef.current) return;
      if (update.level !== undefined) {
        if (!stoppingRef.current && Number.isFinite(update.level) && update.level >= 0 && update.level <= 1) {
          setInputLevel(update.level);
        }
        return;
      }
      if (update.phase) {
        const labels = { recording: "正在录音…", recognizing: "正在识别…", polishing: "正在润色…" };
        setNotice(labels[update.phase]);
        if (update.phase !== "recording") {
          stoppingRef.current = true;
          setStopping(true);
        }
        return;
      }
      updateText(update.text);
      setNotice(update.final ? (update.text ? "识别完成，点击提交即可输入" : "没有识别到内容") : stoppingRef.current ? "正在识别…" : "正在录音并识别…");
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
    if (busyRef.current || submittingRef.current) return;
    if (!client.recognizeVoice) {
      setNotice("当前宿主未提供语音识别能力");
      return;
    }
    if (!validVoiceLanguage(language)) {
      setNotice("请输入有效的识别语言码");
      return;
    }
    const revision = ++recognitionRevision.current;
    busyRef.current = true;
    setBusy(true);
    setInputLevel(undefined);
    updateText("");
    setNotice("正在录音并识别…");
    try {
      const result = await client.recognizeVoice(language);
      if (revision !== recognitionRevision.current) return;
      updateText(result.text);
      setNotice(result.text ? "识别完成，点击提交即可输入" : "没有识别到内容");
    } catch {
      if (revision === recognitionRevision.current) setNotice("语音识别失败，请确认录音服务已启动");
    } finally {
      if (revision === recognitionRevision.current) {
        busyRef.current = false;
        setBusy(false);
        stoppingRef.current = false;
        setStopping(false);
      }
    }
  }

  async function submit(copyOnly = false) {
    const send = copyOnly ? client.copyText : client.sendVoiceText ?? client.sendText;
    if (!text || !send || busyRef.current || submittingRef.current) return;
    if (!copyOnly && exceedsSubmitLimit) {
      setNotice("内容超过单次提交长度，请精简或复制结果后手动粘贴");
      return;
    }
    const revision = ++submissionRevision.current;
    const submittedTextRevision = textRevision.current;
    submittingRef.current = true;
    setSubmitting(true);
    setCopying(copyOnly);
    setNotice(copyOnly ? "正在复制…" : "正在提交…");
    try {
      await send(text);
      if (revision !== submissionRevision.current) return;
      if (submittedTextRevision !== textRevision.current) {
        setNotice(copyOnly ? "上一版内容已复制，当前内容已保留" : "上一版内容已提交，当前内容已保留");
        return;
      }
      if (copyOnly) {
        setNotice("识别结果已复制，文本已保留");
      } else {
        setNotice(`已提交：${text}`);
        updateText("");
      }
    } catch {
      if (revision === submissionRevision.current) setNotice(copyOnly ? "复制失败，识别结果已保留" : "提交失败，前台输入窗口可能已关闭");
    } finally {
      if (revision === submissionRevision.current) {
        submittingRef.current = false;
        setSubmitting(false);
        setCopying(false);
      }
    }
  }

  async function stop() {
    if (!client.stopVoice) { await cancel(); return; }
    if (!busyRef.current || stoppingRef.current) return;
    const revision = recognitionRevision.current;
    stoppingRef.current = true;
    setStopping(true);
    setNotice("正在完成识别…");
    try { await client.stopVoice(); }
    catch {
      if (revision === recognitionRevision.current && busyRef.current) {
        stoppingRef.current = false;
        setStopping(false);
        setNotice("停止录音失败，请重试或取消录音");
      }
    }
  }

  async function cancel() {
    recognitionRevision.current++;
    busyRef.current = false;
    // Cancellation is immediate even if the provider acknowledgement is delayed.
    setBusy(false);
    stoppingRef.current = false;
    setStopping(false);
    setNotice("录音已停止");
    try { await client.cancelVoice?.(); } catch { /* provider may already have stopped */ }
  }

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== "Escape" || event.isComposing || event.ctrlKey || event.altKey || event.metaKey || event.shiftKey
        || !busyRef.current || !client.cancelVoice) return;
      event.preventDefault();
      event.stopPropagation();
      void cancel();
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [client]);

  async function close() {
    submissionRevision.current++;
    recognitionRevision.current++;
    const wasBusy = busyRef.current;
    busyRef.current = false;
    setBusy(false);
    stoppingRef.current = false;
    setStopping(false);
    if (wasBusy && client.cancelVoice) {
      try { await client.cancelVoice(); } catch { /* close even if provider is gone */ }
    }
    await client.close();
  }

  return <main className="native-panel voice-panel" data-panel-theme={theme} aria-label="语音输入">
    <header className="native-panel-header" {...drag}><span>水杉语音输入</span><button type="button" aria-label="关闭" onClick={() => void close()}>×</button></header>
    <div className="voice-panel-body">
      <div className="voice-panel-icon" aria-hidden="true">🎙</div>
      <h1>语音输入</h1>
      {busy && !stopping && inputLevel !== undefined && <label>麦克风音量 <meter aria-label="麦克风音量" min={0} max={1} value={inputLevel} /></label>}
      <p className="voice-panel-description">录音和识别由已配置的 Linux provider 服务完成，输入法不会保存原始音频。</p>
      <label className="voice-panel-language">识别语言<input value={language} maxLength={64} list="voice-language-options" onChange={event => setLanguage(event.target.value)} disabled={busy} /><datalist id="voice-language-options"><option value="zh-cn">中文（普通话）</option><option value="en">English</option><option value="ja">日本語</option><option value="auto">自动识别</option></datalist></label>
      <button type="button" className="voice-panel-record" onClick={() => void (busy ? stop() : recognize())} disabled={submitting || stopping || (busy && !(client.stopVoice ?? client.cancelVoice))}>{stopping ? "正在完成识别…" : busy ? "停止录音" : "开始录音"}</button>
      {busy && client.stopVoice && client.cancelVoice && <button type="button" aria-keyshortcuts="Escape" onClick={() => void cancel()}>取消录音</button>}
      <textarea aria-label="识别结果" aria-describedby={exceedsSubmitLimit ? "voice-result-limit" : undefined} aria-invalid={exceedsSubmitLimit || undefined} value={text} maxLength={4096} onChange={event => updateText(event.target.value)} placeholder="识别结果会显示在这里" rows={4} />
      {exceedsSubmitLimit && <p id="voice-result-limit" className="voice-panel-description" role="status">内容超过单次提交长度，请精简或复制结果后手动粘贴。</p>}
      <button type="button" className="voice-panel-submit" onClick={() => void submit()} disabled={!text || exceedsSubmitLimit || !(client.sendVoiceText ?? client.sendText) || busy || submitting}>{submitting && !copying ? "正在提交…" : "提交到当前窗口"}</button>
      {client.copyText && <button type="button" onClick={() => void submit(true)} disabled={!text || busy || submitting}>{copying ? "正在复制…" : "复制结果"}</button>}
      <button type="button" onClick={() => { updateText(""); setNotice("识别结果已清空"); }} disabled={!text || busy}>清空结果</button>
      {busy && client.cancelVoice && <p className="voice-panel-description">按 Esc 取消录音</p>}
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
  const [items, setItems] = useState<CloudClipboardItem[]>([]);
  const [draft, setDraft] = useState("");
  const [enabled, setEnabled] = useState(true);
  const [busy, setBusy] = useState(false);
  const refreshRevision = useRef(0);
  const busyRef = useRef(false);
  const draftRevision = useRef(0);
  const searchRef = useRef("");
  const [notice, setNotice] = useState("只上传你明确选择的内容");

  async function run(action: (revision: number) => Promise<void>, failure: string) {
    if (busyRef.current) return;
    const revision = ++refreshRevision.current;
    busyRef.current = true;
    setBusy(true);
    try { await action(revision); }
    catch { if (revision === refreshRevision.current) setNotice(failure); }
    finally {
      if (revision === refreshRevision.current) {
        busyRef.current = false;
        setBusy(false);
      }
    }
  }

  async function load(revision: number, nextSearch: string) {
    const result = await client.request({ operation: "list", search: nextSearch });
    if (revision !== refreshRevision.current) return;
    setItems(cloudClipboardItems(result));
    if (typeof result.enabled === "boolean") setEnabled(result.enabled);
    setNotice("云剪贴板已刷新");
  }

  function refresh(nextSearch = searchRef.current) {
    return run(revision => load(revision, nextSearch), "无法访问云剪贴板服务");
  }

  useEffect(() => {
    let active = true;
    busyRef.current = false;
    setItems([]);
    if (client.rememberInputTarget) void client.rememberInputTarget().catch(() => {
      if (active) setNotice("未能记录前台输入窗口");
    });
    void refresh(searchRef.current);
    return () => { active = false; refreshRevision.current++; busyRef.current = false; };
  }, [client]);

  function add() {
    if (!draft || !enabled) return;
    const uploadedRevision = draftRevision.current;
    return run(async revision => {
      await client.request({ operation: "add", text: draft });
      if (revision !== refreshRevision.current) return;
      if (uploadedRevision === draftRevision.current) setDraft("");
      try { await load(revision, searchRef.current); }
      catch { if (revision === refreshRevision.current) setNotice("已上传，但历史刷新失败，请点击刷新"); }
    }, "上传失败，请确认账户 provider 已连接");
  }

  function remove(id: string) {
    return run(async revision => {
      await client.request({ operation: "delete", id });
      if (revision !== refreshRevision.current) return;
      try { await load(revision, searchRef.current); }
      catch { if (revision === refreshRevision.current) setNotice("已删除，但历史刷新失败，请点击刷新"); }
    }, "删除失败");
  }

  function toggle() {
    const next = !enabled;
    return run(async revision => {
      const result = await client.request({ operation: "set_enabled", enabled: next });
      if (revision !== refreshRevision.current) return;
      const effective = typeof result.enabled === "boolean" ? result.enabled : next;
      setEnabled(effective);
      setNotice(effective ? "云剪贴板已开启" : "云剪贴板已关闭");
    }, "更新云剪贴板设置失败");
  }

  function choose(item: CloudClipboardItem, copyOnly = false) {
    const send = copyOnly ? client.copyText : client.sendText;
    if (!send) { setNotice("当前宿主未提供此操作"); return; }
    return run(async revision => {
      await send(item.text);
      if (revision === refreshRevision.current) setNotice(copyOnly ? "已复制到本机剪贴板" : `已输入：${item.text}`);
    }, copyOnly ? "复制失败，请重试" : "提交失败，可复制后手动粘贴");
  }

  return <main className="native-panel cloud-clipboard-panel" aria-label="云剪贴板">
    <header className="native-panel-header"><span>水杉云剪贴板</span><button type="button" aria-label="关闭" onClick={() => void client.close()}>×</button></header>
    <div className="cloud-clipboard-body">
      <p className="cloud-clipboard-description">只上传你明确选择的文本，不自动读取本地剪贴板。</p>
      <label className="cloud-clipboard-toggle"><span>启用云剪贴板</span><input type="checkbox" checked={enabled} onChange={() => void toggle()} disabled={busy} /></label>
      <div className="cloud-clipboard-search"><input aria-label="搜索云端历史" value={search} onChange={event => { searchRef.current = event.target.value; setSearch(event.target.value); }} onKeyDown={event => { if (event.key === "Enter") void refresh(); }} placeholder="搜索云端历史" /><button type="button" onClick={() => void refresh()} disabled={busy}>刷新</button></div>
      <div className="cloud-clipboard-add"><textarea aria-label="待上传文本" value={draft} onChange={event => { draftRevision.current++; setDraft(event.target.value); }} placeholder="输入要上传的文本" rows={3} /><button type="button" onClick={() => void add()} disabled={!enabled || !draft || busy}>上传明确选择的文本</button></div>
      <div className="cloud-clipboard-list" aria-label="云端历史">{items.length ? items.map(item => <article className="cloud-clipboard-item" key={item.id}><button type="button" disabled={busy} onClick={() => void choose(item)}>{item.text}</button>{client.copyText && <button type="button" disabled={busy} aria-label="复制此条云端记录" onClick={() => void choose(item, true)}>复制</button>}<button type="button" className="cloud-clipboard-delete" aria-label={`删除 ${item.text}`} onClick={() => void remove(item.id)} disabled={busy}>删除</button></article>) : <p className="cloud-clipboard-empty">暂无云端历史</p>}</div>
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
  const refreshRevision = useRef(0);
  const busyRef = useRef(false);
  const searchRef = useRef("");

  async function run(action: (revision: number) => Promise<void>, failure: string) {
    if (busyRef.current) return;
    const revision = ++refreshRevision.current;
    busyRef.current = true;
    setBusy(true);
    try { await action(revision); }
    catch { if (revision === refreshRevision.current) setNotice(failure); }
    finally {
      if (revision === refreshRevision.current) {
        busyRef.current = false;
        setBusy(false);
      }
    }
  }

  async function load(revision: number, nextOffset: number, nextSearch: string, nextKind: CloudDictionaryKind) {
    const result = await client.request({ operation: "list", kind: nextKind, offset: nextOffset, search: nextSearch });
    if (revision !== refreshRevision.current) return;
    setEntries(cloudDictionaryEntries(result));
    setOffset(typeof result.offset === "number" ? result.offset : nextOffset);
    setHasMore(result.has_more === true);
  }

  function refresh(nextOffset = 0, nextSearch = searchRef.current, nextKind = kind) {
    return run(async revision => {
      await load(revision, nextOffset, nextSearch, nextKind);
      if (revision === refreshRevision.current) setNotice("云词典已刷新");
    }, "无法访问云词典服务，请确认 provider 已连接");
  }

  useEffect(() => {
    busyRef.current = false;
    setEntries([]);
    setOffset(0);
    setHasMore(false);
    setForm(null);
    void refresh(0);
    return () => { refreshRevision.current++; };
  }, [client]);

  function beginAdd() {
    if (!busyRef.current) setForm({ entry: null, code: "", word: "", weight: 100000 });
  }
  function beginEdit(entry: CloudDictionaryEntry) {
    if (!busyRef.current) setForm({ entry, code: entry.code, word: entry.word, weight: entry.weight });
  }

  async function reloadAfterMutation(revision: number, success: string) {
    if (revision !== refreshRevision.current) return;
    try {
      await load(revision, 0, searchRef.current, kind);
      if (revision === refreshRevision.current) setNotice(success);
    } catch {
      if (revision === refreshRevision.current) {
        setEntries([]);
        setOffset(0);
        setHasMore(false);
        setNotice(`${success}，但列表刷新失败，请重新查询`);
      }
    }
  }

  function save() {
    if (busyRef.current) return;
    if (!form || !form.code.trim() || !form.word.trim()) { setNotice("编码和词条不能为空"); return; }
    return run(async revision => {
      const code = form.code.trim();
      const word = form.word;
      if (form.entry) {
        await client.request({ operation: "update", kind, id: form.entry.id, code, word, weight: form.weight, revision: form.entry.revision });
      } else {
        await client.request({ operation: "add", kind, code, word, weight: form.weight });
      }
      if (revision !== refreshRevision.current) return;
      setForm(null);
      await reloadAfterMutation(revision, "云词条已保存");
    }, "云词条保存失败，请刷新后重试");
  }

  function remove(entry: CloudDictionaryEntry) {
    return run(async revision => {
      await client.request({ operation: "delete", kind, id: entry.id, revision: entry.revision });
      if (revision !== refreshRevision.current) return;
      setForm(current => current?.entry?.id === entry.id ? null : current);
      await reloadAfterMutation(revision, "云词条已删除");
    }, "云词条删除失败，请刷新后重试");
  }

  function importFile(file: File) {
    if (busyRef.current) return;
    if (file.size > 65536) { setNotice("导入文件不能超过 64 KiB"); return; }
    return run(async revision => {
      const text = await file.text();
      if (revision !== refreshRevision.current) return;
      await client.request({ operation: "import", kind, format, text });
      await reloadAfterMutation(revision, "云词库已导入");
    }, "导入失败，请检查 UTF-8 TSV 文件格式");
  }

  function exportDictionary() {
    return run(async revision => {
      if (format === "hans") throw new Error("format cannot be exported");
      const result = await client.request({ operation: "export", kind, format });
      if (revision !== refreshRevision.current) return;
      const text = typeof result.text === "string" ? result.text : result.content;
      if (typeof text !== "string") throw new Error("provider returned no file");
      const anchor = document.createElement("a");
      const url = URL.createObjectURL(new Blob([text], { type: "text/plain;charset=utf-8" }));
      anchor.href = url;
      anchor.download = result.filename || `msime-${kind}-dictionary.tsv`;
      document.body.appendChild(anchor);
      try { anchor.click(); setNotice("云词库已导出"); }
      finally {
        anchor.remove();
        window.setTimeout(() => URL.revokeObjectURL(url), 1000);
      }
    }, "导出失败，请确认 provider 已连接");
  }

  function changeKind(next: CloudDictionaryKind) {
    if (busyRef.current || next === kind) return;
    setKind(next);
    setForm(null);
    if (next !== "pinyin" && format === "hans") setFormat("standard");
    setOffset(0);
    setEntries([]);
    setHasMore(false);
    void refresh(0, searchRef.current, next);
  }
  return <main className="native-panel cloud-dictionary-panel" aria-label="云词典">
    <header className="native-panel-header"><span>水杉云词典</span><button type="button" aria-label="关闭" onClick={() => void client.close()}>×</button></header>
    <div className="cloud-dictionary-body">
      <p className="cloud-dictionary-description">管理当前账号的云端词条。修改需要 provider 提供登录态和同步服务。</p>
      <div className="cloud-dictionary-toolbar"><label>词库<select aria-label="词库类型" value={kind} onChange={event => changeKind(event.target.value as CloudDictionaryKind)} disabled={busy}>{cloudDictionaryKinds.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label><label className="cloud-dictionary-search">搜索<input aria-label="搜索云词条" value={search} onChange={event => { searchRef.current = event.target.value; setSearch(event.target.value); }} onKeyDown={event => { if (event.key === "Enter") void refresh(0); }} placeholder="词条或编码" /></label><button type="button" onClick={() => void refresh(0)} disabled={busy}>查询</button><button type="button" onClick={beginAdd} disabled={busy}>添加词条</button></div>
      <div className="cloud-dictionary-actions"><label>文件格式<select aria-label="文件格式" value={format} onChange={event => setFormat(event.target.value as CloudDictionaryFileFormat)} disabled={busy}><option value="standard">标准 TSV</option><option value="windows">Windows TSV</option>{kind === "pinyin" && <option value="hans">汉字自动注音（仅导入）</option>}</select></label><button type="button" onClick={() => void exportDictionary()} disabled={busy || format === "hans"}>导出</button><label className="secondary">导入<input hidden type="file" accept=".txt,.tsv,text/plain" disabled={busy} onChange={event => { const file = event.target.files?.[0]; if (file) void importFile(file); event.currentTarget.value = ""; }} /></label></div>
      {form && <div className="cloud-dictionary-form"><label>编码<input disabled={busy} value={form.code} onChange={event => setForm({ ...form, code: event.target.value })} /></label><label className="cloud-dictionary-word">词条<input disabled={busy} value={form.word} onChange={event => setForm({ ...form, word: event.target.value })} /></label><label>权重<input disabled={busy} type="number" min="0" value={form.weight} onChange={event => setForm({ ...form, weight: Number(event.target.value) })} /></label><button type="button" onClick={() => void save()} disabled={busy}>保存</button><button type="button" className="secondary" onClick={() => setForm(null)} disabled={busy}>取消</button></div>}
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
  const normalizedQuery = query.trim().toLocaleLowerCase();
  return !normalizedQuery || `${item.text} ${item.keywords}`.toLocaleLowerCase().includes(normalizedQuery);
}

function clipboardTooltip(text: string) {
  const preview = text.replace(/[\r\t]/g, " ").replace(/\n+$/, "");
  const characters = Array.from(preview);
  return characters.length > 200 ? `${characters.slice(0, 200).join("")}…` : preview;
}

function flattenGroups(groups: EmojiCatalogGroup[]) {
  return groups.flatMap(group => group.items);
}

export function EmojiPanel({ client, theme = "dark", initialPage = "home" }: { client: EmojiPanelClient; theme?: "dark" | "light"; initialPage?: "home" | "clipboard" }) {
  const [page, setPage] = useState<EmojiPage>(initialPage);
  const [query, setQuery] = useState("");
  const [categories, setCategories] = useState({ emoji: "all", symbols: "all" });
  const [recent, setRecent] = useState<EmojiCatalogItem[]>(() => {
    try {
      const value: unknown = typeof window === "undefined" ? null : JSON.parse(window.localStorage.getItem("msime.emoji.recent") ?? "null");
      return Array.isArray(value) ? value.filter(item => item && typeof item.text === "string" && typeof item.keywords === "string").slice(0, 28) as EmojiCatalogItem[] : [];
    } catch { return []; }
  });
  const [clipboard, setClipboard] = useState<string[]>([]);
  const [clipboardBusy, setClipboardBusy] = useState(false);
  const [clipboardLoadFailed, setClipboardLoadFailed] = useState(false);
  const [clipboardRefresh, setClipboardRefresh] = useState(0);
  const [activationMode, setActivationMode] = useState<"copy" | "input">("copy");
  const operationRevision = useRef(0);
  const [clipboardEnabled, setClipboardEnabled] = useState<boolean | null>(null);
  const clipboardMutation = useRef(false);
  const clipboardGeneration = useRef(0);
  const [notice, setNotice] = useState("点击项目即可复制");
  const [catalog, setCatalog] = useState({ emoji: fallbackEmojiGroups, kaomoji: fallbackKaomojiGroups, symbols: fallbackSymbolGroups });

  useEffect(() => {
    clipboardMutation.current = false;
    setClipboardBusy(false);
    return () => { operationRevision.current++; };
  }, [client]);

  async function runOperation(action: (revision: number) => Promise<void>, failure: string) {
    if (clipboardMutation.current) return;
    const revision = ++operationRevision.current;
    clipboardMutation.current = true;
    setClipboardBusy(true);
    try { await action(revision); }
    catch { if (revision === operationRevision.current) setNotice(failure); }
    finally {
      if (revision === operationRevision.current) {
        clipboardMutation.current = false;
        setClipboardBusy(false);
      }
    }
  }

  useEffect(() => {
    try { window.localStorage.setItem("msime.emoji.recent", JSON.stringify(recent.slice(0, 28))); } catch { /* preference is optional */ }
  }, [recent]);

  useEffect(() => {
    if (!client.rememberInputTarget) return;
    void client.rememberInputTarget().catch(() => setNotice("未能记录前台输入窗口"));
  }, [client]);

  useEffect(() => {
    if (!client.loadCatalog) return;
    let active = true;
    void client.loadCatalog().then(next => { if (active) setCatalog(next); }).catch(() => { if (active) setNotice("目录不可用，已使用内置目录"); });
    return () => { active = false; };
  }, [client]);

  useEffect(() => {
    if (!client.clipboard?.list) { setClipboardLoadFailed(false); return; }
    let active = true;
    let unsubscribe: (() => void) | undefined;
    const refresh = () => {
      const request = ++clipboardGeneration.current;
      void Promise.all([client.clipboard!.list!(), client.clipboard?.isEnabled?.() ?? Promise.resolve(true)]).then(([value, enabled]) => {
        if (active && request === clipboardGeneration.current) {
          setClipboard(enabled ? value : []);
          setClipboardEnabled(enabled);
          setClipboardLoadFailed(false);
        }
      }).catch(() => {
        if (active && request === clipboardGeneration.current) {
          setClipboard([]);
          setClipboardEnabled(null);
          setClipboardLoadFailed(true);
        }
      });
    };
    const start = async () => {
      try {
        const stop = await client.clipboard?.onChanged?.(refresh);
        if (!active) { stop?.(); return; }
        unsubscribe = stop;
      } catch { /* Opening and tab changes still refresh without notifications. */ }
      if (active) refresh();
    };
    void start();
    return () => { active = false; ++clipboardGeneration.current; unsubscribe?.(); };
  }, [client, page, clipboardRefresh]);

  type DisplayGroup = EmojiCatalogGroup & { moreTarget?: EmojiPage; flow?: boolean };
  const groups = page === "emoji" ? catalog.emoji : page === "kaomoji" ? catalog.kaomoji : catalog.symbols;
  const categoryPage = page === "emoji" || page === "symbols" ? page : null;
  const selectedCategory = categoryPage ? categories[categoryPage] : "all";
  const activeCategory = selectedCategory === "recent" || groups.some(group => `group:${group.title}` === selectedCategory) ? selectedCategory : "all";
  const recentGroup = { title: "最近使用", icon: "◷", items: recent };
  const selectedGroups = categoryPage && !query.trim()
    ? activeCategory === "recent" ? [recentGroup] : activeCategory === "all" ? groups : groups.filter(group => `group:${group.title}` === activeCategory)
    : groups;
  const filteredGroups: DisplayGroup[] = selectedGroups.map(group => ({ ...group, flow: page === "kaomoji", items: group.items.filter(item => matchesEmojiItem(item, query)) })).filter(group => group.items.length);
  const symbolPreview = query.trim()
    ? flattenGroups(catalog.symbols).filter(item => matchesEmojiItem(item, query)).slice(0, 18)
    : catalog.symbols.flatMap(group => group.items.map((item, index) => ({ item, index }))).sort((left, right) => left.index - right.index).slice(0, 18).map(({ item }) => item);
  const homeGroups: DisplayGroup[] = [
    { ...recentGroup, items: recent.filter(item => matchesEmojiItem(item, query)) },
    { title: "Emoji", icon: catalog.emoji[0]?.icon ?? "😀", moreTarget: "emoji", items: flattenGroups(catalog.emoji).filter(item => matchesEmojiItem(item, query)).slice(0, 18) },
    { title: "Kaomoji", icon: catalog.kaomoji[0]?.icon ?? "ヾ", moreTarget: "kaomoji", flow: true, items: flattenGroups(catalog.kaomoji).filter(item => matchesEmojiItem(item, query)).slice(0, 12) },
    { title: "Symbols", icon: catalog.symbols[0]?.icon ?? "★", moreTarget: "symbols", items: symbolPreview },
  ];

  function selectCategory(next: string) {
    if (!categoryPage) return;
    setCategories(current => ({ ...current, [categoryPage]: next }));
    setQuery("");
  }

  const visibleClipboard = clipboard.filter(item => matchesEmojiItem({ text: item, keywords: "" }, query));
  const canCopy = Boolean(client.copyText ?? client.clipboard?.copy);
  const effectiveMode = !client.sendText ? "copy" : !canCopy ? "input" : activationMode;

  function copy(text: string, isClipboardItem = false, keywords = text) {
    const input = !isClipboardItem && effectiveMode === "input";
    const action = input ? client.sendText : isClipboardItem ? client.clipboard?.copy ?? client.copyText : client.copyText ?? client.clipboard?.copy;
    if (!action) { setNotice("当前宿主未提供此操作"); return; }
    return runOperation(async revision => {
      await action(text);
      if (revision !== operationRevision.current) return;
      setNotice(input ? "已输入到原应用" : "已复制到剪贴板");
      if (!isClipboardItem) setRecent(current => [{ text, keywords }, ...current.filter(item => item.text !== text)].slice(0, 28));
    }, input ? "输入失败，可切换复制后手动粘贴" : "无法访问剪贴板");
  }

  function changeClipboard(action: () => Promise<string[] | void>, fallback: () => string[], message: string) {
    return runOperation(async revision => {
      ++clipboardGeneration.current;
      const result = await action();
      if (revision !== operationRevision.current) return;
      const request = ++clipboardGeneration.current;
      try {
        const [next, enabled] = await Promise.all([
          client.clipboard?.list ? client.clipboard.list() : Promise.resolve(result ?? fallback()),
          client.clipboard?.isEnabled?.() ?? Promise.resolve(true),
        ]);
        if (revision !== operationRevision.current) return;
        if (request === clipboardGeneration.current) {
          setClipboard(enabled ? next : []);
          setClipboardEnabled(enabled);
          setClipboardLoadFailed(false);
        }
        setNotice(message);
      } catch {
        if (revision === operationRevision.current) setNotice(`${message}，但列表刷新失败，请重新打开剪贴板页`);
      }
    }, "无法更新剪贴板历史");
  }

  function enableClipboard() {
    if (client.clipboard?.enable) return changeClipboard(client.clipboard.enable, () => [], "剪贴板历史已开启");
  }

  function syncClipboard() {
    if (client.clipboard?.sync) return changeClipboard(client.clipboard.sync, () => clipboard, "剪贴板已同步");
  }

  function pasteClipboard(text: string) {
    const paste = client.clipboard?.paste;
    if (!paste) return;
    return runOperation(async revision => {
      await paste(text);
      if (revision === operationRevision.current) setNotice("已粘贴到原应用");
    }, "无法粘贴，请使用复制后手动粘贴");
  }

  function removeClipboard(text: string) {
    if (client.clipboard?.remove) return changeClipboard(() => client.clipboard!.remove!(text), () => clipboard.filter(item => item !== text), "记录已删除");
  }

  function clearClipboard() {
    if (client.clipboard?.clear) return changeClipboard(client.clipboard.clear, () => [], "剪贴板历史已清空");
  }

  function selectPage(next: EmojiPage, preserveSearch = false) {
    setPage(next);
    if (!preserveSearch) setQuery("");
    setNotice(next === "clipboard" || effectiveMode === "copy" ? "点击项目即可复制" : "点击项目即可输入到原应用");
  }

  const isDetail = page !== "home";
  const displayGroups = page === "home" ? homeGroups.filter(group => group.items.length) : filteredGroups;
  function clearRecent() {
    if (clipboardMutation.current) return;
    setRecent([]);
    setNotice("最近使用已清除");
  }
  function closeEmoji() {
    return runOperation(async () => { await client.close(); }, "无法关闭面板，请重试");
  }
  const navigation = useEmojiNavigation(() => {
    if (page !== "home") {
      selectPage("home");
      navigation.ref.current?.querySelector<HTMLInputElement>(".emoji-panel-search input")?.focus();
    } else {
      void closeEmoji();
    }
  }, JSON.stringify([page, query, activeCategory]));
  return <main {...navigation} className="native-panel emoji-panel" data-panel-theme={theme} aria-label="表情与符号">
    <header className="native-panel-header"><span>Emoji and more</span><button type="button" aria-label="关闭" disabled={clipboardBusy} onClick={() => void closeEmoji()}>×</button></header>
    <div className="emoji-panel-search"><span aria-hidden="true">⌕</span><input aria-label="搜索" value={query} onChange={event => setQuery(event.target.value)} placeholder={page === "clipboard" ? "搜索剪贴板" : "Search emoji, kaomoji, and symbols"} /></div>
    <nav className="emoji-panel-tabs" aria-label="面板分类">
      {emojiPages.map(item => <button type="button" key={item.id} className={page === item.id ? "active" : ""} aria-label={item.label} aria-pressed={page === item.id} onClick={() => selectPage(item.id)}><span aria-hidden="true">{item.icon}</span><small>{item.label}</small></button>)}
    </nav>
    {isDetail && <div className="emoji-panel-back"><button type="button" aria-label="返回" onClick={() => selectPage("home")}>‹ 返回</button></div>}
    {page !== "clipboard" && page !== "sticker" && page !== "gif" && canCopy && client.sendText && <div className="emoji-panel-activation" role="group" aria-label="点击项目时的操作">
      <span>点击项目：</span><button type="button" aria-pressed={effectiveMode === "copy"} disabled={clipboardBusy} onClick={() => { setActivationMode("copy"); setNotice("点击项目即可复制"); }}>复制</button><button type="button" aria-pressed={effectiveMode === "input"} disabled={clipboardBusy} onClick={() => { setActivationMode("input"); setNotice("点击项目即可输入到原应用"); }}>输入到原应用</button>
    </div>}
    {categoryPage && <nav className="emoji-panel-categories" aria-label={page === "emoji" ? "Emoji 子分类" : "符号子分类"}>
      <button type="button" aria-pressed={activeCategory === "all"} onClick={() => selectCategory("all")}>全部</button>
      {page === "emoji" && <button type="button" aria-pressed={activeCategory === "recent"} onClick={() => selectCategory("recent")}>◷ 最近使用</button>}
      {groups.map(group => <button type="button" key={group.title} aria-pressed={activeCategory === `group:${group.title}`} onClick={() => selectCategory(`group:${group.title}`)}><span aria-hidden="true">{group.icon}</span> {group.title}</button>)}
    </nav>}
    {page === "clipboard" ? <section className="emoji-panel-content clipboard-panel-content" aria-label="剪贴板历史">
      <div className="emoji-panel-toolbar"><h2>剪贴板</h2><div className="clipboard-panel-actions">{client.clipboard?.list && <button type="button" disabled={clipboardBusy} onClick={() => { if (!clipboardMutation.current) setClipboardRefresh(value => value + 1); }}>刷新列表</button>}{client.clipboard?.sync && <button type="button" disabled={clipboardBusy || clipboardEnabled === false} onClick={() => void syncClipboard()}>同步</button>}{client.clipboard?.clear && <button type="button" disabled={clipboardBusy || !clipboard.length} onClick={() => void clearClipboard()}>清空历史</button>}</div></div>
      {clipboardLoadFailed ? <p className="emoji-panel-empty" role="status">无法读取剪贴板历史，请点击“刷新列表”重试</p> : clipboardEnabled === false ? <div className="emoji-panel-empty"><p>剪贴板历史已关闭</p><p>开启后保存复制过的文本；关闭会清空历史。</p>{client.clipboard?.enable && <button type="button" disabled={clipboardBusy} onClick={() => void enableClipboard()}>开启剪贴板历史</button>}</div> : visibleClipboard.length ? <div className="clipboard-panel-list">{visibleClipboard.map(item => <div className="clipboard-panel-row" key={item}><button type="button" className="clipboard-panel-item" data-emoji-navigation-item disabled={clipboardBusy} title={clipboardTooltip(item)} onClick={() => void copy(item, true)}>{item.replace(/[\r\n\t]/g, " ")}</button>{client.clipboard?.paste && <button type="button" className="clipboard-panel-delete" disabled={clipboardBusy} aria-label="粘贴此条记录到原应用" onClick={() => void pasteClipboard(item)}>粘贴</button>}{client.clipboard?.remove && <button type="button" className="clipboard-panel-delete" disabled={clipboardBusy} aria-label="删除此条记录" onClick={() => void removeClipboard(item)}>删除</button>}</div>)}</div> : <p className="emoji-panel-empty" role="status">{query.trim() ? "没有匹配的剪贴板记录" : "暂无剪贴板记录"}</p>}
    </section> : page === "sticker" || page === "gif" ? <p className="emoji-panel-empty">{page === "sticker" ? "贴纸来源可在这里接入" : "GIF 来源可在这里接入"}</p> : <section className="emoji-panel-content" aria-label={page === "home" ? "最近使用与目录" : page === "emoji" ? "Emoji 目录" : page === "kaomoji" ? "颜文字目录" : "符号目录"}>
      {(page === "home" || (page === "emoji" && activeCategory === "recent" && !query.trim())) && recent.length > 0 && <div className="emoji-panel-toolbar"><span>最近使用</span><button type="button" onClick={clearRecent} disabled={clipboardBusy}>清除最近使用</button></div>}
      {displayGroups.map(group => <div className="emoji-panel-group" key={group.title}><div className="emoji-panel-group-title"><span>{group.icon}</span><h2>{group.title}</h2>{group.moreTarget && <button type="button" onClick={() => { setCategories(current => ({ ...current, emoji: "all", symbols: "all" })); selectPage(group.moreTarget!, true); }}>更多</button>}</div><div className={`emoji-panel-grid${group.flow ? " emoji-panel-flow" : ""}`}>{group.items.map(item => <button type="button" className="emoji-panel-item" data-emoji-navigation-item disabled={clipboardBusy} key={`${group.title}-${item.text}`} title={item.keywords} onClick={() => void copy(item.text, false, item.keywords)}>{item.text}</button>)}</div></div>)}
      {!displayGroups.length && <p className="emoji-panel-empty">{query ? "No results" : "暂无可显示内容"}</p>}
    </section>}
    <p className="emoji-panel-notice" role="status">{notice}</p>
  </main>;
}
