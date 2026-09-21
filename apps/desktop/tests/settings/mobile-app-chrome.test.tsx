// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, render, screen, within } from "@testing-library/react";
import { SettingsPage, type Snapshot } from "@msime/ui";
import css from "../../../../packages/ui/src/styles.css?raw";

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

const initial: Snapshot = {
  format_version: 1,
  revision: 3,
  preferences: {
    scheme: "quanpin",
    shuangpin_profile: "xiaohe",
    candidate_page_size: 5,
    learning: true,
    chinese_punctuation: true,
  },
};

function renderSettings(platform: string) {
  render(
    <SettingsPage
      client={{
        load: vi.fn().mockResolvedValue(initial),
        save: vi.fn().mockResolvedValue(undefined),
        host: { platform } as never,
        home: { openKeyboard: vi.fn(), openSystemKeyboardSettings: vi.fn() },
        // Both window commands are present here because one Tauri binary serves every platform: the
        // app exposes them on a phone too, which is exactly how the titlebar reached Android.
        windowControl: vi.fn(),
        beginWindowDrag: vi.fn(),
      }}
    />,
  );
}

// The OS owns the frame on a phone. Minimise, maximise and close have nothing to act on there, and a
// drag handle above the content only steals a row of screen.
test("a phone host draws no window titlebar", async () => {
  renderSettings("android");
  await screen.findByRole("button", { name: "保存设置" });

  expect(screen.queryByRole("banner", { name: "窗口控制" })).toBeNull();
});

test("a desktop host keeps its window titlebar", async () => {
  renderSettings("windows");
  await screen.findByRole("button", { name: "保存设置" });

  expect(screen.getByRole("banner", { name: "窗口控制" })).toBeTruthy();
});

// The home card previews the keyboard the user will actually see. A phone has no number row, no Tab
// and no Win key, so the desktop artwork misdescribes every touch host.
test("a phone previews the touch keyboard, not the desktop one", async () => {
  renderSettings("android");
  await screen.findByRole("button", { name: "保存设置" });

  const preview = document.querySelector(".screen-keyboard-artwork");
  expect(preview).toBeTruthy();
  const keys = Array.from(preview!.querySelectorAll("[data-keyboard-key]")).map((key) =>
    key.getAttribute("data-keyboard-key"),
  );
  expect(keys).toContain("⇧");
  expect(keys).toContain("空格");
  expect(keys).not.toContain("Caps Lock");
  expect(keys).not.toContain("Win");
});

test("the desktop home card keeps the full keyboard", async () => {
  renderSettings("windows");
  await screen.findByRole("button", { name: "保存设置" });

  const preview = document.querySelector(".screen-keyboard-artwork");
  const keys = Array.from(preview!.querySelectorAll("[data-keyboard-key]")).map((key) =>
    key.getAttribute("data-keyboard-key"),
  );
  expect(keys).toContain("Caps Lock");
  expect(keys).toContain("Tab");
});

// The hero art is resolved relative to the module that asks for it, and home-page.tsx sits one
// directory deeper than index.tsx. The same relative path in both places left a broken image on the
// phone's first screen.
test("the home hero image resolves to a real asset", async () => {
  renderSettings("android");
  await screen.findByRole("button", { name: "保存设置" });

  // Queried through the landmark rather than a class, because the home page's styling is Tailwind
  // utilities: a class name there is a styling detail with no reason to stay put.
  const home = screen.getByRole("region", { name: "首页" });
  const hero = home.querySelector("header img") as HTMLImageElement;
  expect(hero).toBeTruthy();
  expect(hero.src).not.toContain("/keyboard/assets/");
  // Either form is a resolved asset: a path to the file, or the file itself once it is small enough
  // for the bundler to inline. What this guards against is a path that resolves to nothing.
  expect(hero.src.includes("msime.svg") || hero.src.startsWith("data:image/svg+xml")).toBe(true);
});

// A phone's primary navigation has to stay reachable by thumb, and it is a bottom tab bar on every
// touch host. The DOM deliberately keeps it ahead of the content so assistive technology and keyboard
// focus meet the navigation first; `order-2` is what seats it below. Both halves of that arrangement
// are asserted, because either one alone is wrong: the DOM order without the utility puts the bar back
// at the top, and the utility without the DOM order sends focus to the bottom of the page first.
test("the phone navigation leads the content but is seated below it", async () => {
  renderSettings("android");
  await screen.findByRole("button", { name: "保存设置" });

  const primary = screen.getByRole("navigation", { name: "主要功能" });
  expect(within(primary).getByRole("button", { name: "键盘" })).toBeTruthy();

  const body = primary.parentElement!;
  const content = body.querySelector("#settings-content")!;
  expect(primary.compareDocumentPosition(content) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();

  // jsdom loads the stylesheet but resolves no media query, so the utility is read off the element
  // rather than from a computed style. `max-phone` is the project's own 600px breakpoint.
  const utilities = primary.className.split(/\s+/);
  expect(utilities).toContain("max-phone:order-2");
  expect(utilities).toContain("max-phone:border-t");
  expect(utilities).toContain("max-phone:pb-[calc(0.5rem+env(safe-area-inset-bottom,0px))]");
  expect(utilities.some((name) => name.includes("border-b"))).toBe(false);
});

// The breakpoint the phone layout keys on has to keep meaning what the stylesheet used to say, or
// every `max-phone:` utility silently moves. Tailwind derives `max-*` as `width < value`, so 601px is
// the rendering of `@media (max-width: 600px)`.
test("the phone breakpoint is the 600px one the layout was written for", () => {
  expect(css).toContain("--breakpoint-phone: 601px");
});
