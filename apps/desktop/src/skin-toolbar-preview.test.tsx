// @vitest-environment jsdom
import { afterEach, expect, test } from "vitest";
import { cleanup, render } from "@testing-library/react";
import { SkinToolbarPreview } from "../../../packages/ui/src/skin-toolbar-preview";
import css from "../../../packages/ui/src/skin-toolbar-preview.css?raw";

afterEach(cleanup);

test("toolbar preview contains upstream static icons without scripts, IDs or host actions", () => {
  const mounted = render(<SkinToolbarPreview />);
  const preview = mounted.container.querySelector(".ftb-preview-host")!;
  expect(preview.getAttribute("aria-hidden")).toBe("true");
  expect(preview.querySelectorAll(".status-bar")).toHaveLength(1);
  expect(preview.querySelector(".drag-handle")).not.toBeNull();
  expect(preview.querySelector(".divider")).not.toBeNull();
  expect(Array.from(preview.querySelectorAll("[data-toolbar-item]"), node => node.getAttribute("data-toolbar-item")))
    .toEqual(["language", "fullwidth", "punctuation", "character_set", "emoji", "screen_keyboard", "settings"]);
  expect(preview.querySelectorAll("[data-toolbar-item=fullwidth] .icon")).toHaveLength(1);
  expect(preview.querySelectorAll("[data-toolbar-item=punctuation] .icon")).toHaveLength(1);
  expect(preview.querySelector('[title="英文"]')).toBeNull();
  expect(preview.querySelectorAll("script,iframe,object,embed,link,[id],button,a,input")).toHaveLength(0);
  for (const node of Array.from(preview.querySelectorAll("*"))) {
    for (const attribute of Array.from(node.attributes))
      expect(attribute.name).not.toMatch(/^(on|src$|href$|tabindex$)/i);
  }
});

test.each([
  ["fluent", "dark", "rgb(26, 26, 26)"], ["fluent", "light", "rgb(255, 255, 255)"],
  ["wechat", "dark", "rgb(21, 21, 21)"], ["wechat", "light", "rgb(247, 247, 247)"],
  ["graphite", "dark", "rgb(28, 31, 35)"], ["graphite", "light", "rgb(251, 251, 252)"],
  ["willow_green", "dark", "rgb(45, 47, 46)"], ["willow_green", "light", "rgb(244, 245, 243)"],
])("%s/%s toolbar uses the upstream palette", (skin, appearance, surface) => {
  const mounted = render(<><style>{css}</style><div className={`skin-card-preview skin-${skin}`} data-preview-theme={appearance}><SkinToolbarPreview /></div></>);
  expect(getComputedStyle(mounted.container.querySelector(".status-bar")!).backgroundColor).toBe(surface);
  expect(getComputedStyle(mounted.container.querySelector(".ftb-preview-host")!).pointerEvents).toBe("none");
  expect(getComputedStyle(mounted.container.querySelector(".icon svg")!).filter).toBe(appearance === "light" ? "invert(1)" : "none");
});
