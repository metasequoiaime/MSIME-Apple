// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { SettingsPage, type Snapshot } from "@msime/ui";
import css from "../../../../packages/ui/src/styles.css?raw";

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  window.history.replaceState({}, "");
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

function renderSettings(platform: string, host: Record<string, unknown> = {}) {
  render(
    <SettingsPage
      client={{
        load: vi.fn().mockResolvedValue(initial),
        save: vi.fn().mockResolvedValue(undefined),
        host: { platform, ...host } as never,
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

test("Harmony settings follow the actual phone or 2-in-1 form factor", async () => {
  renderSettings("harmony", { mobile_settings: true });
  await screen.findByRole("button", { name: "保存设置" });
  expect(screen.getByRole("navigation", { name: "主要功能" })).toBeTruthy();
  cleanup();

  renderSettings("harmony", { mobile_settings: false });
  await screen.findByRole("button", { name: "保存设置" });
  expect(screen.queryByRole("navigation", { name: "主要功能" })).toBeNull();
  expect(screen.getByRole("navigation", { name: "设置分类" })).toBeTruthy();
  const preview = document.querySelector(".screen-keyboard-artwork");
  const keys = Array.from(preview!.querySelectorAll("[data-keyboard-key]")).map((key) =>
    key.getAttribute("data-keyboard-key"),
  );
  expect(keys).toContain("Caps Lock");
  expect(keys).toContain("Tab");
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

// A phone opens on the headline and carries no brand mark: the source shows none there, and the app
// is already the thing being looked at. Desktop keeps it, and there the path still has to resolve —
// home-page.tsx sits one directory deeper than index.tsx, and the same relative path written in both
// left a broken image on this very screen once already.
//
// Queried through the landmark rather than a class, because the home page's styling is Tailwind
// utilities: a class name there is a styling detail with no reason to stay put.
test("the home hero image is a desktop-only mark, and resolves", async () => {
  renderSettings("android");
  await screen.findByRole("button", { name: "保存设置" });

  const home = screen.getByRole("region", { name: "首页" });
  expect(home.querySelector("header img")).toBeNull();

  cleanup();
  renderSettings("windows");
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "首页" }));
  const desktopHero = screen
    .getByRole("region", { name: "首页" })
    .querySelector("header img") as HTMLImageElement;
  expect(desktopHero).toBeTruthy();
  expect(desktopHero.src).not.toContain("/keyboard/assets/");
  // Either form is a resolved asset: a path to the file, or the file itself once it is small enough
  // for the bundler to inline. What this guards against is a path that resolves to nothing.
  expect(
    desktopHero.src.includes("msime.svg") || desktopHero.src.startsWith("data:image/svg+xml"),
  ).toBe(true);
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
  // A capsule floating clear of the edges, the way the source draws it, rather than a full-width
  // strip ruled off with a top hairline. The bottom inset still clears the gesture area.
  expect(utilities).toContain("max-phone:rounded-[26px]");
  expect(utilities).toContain("max-phone:mb-[calc(0.5rem+env(safe-area-inset-bottom,0px))]");
});

// The breakpoint the phone layout keys on has to keep meaning what the stylesheet used to say, or
// every `max-phone:` utility silently moves. Tailwind derives `max-*` as `width < value`, so 601px is
// the rendering of `@media (max-width: 600px)`.
test("the phone breakpoint is the 600px one the layout was written for", () => {
  expect(css).toContain("--breakpoint-phone: 601px");
});

// A phone has no Ctrl, no Alt and no Win key, and no panel window to theme. Both blocks were gated
// on `!androidPlatform` — a platform name, not a capability — so they reached every host that was
// not Android, and HarmonyOS and iOS were both being shown `Ctrl+F9 切换语音`. Asserted for the two
// hosts that were wrong and for one that is right, because a gate that hides it everywhere passes
// the first half of this on its own.
test("a phone is not offered the desktop's modifier-chord voice shortcuts", async () => {
  for (const platform of ["harmony", "ios"]) {
    renderSettings(platform);
    await screen.findByRole("button", { name: "保存设置" });
    fireEvent.click(screen.getByRole("button", { name: /全部设置/ }));
    const list = screen.getByRole("region", { name: "全部设置" });
    const row = [...list.querySelectorAll("button")].find(
      (item) => item.querySelector("strong")?.textContent === "语音输入",
    );
    if (!row) throw new Error(`no 语音输入 row on ${platform}`);
    fireEvent.click(row);
    expect(screen.queryByText("语音快捷键")).toBeNull();
    expect(screen.queryByText("语音输入弹出条主题")).toBeNull();
    cleanup();
    window.history.replaceState({}, "");
  }

  renderSettings("windows");
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "语音输入" }));
  expect(screen.getByText("语音快捷键")).toBeTruthy();
});
