// @vitest-environment jsdom
import { expect, test } from "vitest";
import styles from "../../../packages/ui/src/styles.css?raw";
import variables from "../../../packages/ui/src/upstream/variables.css?raw";

// Inspect parsed CSS declarations: jsdom does not resolve custom properties or
// simulate native WebView hover/layout. These are stylesheet contract tests.
function declarations(source: string, selector: string): CSSStyleDeclaration {
  const sheet = new CSSStyleSheet();
  sheet.replaceSync(source);
  expect(source).toContain("--titlebar");
  const matches = Array.from(sheet.cssRules).filter(
    (rule): rule is CSSStyleRule => rule.type === CSSRule.STYLE_RULE &&
      (rule as CSSStyleRule).selectorText.replace(/\s+/g, " ") === selector.replace(/\s+/g, " "),
  );
  expect(matches.length).toBeGreaterThan(0);
  return matches[matches.length - 1].style;
}

test("titlebar uses shared theme colors and upstream control dimensions", () => {
  const titlebar = declarations(styles, ".window-titlebar");
  expect(titlebar.getPropertyValue("background")).toBe("var(--chrome-bg)");
  expect(titlebar.getPropertyValue("color")).toBe("var(--text-color)");
  expect(titlebar.getPropertyValue("height")).toBe("var(--titlebar-height)");
  const button = declarations(styles, ".window-controls button");
  expect(button.getPropertyValue("height")).toBe("var(--titlebar-height)");
  expect(button.getPropertyValue("width")).toBe("42px");
});

test("normal button interaction colors follow both themes", () => {
  for (const state of ["hover", "active"]) {
    expect(declarations(styles, `.window-controls button:${state}`).getPropertyValue("background"))
      .toBe(`var(--titlebar-btn-${state})`);
  }
  const dark = declarations(variables, ':root,\nhtml[data-theme="dark"]');
  const light = declarations(variables, 'html[data-theme="light"]');
  for (const token of ["--chrome-bg", "--text-color", "--titlebar-btn-hover", "--titlebar-btn-active"]) {
    expect(dark.getPropertyValue(token)).not.toBe("");
    expect(light.getPropertyValue(token)).not.toBe("");
    expect(dark.getPropertyValue(token)).not.toBe(light.getPropertyValue(token));
  }
});

test("close interaction and keyboard focus keep dedicated styles", () => {
  expect(declarations(styles, ".window-controls .window-close:hover").getPropertyValue("background")).toBe("rgb(196, 43, 28)");
  expect(declarations(styles, ".window-controls .window-close:active").getPropertyValue("background")).toBe("rgb(167, 34, 22)");
  expect(declarations(styles, ".window-controls button:focus-visible").getPropertyValue("outline-offset")).toBe("-3px");
});

test("window SVGs retain upstream sizing and light-theme contrast", () => {
  const icon = declarations(styles, ".window-icon");
  expect(icon.getPropertyValue("width")).toBe("9px");
  expect(icon.getPropertyValue("height")).toBe("10px");
  expect(icon.getPropertyValue("object-fit")).toBe("contain");
  expect(icon.getPropertyValue("pointer-events")).toBe("none");
  expect(declarations(styles, 'html[data-theme="light"] .window-icon').getPropertyValue("filter"))
    .toBe("invert(1) brightness(0.2)");
  expect(declarations(styles, 'html[data-theme="light"] .window-close:hover .window-icon, html[data-theme="light"] .window-close:active .window-icon')
    .getPropertyValue("filter")).toBe("none");
});
