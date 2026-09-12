import type { CSSProperties } from "react";

// Shared preferences and pinned Windows appearance controls both use 12–32.
export const candidateFontSizes = Array.from({ length: 21 }, (_, index) => index + 12);
export function candidateFontSize(value: unknown): number {
  return typeof value === "number" && Number.isInteger(value) && value >= 12 && value <= 32 ? value : 16;
}
export function candidateFontStyle(preferences: { candidate_font_size?: number; candidate_preedit_font_size?: number }): CSSProperties {
  return {
    "--appearance-font-size": `${candidateFontSize(preferences.candidate_font_size)}px`,
    "--appearance-preedit-font-size": `${candidateFontSize(preferences.candidate_preedit_font_size)}px`,
  } as CSSProperties;
}
