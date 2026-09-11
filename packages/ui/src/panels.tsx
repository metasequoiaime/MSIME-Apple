import { useState, type PointerEvent } from "react";

export interface PanelClient {
  close(): Promise<void>;
}

const keyboardRows = [
  ["Esc", ..."1234567890", "Backspace"],
  ["Tab", ..."QWERTYUIOP", "[", "]"],
  ["Caps", ..."ASDFGHJKL", ";", "'", "Enter"],
  ["Shift", ..."ZXCVBNM", ",", ".", "/", "Shift"],
  ["Ctrl", "Win", "Alt", "Space", "Alt", "Win", "Menu", "Ctrl"],
] as const;

export function KeyboardPanel({ client }: { client: PanelClient }) {
  const [activeModifiers, setActiveModifiers] = useState<string[]>([]);
  const [notice, setNotice] = useState("");
  function toggleModifier(key: string) {
    setActiveModifiers(current => current.includes(key) ? current.filter(value => value !== key) : [...current, key]);
  }
  function pressKey(key: string) {
    if (["Shift", "Ctrl", "Alt", "Win", "Caps"].includes(key)) {
      toggleModifier(key);
      return;
    }
    setNotice(`${activeModifiers.length ? `${activeModifiers.join("+")}+` : ""}${key}`);
    setActiveModifiers(current => current.filter(value => !["Shift", "Ctrl", "Alt", "Win"].includes(value)));
  }
  return <main className="native-panel keyboard-panel" aria-label="屏幕键盘">
    <header className="native-panel-header"><span>水杉屏幕键盘</span><button type="button" aria-label="关闭" onClick={() => void client.close()}>×</button></header>
    <div className="keyboard-panel-body">
      <div className="keyboard-panel-notice" role="status">{notice || "使用鼠标或触控方式输入文字与快捷按键"}</div>
      <div className="keyboard-layout">
        {keyboardRows.map((row, rowIndex) => <div className="keyboard-row" key={rowIndex}>{row.map((key, keyIndex) => <button type="button" key={`${key}-${keyIndex}`} aria-pressed={["Shift", "Ctrl", "Alt", "Win", "Caps"].includes(key) ? activeModifiers.includes(key) : undefined} className={`keyboard-key keyboard-key-${key.toLowerCase().replace(/[^a-z]/g, "special")}${activeModifiers.includes(key) ? " active" : ""}`} onClick={() => pressKey(key)}>{key === "Space" ? "" : key}</button>)}</div>)}
      </div>
    </div>
  </main>;
}

type Point = { x: number; y: number };

export function HandwritingPanel({ client }: { client: PanelClient }) {
  const [strokes, setStrokes] = useState<Point[][]>([]);
  const [drawing, setDrawing] = useState<Point[]>([]);
  const [notice, setNotice] = useState("请在左侧书写，松开鼠标后自动识别");
  const candidates = strokes.length ? ["水", "永", "木", "未"] : [];
  function point(event: PointerEvent<SVGSVGElement>): Point {
    const rect = event.currentTarget.getBoundingClientRect();
    return { x: event.clientX - rect.left, y: event.clientY - rect.top };
  }
  function start(event: PointerEvent<SVGSVGElement>) {
    event.currentTarget.setPointerCapture?.(event.pointerId);
    setDrawing([point(event)]);
  }
  function move(event: PointerEvent<SVGSVGElement>) {
    if (!drawing.length) return;
    const nextPoint = point(event);
    setDrawing(current => [...current, nextPoint]);
  }
  function end() {
    if (!drawing.length) return;
    setStrokes(current => [...current, drawing]);
    setDrawing([]);
    setNotice("识别结果将在原生识别接口接入后显示");
  }
  function undo() { setStrokes(current => { const next = current.slice(0, -1); if (!next.length) setNotice("请在左侧书写，松开鼠标后自动识别"); return next; }); }
  function clear() { setStrokes([]); setDrawing([]); setNotice("请在左侧书写，松开鼠标后自动识别"); }
  const renderStrokes = [...strokes, ...(drawing.length ? [drawing] : [])];
  return <main className="native-panel handwriting-panel" aria-label="手写识别板">
    <header className="native-panel-header"><span>水杉手写识别板</span><button type="button" aria-label="关闭" onClick={() => void client.close()}>×</button></header>
    <div className="handwriting-panel-body">
      <section className="ink-canvas-section"><svg className="ink-canvas" viewBox="0 0 420 420" onPointerDown={start} onPointerMove={move} onPointerUp={end} onPointerCancel={end} aria-label="手写画布">{renderStrokes.map((stroke, index) => <polyline key={index} points={stroke.map(({ x, y }) => `${x},${y}`).join(" ")} />)}{!renderStrokes.length && <text x="210" y="215" textAnchor="middle">请在这里书写</text>}</svg><div className="handwriting-actions"><button type="button" onClick={undo}>↶ 撤销</button><button type="button" onClick={clear}>× 重写</button></div></section>
      <section className="recognition-section"><h2>识别结果</h2><div className="handwriting-candidate-grid">{candidates.map(candidate => <button type="button" key={candidate} onClick={() => setNotice(`已选择：${candidate}`)}>{candidate}</button>)}</div><p role="status">{notice}</p></section>
    </div>
  </main>;
}
