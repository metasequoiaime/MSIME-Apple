import { expect, test } from "vitest";
import { candidateFamilyStyle, quoteFontFamily, validCandidateFonts, validFontFamily } from "../../../packages/ui/src/candidate-font-family";

test("font names preserve Unicode and enforce UTF-8 and list bounds", () => {
  expect(validFontFamily("字".repeat(42) + "ab")).toBe(true);
  for (const value of ["", "字".repeat(43), "a".repeat(129), undefined, null]) expect(validFontFamily(value)).toBe(false);
  expect(validCandidateFonts({ candidate_fallback_fonts: Array(32).fill("示例字体") })).toBe(true);
  expect(validCandidateFonts({ candidate_fallback_fonts: Array(33).fill("示例字体") })).toBe(false);
  expect(validCandidateFonts({})).toBe(true);
});
test("font families are quoted literals, preserving fallback order", () => {
  expect(quoteFontFamily('a"\\\n')).toBe('"a\\22 \\5c \\a "');
  expect(candidateFamilyStyle({ candidate_font_family: "主字体", candidate_fallback_fonts: ["示例一", "示例二"] })).toEqual({
    "--appearance-font-family": '"主字体", "示例一", "示例二", sans-serif',
  });
});
