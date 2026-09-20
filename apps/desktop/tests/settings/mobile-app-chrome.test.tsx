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

  const hero = document.querySelector(".home-intro img") as HTMLImageElement;
  expect(hero).toBeTruthy();
  expect(hero.src).not.toContain("/keyboard/assets/");
  expect(hero.src).toContain("msime.svg");
});

// A phone's primary navigation has to stay reachable by thumb. The DOM keeps it ahead of the content
// so assistive technology and keyboard focus still meet it first; only the stylesheet moves it down,
// which is why the placement is asserted there rather than through a computed style jsdom never
// resolves.
test("the phone navigation leads the content in the DOM", async () => {
  renderSettings("android");
  await screen.findByRole("button", { name: "保存设置" });

  const primary = screen.getByRole("navigation", { name: "主要功能" });
  expect(within(primary).getByRole("button", { name: "键盘" })).toBeTruthy();
  const body = primary.parentElement!;
  const content = body.querySelector("#settings-content")!;
  expect(body.classList.contains("settings-body")).toBe(true);
  expect(primary.compareDocumentPosition(content) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
});

test("the stylesheet seats the phone navigation at the bottom edge", () => {
  const mobile = css.slice(css.indexOf("@media (max-width: 600px)"));
  const nav = mobile.slice(mobile.indexOf(".mobile-primary-nav {"));
  const block = nav.slice(0, nav.indexOf("}"));

  expect(block).toContain("order: 2");
  expect(block).toContain("border-top:");
  expect(block).not.toContain("border-bottom:");
  expect(block).toContain("env(safe-area-inset-bottom");
});
