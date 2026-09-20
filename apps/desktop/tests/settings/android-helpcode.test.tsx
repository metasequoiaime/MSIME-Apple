// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { SettingsPage, type Snapshot } from "@msime/ui";

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

const initial: Snapshot = {
  format_version: 1,
  revision: 7,
  preferences: {
    scheme: "quanpin",
    shuangpin_profile: "xiaohe",
    candidate_page_size: 5,
    learning: true,
    chinese_punctuation: true,
    quanpin_helpcode: { enabled: true, schema: "ziranma", show_in_candidate_window: false },
    shuangpin_helpcode: { enabled: true, schema: "lantian", show_in_candidate_window: true },
  },
};

function renderSettings(platform: string, save = vi.fn().mockResolvedValue(undefined)) {
  render(
    <SettingsPage
      client={{
        load: vi.fn().mockResolvedValue(initial),
        save,
        host: { platform } as never,
        home: { openKeyboard: vi.fn(), openSystemKeyboardSettings: vi.fn() },
      }}
    />,
  );
  return save;
}

async function moreSettings() {
  await screen.findByRole("button", { name: "保存设置" });
  const primary = screen.getByRole("navigation", { name: "主要功能" });
  return within(primary).getByRole("combobox", { name: "更多设置" }) as HTMLSelectElement;
}

// The Android keyboard sends helper codes -- Shift during a quanpin or shuangpin
// composition -- and the Engine reads the schema from these preferences, so the
// page has to be reachable there.
test("Android reaches the helper-code page from 更多设置", async () => {
  renderSettings("android");

  const more = await moreSettings();
  expect(Array.from(more.options).map((option) => option.text)).toContain("辅助码");

  fireEvent.change(more, { target: { value: "helpcode" } });
  expect(screen.getByRole("heading", { name: "辅助码" })).toBeTruthy();
  expect(screen.getByText(/按 Shift 再输入的字母作为辅助码/)).toBeTruthy();
});

test("Android saves a helper-code schema into shared preferences", async () => {
  const save = renderSettings("android");

  const more = await moreSettings();
  fireEvent.change(more, { target: { value: "helpcode" } });
  const schema = screen.getByRole("combobox", { name: /全拼辅助码方案/ }) as HTMLSelectElement;
  expect(schema.value).toBe("ziranma");
  fireEvent.change(schema, { target: { value: "xiaohe" } });

  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await waitFor(() =>
    expect(save).toHaveBeenCalledWith(
      7,
      expect.objectContaining({
        quanpin_helpcode: expect.objectContaining({ schema: "xiaohe" }),
      }),
    ),
  );
});

// A touch host has a candidate row, not a candidate window.
test("mobile names the candidate row rather than a window", async () => {
  renderSettings("android");

  const more = await moreSettings();
  fireEvent.change(more, { target: { value: "helpcode" } });
  expect(screen.getAllByLabelText("在候选栏显示辅助码").length).toBe(2);
  expect(screen.queryByLabelText("在候选窗口显示辅助码")).toBeNull();
});

// The Apple keyboard extension has no helper-code input at all.
test("iOS keeps the helper-code page hidden", async () => {
  renderSettings("ios");

  const more = await moreSettings();
  expect(Array.from(more.options).map((option) => option.text)).not.toContain("辅助码");
});

test("the desktop sidebar keeps the helper-code page and its window wording", async () => {
  renderSettings("windows");

  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "辅助码" }));
  expect(screen.getAllByLabelText("在候选窗口显示辅助码").length).toBe(2);
});

// HarmonyOS ships the same helper-code input: its ChineseHelpcodePolicy is the Android one,
// ported, and the session calls it on every shifted key during a quanpin or shuangpin
// composition. The page was hidden there anyway, which left a shipping feature with no way to
// pick a schema or turn it off — the state this file's Android tests exist to prevent.
test("HarmonyOS reaches the helper-code page from 更多设置", async () => {
  renderSettings("harmony");

  const more = await moreSettings();
  expect(Array.from(more.options).map((option) => option.text)).toContain("辅助码");

  fireEvent.change(more, { target: { value: "helpcode" } });
  expect(screen.getByRole("heading", { name: "辅助码" })).toBeTruthy();
});

test("HarmonyOS saves a helper-code schema into shared preferences", async () => {
  const save = renderSettings("harmony");

  const more = await moreSettings();
  fireEvent.change(more, { target: { value: "helpcode" } });
  const schema = screen.getByRole("combobox", { name: /全拼辅助码方案/ }) as HTMLSelectElement;
  expect(schema.value).toBe("ziranma");
  fireEvent.change(schema, { target: { value: "xiaohe" } });

  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await waitFor(() =>
    expect(save).toHaveBeenCalledWith(
      7,
      expect.objectContaining({
        quanpin_helpcode: expect.objectContaining({ schema: "xiaohe" }),
      }),
    ),
  );
});

// The gesture is the host's, not the platform's: Windows appends a helper code to a finished
// spelling and needs none, while the hosts running the ported ChineseHelpcodePolicy mark it with
// Shift. HarmonyOS reached the page before it could read this sentence.
test("the Shift explanation follows the capability, not the platform name", async () => {
  render(
    <SettingsPage
      client={{
        load: vi.fn().mockResolvedValue(initial),
        save: vi.fn(),
        host: { platform: "harmony", helpcode_shift_entry: true } as never,
        home: { openKeyboard: vi.fn(), openSystemKeyboardSettings: vi.fn() },
      }}
    />,
  );
  const more = await moreSettings();
  fireEvent.change(more, { target: { value: "helpcode" } });
  expect(screen.getByText(/按 Shift\s*再输入的字母作为辅助码/)).toBeTruthy();
});

test("a host that appends helper codes is not told to hold Shift", async () => {
  render(
    <SettingsPage
      client={{
        load: vi.fn().mockResolvedValue(initial),
        save: vi.fn(),
        host: { platform: "windows", helpcode_shift_entry: false } as never,
      }}
    />,
  );
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "辅助码" }));
  expect(screen.queryByText(/按 Shift\s*再输入的字母作为辅助码/)).toBeNull();
});
