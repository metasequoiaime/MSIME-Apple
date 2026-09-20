// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, render, screen, within } from "@testing-library/react";
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

function renderSettings(platform: string) {
  render(
    <SettingsPage
      client={{
        load: vi.fn().mockResolvedValue(initial),
        save: vi.fn(),
        host: { platform } as never,
        openSystemKeyboardSettings: vi.fn(),
        home: { openKeyboard: vi.fn(), openSystemKeyboardSettings: vi.fn() },
      }}
    />,
  );
}

async function handwritingPage() {
  await screen.findByRole("button", { name: "保存设置" });
  const primary = screen.getByRole("navigation", { name: "主要功能" });
  const more = within(primary).getByRole("combobox", { name: "更多设置" }) as HTMLSelectElement;
  const { fireEvent } = await import("@testing-library/react");
  fireEvent.change(more, { target: { value: "handwriting" } });
  return screen.getByRole("group", { name: "手写识别板" });
}

// HarmonyOS reaches handwriting by switching the keyboard's input scheme, the way the other
// keyboard hosts do. It fell into the desktop branch instead, which offers a button wired to
// client.openHandwriting — a settings window cannot raise a keyboard extension's panel, so that
// host never provides it and the button was permanently disabled with nothing to explain it.
test("HarmonyOS is told how to reach handwriting instead of being offered a dead button", async () => {
  renderSettings("harmony");
  const page = await handwritingPage();

  expect(within(page).getByText("HarmonyOS 键盘手写")).toBeTruthy();
  expect(within(page).getByText(/方案选择器/)).toBeTruthy();
  expect(within(page).queryByRole("button", { name: "打开" })).toBeNull();
});

test("the 2in1 route to the scheme picker is spelled out", async () => {
  // A 2in1 draws a candidate window with no key faces, so the picker is not where a phone user
  // would look for it. Saying "switch the scheme" without saying where would be advice nobody
  // could follow on that form factor.
  renderSettings("harmony");
  const page = await handwritingPage();
  expect(within(page).getByText(/屏幕键盘/)).toBeTruthy();
});

test("a desktop host still gets the launch button", async () => {
  // The branch this adds must not take the desktop path with it: Windows and Linux do open a
  // handwriting panel from the settings window.
  renderSettings("windows");
  const { fireEvent } = await import("@testing-library/react");
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "手写识别板" }));
  const page = screen.getByRole("group", { name: "手写识别板" });
  expect(within(page).getByText("打开手写识别板")).toBeTruthy();
});
