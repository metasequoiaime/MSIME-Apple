// @vitest-environment jsdom
import { expect, test } from "vitest";
import variables from "../../../../packages/ui/src/upstream/variables.css?raw";
import * as settings from "../../../../packages/ui/src/settings/settings-style";

/*
 * The titlebar reproduces the upstream Windows one, and jsdom resolves neither custom properties nor
 * native hover, so these stay contract tests: they read the declaration the titlebar is built from
 * rather than a computed style. That source is now the utility strings rather than a stylesheet, so
 * the assertions read utilities -- the contract is the same, the place it is written moved.
 */
function utilities(value: string): string[] {
  return value.split(/\s+/).filter(Boolean);
}

function declarations(source: string, selector: string): CSSStyleDeclaration {
  const sheet = new CSSStyleSheet();
  sheet.replaceSync(source);
  const matches = Array.from(sheet.cssRules).filter(
    (rule): rule is CSSStyleRule =>
      rule.type === CSSRule.STYLE_RULE &&
      (rule as CSSStyleRule).selectorText.replace(/\s+/g, " ") === selector.replace(/\s+/g, " "),
  );
  expect(matches.length).toBeGreaterThan(0);
  return matches[matches.length - 1].style;
}

test("titlebar uses shared theme colors and upstream control dimensions", () => {
  const titlebar = utilities(settings.titlebar);
  expect(titlebar).toContain("bg-chrome");
  expect(titlebar).toContain("text-body");
  expect(titlebar).toContain("h-[var(--titlebar-height)]");

  const controls = utilities(settings.windowControls);
  expect(controls).toContain("[&>button]:h-[var(--titlebar-height)]");
  expect(controls).toContain("[&>button]:w-[42px]");
});

test("normal button interaction colors follow both themes", () => {
  const controls = utilities(settings.windowControls);
  expect(controls).toContain("[&>button:hover]:bg-[var(--titlebar-btn-hover)]");
  expect(controls).toContain("[&>button:active]:bg-[var(--titlebar-btn-active)]");

  // The tokens themselves still have to differ between the two palettes, or the hover would be
  // invisible in one of them.
  const dark = declarations(variables, ':root,\nhtml[data-theme="dark"]');
  const light = declarations(variables, 'html[data-theme="light"]');
  for (const token of [
    "--chrome-bg",
    "--text-color",
    "--titlebar-btn-hover",
    "--titlebar-btn-active",
  ]) {
    expect(dark.getPropertyValue(token)).not.toBe("");
    expect(light.getPropertyValue(token)).not.toBe("");
    expect(dark.getPropertyValue(token)).not.toBe(light.getPropertyValue(token));
  }
});

test("close interaction and keyboard focus keep dedicated styles", () => {
  const close = utilities(settings.windowClose);
  expect(close).toContain("hover:bg-[#c42b1c]!");
  expect(close).toContain("active:bg-[#a72216]!");
  expect(utilities(settings.windowControls)).toContain(
    "[&>button:focus-visible]:-outline-offset-[3px]",
  );
});

test("window SVGs retain upstream sizing and light-theme contrast", () => {
  const icon = utilities(settings.windowIcon);
  expect(icon).toContain("size-[9px]");
  expect(icon).toContain("h-2.5");
  expect(icon).toContain("object-contain");
  expect(icon).toContain("[pointer-events:none]");
  expect(icon).toContain("light-theme:invert");
  expect(icon).toContain("light-theme:brightness-[0.2]");

  // Close is the exception: it goes red on hover, so the white glyph must not invert there.
  const close = utilities(settings.windowClose);
  expect(close).toContain("light-theme:hover:[&_img]:[filter:none]");
  expect(close).toContain("light-theme:active:[&_img]:[filter:none]");
});
