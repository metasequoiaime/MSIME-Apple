import type { CSSProperties } from "react";

export function candidateTextColor(value: unknown): string | null {
  return typeof value === "string" && /^#[0-9a-f]{6}$/i.test(value) ? value.toLowerCase() : null;
}
// Match pinned appearance.ts: text colour plus translucent candidate numbers.
// Omitting the properties restores the selected skin's original variables.
export function candidateTextStyle(value: unknown, numberValue?: unknown, accentValue?: unknown): CSSProperties {
  const color = candidateTextColor(value);
  const numberColor = candidateTextColor(numberValue) ?? (color ? `${color}9d` : null);
  const accent = candidateTextColor(accentValue);
  return color || numberColor || accent ? { ...(color ? { "--cand-text": color } : {}), ...(numberColor ? { "--cand-num": numberColor } : {}), ...(accent ? { "--cand-accent": accent } : {}) } as CSSProperties : {};
}
