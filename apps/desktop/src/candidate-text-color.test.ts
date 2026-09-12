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
