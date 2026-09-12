import { expect, test } from "vitest";
import { preserveAnimationShorthands } from "../../../packages/ui/src/animation-shorthand-source";

// Positive expansion needs browser shorthand CSSOM support; the Chromium
// regression verifies actual timing, ordering, priority and image preparation.
test.each([
  '.sample { color: red; }',
  '.sample { content: "animation:var(--not-a-declaration);"; }',
  '.sample { --tokens: { animation:var(--not-a-declaration); }; }',
  '/* animation:var(--comment); */ .sample {animation-name:var(--name)}',
])("does not rewrite opaque or unrelated source: %s", css => {
  expect(preserveAnimationShorthands(css)).toEqual({ css, partial: false });
});
test("malformed source is left to browser recovery and reports partial support", () => {
  const css = '.sample { animation:var(--motion);';
  expect(preserveAnimationShorthands(css)).toEqual({ css, partial: true });
});
test("oversized source is rejected before parsing", () => {
  expect(preserveAnimationShorthands(" ".repeat(16 * 1024 * 1024 + 1))).toEqual({ css: "", partial: true });
});
