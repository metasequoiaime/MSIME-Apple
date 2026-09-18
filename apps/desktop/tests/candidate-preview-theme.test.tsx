// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { act, cleanup, render } from "@testing-library/react";
import { AppearanceCandidatePreview } from "../../../packages/ui/src/appearance-candidate-preview";
import type { Preferences } from "@msime/ui";

afterEach(() => { cleanup(); vi.unstubAllGlobals(); });
const preferences: Preferences = { scheme: "quanpin", shuangpin_profile: "xiaohe", candidate_page_size: 6,
  learning: true, chinese_punctuation: true };

test("all builtins resolve candidate override before global, independently of settings", () => {
  const view = render(<AppearanceCandidatePreview preferences={preferences} />);
  const theme = () => view.container.querySelector(".appearance-candidate-preview")?.getAttribute("data-preview-theme");
  expect(theme()).toBe("dark");
  for (const skin of ["fluent", "wechat", "graphite", "willow_green"]) {
    for (const candidate_theme of ["follow", "light", "dark"] as const) {
      view.rerender(<AppearanceCandidatePreview preferences={{ ...preferences, candidate_skin: skin, theme: "light", settings_theme: "dark", candidate_theme }} />);
      expect(theme()).toBe(candidate_theme === "dark" ? "dark" : "light");
    }
  }
});

test("system changes update following previews and listeners are disposed on override/unmount", () => {
  let listener: (() => void) | undefined;
  const media = { matches: true, addEventListener: vi.fn((_event, callback) => { listener = callback; }),
    removeEventListener: vi.fn(() => { listener = undefined; }) };
  vi.stubGlobal("matchMedia", vi.fn(() => media));
  const view = render(<AppearanceCandidatePreview preferences={{ ...preferences, theme: "system" }} />);
  const theme = () => view.container.querySelector(".appearance-candidate-preview")?.getAttribute("data-preview-theme");
  expect(theme()).toBe("light");
  act(() => { media.matches = false; listener!(); });
  expect(theme()).toBe("dark");
  view.rerender(<AppearanceCandidatePreview preferences={{ ...preferences, theme: "system", candidate_theme: "light" }} />);
  expect(theme()).toBe("light");
  expect(media.removeEventListener).toHaveBeenCalledTimes(1);
  view.rerender(<AppearanceCandidatePreview preferences={{ ...preferences, theme: "system" }} />);
  expect(theme()).toBe("dark");
  view.unmount();
  expect(media.removeEventListener).toHaveBeenCalledTimes(2);
});

test("missing system API retains the upstream dark fallback", () => {
  vi.stubGlobal("matchMedia", undefined);
  const view = render(<AppearanceCandidatePreview preferences={{ ...preferences, theme: "system" }} />);
  expect(view.container.querySelector(".appearance-candidate-preview")?.getAttribute("data-preview-theme")).toBe("dark");
});
