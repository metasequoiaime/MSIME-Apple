import type { CSSProperties } from "react";

export function candidateTextColor(value: unknown): string | null {
  return typeof value === "string" && /^#[0-9a-f]{6}$/i.test(value) ? value.toLowerCase() : null;
}
// Match pinned appearance.ts: text colour plus translucent candidate numbers.
// Omitting the properties restores the selected skin's original variables.
export function candidateTextStyle(value: unknown): CSSProperties {
  const color = candidateTextColor(value);
  return color ? { "--cand-text": color, "--cand-num": `${color}9d` } as CSSProperties : {};
}
