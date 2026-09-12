import type { CSSProperties } from "react";

export type CandidateFontPreferences = { candidate_font_family?: string; candidate_fallback_fonts?: string[] };
export function validFontFamily(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && new TextEncoder().encode(value).length <= 128;
}
export function validCandidateFonts(value: CandidateFontPreferences): boolean {
  return validFontFamily(value.candidate_font_family ?? "Segoe UI") &&
    (value.candidate_fallback_fonts?.length ?? 0) <= 32 && (value.candidate_fallback_fonts ?? []).every(validFontFamily);
}
export function quoteFontFamily(value: string): string {
  return '"' + value.replace(/["\\\x00-\x1f\x7f]/g, char => "\\" + char.charCodeAt(0).toString(16) + " ") + '"';
}
export function candidateFamilyStyle(value: CandidateFontPreferences): CSSProperties {
  const primary = validFontFamily(value.candidate_font_family) ? value.candidate_font_family : "Segoe UI";
  const families = [primary, ...(value.candidate_fallback_fonts ?? []).slice(0, 32).filter(validFontFamily)];
  return { "--appearance-font-family": families.map(quoteFontFamily).join(", ") + ", sans-serif" } as CSSProperties;
}
