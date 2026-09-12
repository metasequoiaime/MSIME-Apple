// Layout/palette reference: MSIME-Windows 04a8df56f86312474a069f4335a1b58da7afaa9e,
// server/src/keyboard-panel/KeyboardPanel.cpp (GPL-3.0). No input actions.
const key = (label: string, weight = 1) => ({ label, weight });
const letters = (text: string) => [...text].map(label => key(label));
const rows = [
  [...letters("`1234567890-="), key("Backspace", 1.9)],
  [key("Tab", 1.5), ...letters("qwertyuiop[]"), key("\\", 1.4)],
  [key("Caps Lock", 1.85), ...letters("asdfghjkl;'"), key("Enter", 2)],
  [key("Shift", 2.35), ...letters("zxcvbnm,./"), key("Shift", 2.15)],
  [key("Ctrl", 1.25), key("Win", 1.25), key("Alt", 1.25), key("Space", 6.7), key("Alt", 1.25), key("Win", 1.25), key("Del", 1.25), key("Ctrl", 1.25)],
];

export function ScreenKeyboardPreview({ theme }: { theme: "dark" | "light" }) {
  const height = (400 - 28 - 7 - 4 * 4) / 5;
  return <svg className="screen-keyboard-artwork" data-preview-theme={theme} viewBox="0 0 1100 400" role="img" aria-label="屏幕键盘完整布局预览">
    <rect className="keyboard-preview-background" width="1100" height="400" rx="8" />
    <text className="keyboard-preview-heading" x="10" y="14" dominantBaseline="middle" fontSize="12">Touch keyboard</text>
    <path className="keyboard-preview-close" d="M1075 9l10 10m0-10l-10 10" fill="none" strokeWidth="2" />
    {rows.map((row, rowIndex) => {
      const available = 1100 - 14 - 4 * (row.length - 1);
      const total = row.reduce((sum, item) => sum + item.weight, 0);
      let x = 7;
      const y = 28 + rowIndex * (height + 4);
      return <g data-keyboard-row={rowIndex} key={rowIndex}>{row.map((item, index) => {
        const width = available * item.weight / total;
        const left = x;
        x += width + 4;
        return <g data-keyboard-key={item.label} key={index}>
          <rect className="keyboard-preview-key" x={left} y={y} width={width} height={height} rx="5" />
          <text className="keyboard-preview-label" x={left + width / 2} y={y + height / 2} textAnchor="middle" dominantBaseline="middle" fontSize={item.label.length === 1 ? 15 : 12}>{item.label}</text>
        </g>;
      })}</g>;
    })}
  </svg>;
}
