import { useId } from "react";

// Built-in visual source: MSIME-Apple@11c950a63ec57656cd78b3f75aa621c293bfe453,
// platforms/ios/SharedUI/KeyboardSkinPreference.swift and KeyboardSkinBackgroundView.swift.
export type TouchKeyboardSkin = "forest" | "ocean" | "rose" | "porcelain" |
  "typewriter" | "candy" | "midnight" | "blueprint";

type Palette = { background: string; key: string; foreground: string; accent: string; action: string };
export type TouchKeyboardSkinOption = {
  id: TouchKeyboardSkin;
  title: string;
  description: string;
  light: Palette;
  dark: Palette;
  cornerRadius: number;
  borderWidth: number;
  shadowOpacity: number;
  shadowRadius: number;
  shadowOffset: number;
  monospaced: boolean;
  pattern: 0 | 1 | 2 | 3;
};

export const touchKeyboardSkinOptions: TouchKeyboardSkinOption[] = [
  { id: "forest", title: "水杉绿", description: "清新留白 · 经典圆角", light: { background: "#e8f0eb", key: "#fff", foreground: "#000", accent: "#185c47", action: "#185c47" }, dark: { background: "#17211c", key: "#303d36", foreground: "#fff", accent: "#73cca6", action: "#1f614a" }, cornerRadius: 8, borderWidth: 0, shadowOpacity: 0, shadowRadius: 3, shadowOffset: 2, monospaced: false, pattern: 0 },
  { id: "ocean", title: "海盐蓝", description: "海盐浅蓝 · 轻盈平面", light: { background: "#e6f0fa", key: "#fff", foreground: "#000", accent: "#1f5ca3", action: "#1f5ca3" }, dark: { background: "#171f2b", key: "#2e384a", foreground: "#fff", accent: "#80bdfa", action: "#295c9e" }, cornerRadius: 8, borderWidth: 0, shadowOpacity: 0, shadowRadius: 3, shadowOffset: 2, monospaced: false, pattern: 0 },
  { id: "rose", title: "浅蔷薇", description: "柔和蔷薇 · 简洁圆角", light: { background: "#fae8f0", key: "#fff", foreground: "#000", accent: "#a14063", action: "#a14063" }, dark: { background: "#291a21", key: "#45303b", foreground: "#fff", accent: "#f59ebd", action: "#8f3b5c" }, cornerRadius: 8, borderWidth: 0, shadowOpacity: 0, shadowRadius: 3, shadowOffset: 2, monospaced: false, pattern: 0 },
  { id: "porcelain", title: "素白瓷", description: "细线边框 · 克制直角", light: { background: "#ebedf0", key: "#fcfcfc", foreground: "#000", accent: "#333d47", action: "#333d47" }, dark: { background: "#1a1c21", key: "#33363b", foreground: "#fff", accent: "#ccd6e3", action: "#454f5c" }, cornerRadius: 3, borderWidth: .5, shadowOpacity: 0, shadowRadius: 3, shadowOffset: 2, monospaced: false, pattern: 0 },
  { id: "typewriter", title: "纸上时光", description: "暖纸网点 · 复古键帽", light: { background: "#e3d6bd", key: "#fcf5e0", foreground: "#000", accent: "#5e4026", action: "#5e4026" }, dark: { background: "#26211a", key: "#40382b", foreground: "#fff", accent: "#deb882", action: "#66472e" }, cornerRadius: 5, borderWidth: 1, shadowOpacity: .3, shadowRadius: 0, shadowOffset: 3, monospaced: true, pattern: 1 },
  { id: "candy", title: "奶油桃桃", description: "奶油波纹 · 饱满圆角", light: { background: "#fce0d1", key: "#fff7ed", foreground: "#000", accent: "#943852", action: "#943852" }, dark: { background: "#301f26", key: "#4d333d", foreground: "#fff", accent: "#ffa8ba", action: "#943852" }, cornerRadius: 18, borderWidth: 0, shadowOpacity: .16, shadowRadius: 3, shadowOffset: 2, monospaced: false, pattern: 3 },
  { id: "midnight", title: "霓虹夜航", description: "紫色星点 · 霓虹描边", light: { background: "#130f24", key: "#291f40", foreground: "#fff", accent: "#c7b0ff", action: "#663bb3" }, dark: { background: "#130f24", key: "#291f40", foreground: "#fff", accent: "#c7b0ff", action: "#663bb3" }, cornerRadius: 10, borderWidth: 1, shadowOpacity: 0, shadowRadius: 3, shadowOffset: 2, monospaced: false, pattern: 1 },
  { id: "blueprint", title: "工程蓝图", description: "蓝图网格 · 等宽字形", light: { background: "#0e2138", key: "#173352", foreground: "#fff", accent: "#8ad6ff", action: "#1f578a" }, dark: { background: "#0e2138", key: "#173352", foreground: "#fff", accent: "#8ad6ff", action: "#1f578a" }, cornerRadius: 3, borderWidth: 1, shadowOpacity: 0, shadowRadius: 3, shadowOffset: 2, monospaced: true, pattern: 2 },
];

// Layout source: MSIME-Windows@04a8df56f86312474a069f4335a1b58da7afaa9e,
// server/src/keyboard-panel/KeyboardPanel.cpp (GPL-3.0). This preview has no input actions.
const key = (label: string, weight = 1) => ({ label, weight });
const letters = (text: string) => [...text].map(label => key(label));
const rows = [
  [...letters("`1234567890-="), key("Backspace", 1.9)],
  [key("Tab", 1.5), ...letters("qwertyuiop[]"), key("\\", 1.4)],
  [key("Caps Lock", 1.85), ...letters("asdfghjkl;'"), key("Enter", 2)],
  [key("Shift", 2.35), ...letters("zxcvbnm,./"), key("Shift", 2.15)],
  [key("Ctrl", 1.25), key("Win", 1.25), key("Alt", 1.25), key("Space", 6.7), key("Alt", 1.25), key("Win", 1.25), key("Del", 1.25), key("Ctrl", 1.25)],
];
const actionLabels = new Set(["Backspace", "Enter", "Shift", "Del"]);

function optionFor(id: TouchKeyboardSkin): TouchKeyboardSkinOption {
  return touchKeyboardSkinOptions.find(option => option.id === id) ?? touchKeyboardSkinOptions[0];
}

function Pattern({ id, pattern, accent }: { id: string; pattern: number; accent: string }) {
  if (pattern === 0) return null;
  if (pattern === 1) return <pattern id={id} width="16" height="16" patternUnits="userSpaceOnUse"><circle cx="8.75" cy="8.75" r=".75" fill={accent} fillOpacity=".15" /></pattern>;
  if (pattern === 2) return <pattern id={id} width="20" height="20" patternUnits="userSpaceOnUse"><path d="M0 0H20M0 0V20" fill="none" stroke={accent} strokeOpacity=".15" strokeWidth=".5" /></pattern>;
  return <pattern id={id} width="48" height="48" patternUnits="userSpaceOnUse"><path d="M-12 42C4 0 27 65 60 1M-12 66C4 24 27 89 60 25" fill="none" stroke={accent} strokeOpacity=".15" strokeWidth="2" /></pattern>;
}

export function ScreenKeyboardPreview({ theme, skin = "forest", compact = false }: { theme: "dark" | "light"; skin?: TouchKeyboardSkin; compact?: boolean }) {
  const option = optionFor(skin);
  const palette = option[theme];
  const unique = useId().replaceAll(":", "");
  const patternId = `touch-skin-pattern-${unique}`;
  const shadowId = `touch-skin-shadow-${unique}`;
  const height = (400 - 28 - 7 - 4 * 4) / 5;
  return <svg className={`screen-keyboard-artwork${compact ? " compact" : ""}`} data-preview-theme={theme} data-preview-skin={skin} viewBox="0 0 1100 400" role={compact ? undefined : "img"} aria-hidden={compact || undefined} aria-label={compact ? undefined : "屏幕键盘完整布局预览"} style={{ fontFamily: option.monospaced ? "ui-monospace, SFMono-Regular, Consolas, monospace" : undefined }}>
    <defs>
      <Pattern id={patternId} pattern={option.pattern} accent={palette.accent} />
      {option.shadowOpacity > 0 && <filter id={shadowId} x="-20%" y="-20%" width="140%" height="150%"><feDropShadow dx="0" dy={option.shadowOffset} stdDeviation={option.shadowRadius} floodOpacity={option.shadowOpacity} /></filter>}
    </defs>
    <rect width="1100" height="400" rx="8" fill={palette.background} />
    {option.pattern !== 0 && <rect width="1100" height="400" rx="8" fill={`url(#${patternId})`} />}
    <text x="10" y="14" dominantBaseline="middle" fontSize="12" fill={palette.accent}>Touch keyboard</text>
    <path d="M1075 9l10 10m0-10l-10 10" fill="none" stroke={palette.foreground} strokeWidth="2" />
    {rows.map((row, rowIndex) => {
      const available = 1100 - 14 - 4 * (row.length - 1);
      const total = row.reduce((sum, item) => sum + item.weight, 0);
      let x = 7;
      const y = 28 + rowIndex * (height + 4);
      return <g data-keyboard-row={rowIndex} key={rowIndex}>{row.map((item, index) => {
        const width = available * item.weight / total;
        const left = x;
        x += width + 4;
        const action = actionLabels.has(item.label);
        return <g data-keyboard-key={item.label} key={index} filter={option.shadowOpacity > 0 ? `url(#${shadowId})` : undefined}>
          <rect x={left} y={y} width={width} height={height} rx={option.cornerRadius} fill={action ? palette.action : palette.key} stroke={option.borderWidth ? palette.accent : "none"} strokeOpacity={skin === "midnight" ? .65 : .28} strokeWidth={option.borderWidth} />
          <text x={left + width / 2} y={y + height / 2} textAnchor="middle" dominantBaseline="middle" fontSize={item.label.length === 1 ? 15 : 12} fill={action ? "#fff" : palette.foreground}>{item.label}</text>
        </g>;
      })}</g>;
    })}
  </svg>;
}
