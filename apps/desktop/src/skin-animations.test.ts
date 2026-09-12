// @vitest-environment jsdom
import { expect, test } from "vitest";
import { rewriteAnimationNames } from "../../../packages/ui/src/skin-animations";

// Full CSSOM serialization/escaping and playback use the Chromium regression.
const names = new Map([["pulse", "private-pulse"], ["spin", "private-spin"]]);
test("maps local animation names and keeps list positions", () => {
  expect(rewriteAnimationNames("pulse, none, spin", names)).toEqual({ value: "private-pulse, none, private-spin", partial: false });
});
test.each(["var(--motion)", "pulse,", "pulse, ", "pulse()", "inherit", "revert", "missing", ""])("disables unresolved animation names: %s", value => {
  expect(rewriteAnimationNames(value, names)).toEqual({ value: "none", partial: true });
});
test("does not bind unknown names to another stylesheet", () => {
  expect(rewriteAnimationNames("pulse, foreign, spin", names)).toEqual({ value: "private-pulse, none, private-spin", partial: true });
});
test("keeps reset keywords inert", () => {
  expect(rewriteAnimationNames("initial", names)).toEqual({ value: "none", partial: false });
  expect(rewriteAnimationNames("unset", names)).toEqual({ value: "none", partial: false });
});
