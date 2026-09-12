import { expect, test } from "vitest";
import { candidateFontSize, candidateFontSizes, candidateFontStyle } from "../../../packages/ui/src/candidate-font-size";

test("font controls expose every shared 12–32 integer", () => {
  expect(candidateFontSizes).toEqual(Array.from({ length: 21 }, (_, i) => i + 12));
  for (const size of candidateFontSizes) expect(candidateFontSize(size)).toBe(size);
});
test("invalid or missing sizes use core default without emitting unsafe CSS", () => {
  for (const value of [undefined, null, "20", "20px;color:red", NaN, Infinity, -1, 11, 33, 16.5]) expect(candidateFontSize(value)).toBe(16);
  expect(candidateFontStyle({})).toEqual({ "--appearance-font-size": "16px", "--appearance-preedit-font-size": "16px" });
  expect(candidateFontStyle({ candidate_font_size: 12, candidate_preedit_font_size: 32 })).toEqual({ "--appearance-font-size": "12px", "--appearance-preedit-font-size": "32px" });
});
