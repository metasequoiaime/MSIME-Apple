// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";
import { SettingsPage, type Snapshot } from "@msime/ui";

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

async function openAppearance(platform: string) {
  render(
    <SettingsPage
      initialPage="appearance"
      client={{
        load: vi.fn().mockResolvedValue(initial),
        save: vi.fn(),
        host: { platform } as never,
        home: { openKeyboard: vi.fn(), openSystemKeyboardSettings: vi.fn() },
      }}
    />,
  );
  await screen.findByRole("heading", { name: "外观" });
}

// The Android keyboard resolves both of these against its own surface setting.
test("Android offers the emoji and handwriting panel themes", async () => {
  await openAppearance("android");

  expect(screen.getByLabelText("Emoji 面板主题")).toBeTruthy();
  expect(screen.getByLabelText("手写面板主题")).toBeTruthy();
});

// Only the native desktop menus read menu_theme; a touch host draws no menu it applies to.
test("mobile hosts do not offer a menu theme", async () => {
  await openAppearance("android");
  expect(screen.queryByLabelText("菜单主题")).toBeNull();

  cleanup();
  await openAppearance("ios");
  expect(screen.queryByLabelText("菜单主题")).toBeNull();
});

test("the desktop keeps the menu theme", async () => {
  await openAppearance("macos");

  expect(screen.getByLabelText("菜单主题")).toBeTruthy();
});
