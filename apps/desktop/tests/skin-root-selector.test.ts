import { expect, test } from "vitest";
import { scopeRootSelector } from "../../../packages/ui/src/skin-root-selector";

test.each([
  [":root", ":scope"],
  [":ROOT.theme-light > .sample", ":scope.theme-light > .sample"],
  [":is(:root, .sample):not(:root:hover)", ":is(:scope, .sample):not(:scope:hover)"],
  ['[data-label=":root"] :root', '[data-label=":root"] :scope'],
  ["[data-label=':root'] :root", "[data-label=':root'] :scope"],
  ['[data-label="escaped \\" :root"] :root', '[data-label="escaped \\" :root"] :scope'],
  [".literal\\:root :root", ".literal\\:root :scope"],
  [".literal\\3a root :root", ".literal\\3a root :scope"],
  ["/* :root */ :root", "/* :root */ :scope"],
  [":root-other, :rooted, :root_foo, :root中", ":root-other, :rooted, :root_foo, :root中"],
])("only rewrites the root pseudo-class in %s", (selector, expected) => {
  expect(scopeRootSelector(selector)).toBe(expected);
});
