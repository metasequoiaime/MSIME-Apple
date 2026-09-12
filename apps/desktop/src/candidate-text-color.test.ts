import { expect, test } from "vitest";
import { candidateTextColor, candidateTextStyle } from "../../../packages/ui/src/candidate-text-color";

test("candidate colours match core hex format and upstream number alpha", () => {
  expect(candidateTextColor("#Ab12Ef")).toBe("#ab12ef");
  expect(candidateTextStyle("#Ab12Ef")).toEqual({ "--cand-text": "#ab12ef", "--cand-num": "#ab12ef9d" });
});
test("invalid colours cannot become preview declarations", () => {
  for (const value of [undefined, null, "", "auto", "red", "#123", "#12345678", "#123456; color:red", " #123456", "#12gg56", 123456]) {
    expect(candidateTextColor(value)).toBeNull();
    expect(candidateTextStyle(value)).toEqual({});
  }
});

test("appearance overrides map to independent skin variables", () => {
  expect(candidateTextStyle(undefined, "#112233", "#223344", "#334455", "#445566", "#556677", "#667788")).toEqual({
    "--cand-num": "#112233", "--cand-accent": "#223344", "--cand-selected": "#334455",
    "--cand-hover": "#445566", "--cand-bg": "#556677", "--cand-border": "#667788",
  });
  expect(candidateTextStyle("#112233", "#334455", "bad", "#445566", "#556677", "#667788", "#778899")).toEqual({
    "--cand-text": "#112233", "--cand-num": "#334455", "--cand-selected": "#445566",
    "--cand-hover": "#556677", "--cand-bg": "#667788", "--cand-border": "#778899",
  });
});
