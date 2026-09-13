// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { HomePage, SettingsPage, type Snapshot } from "@msime/ui";

afterEach(cleanup);

const initial: Snapshot = {
  format_version: 1,
  revision: 7,
  preferences: {
    scheme: "shuangpin",
    shuangpin_profile: "xiaohe",
    touch_keyboard_skin: "ocean",
    touch_keyboard_schemes: { enabled: ["xiaohe"], selected: "xiaohe" },
    candidate_page_size: 5,
    learning: true,
    chinese_punctuation: true,
  },
};

test("renders the keyboard home surface with the current skin and scheme", () => {
  render(<HomePage preferences={initial.preferences} onOpenPage={vi.fn()} />);

  expect(screen.getByRole("region", { name: "首页" })).toBeTruthy();
  expect(screen.getByText("我的键盘")).toBeTruthy();
  expect(screen.getByText("海盐蓝 · 小鹤双拼")).toBeTruthy();
  expect(screen.getByRole("img", { name: "屏幕键盘完整布局预览" })).toBeTruthy();
  expect(screen.getByText("高情商回复")).toBeTruthy();
});

test("routes home shortcuts to the shared settings pages", () => {
  const onOpenPage = vi.fn();
  render(<HomePage preferences={initial.preferences} onOpenPage={onOpenPage} />);

  fireEvent.click(screen.getByRole("button", { name: /皮肤/ }));
  fireEvent.click(screen.getByRole("button", { name: /输入方案/ }));
  fireEvent.click(screen.getByRole("button", { name: /按键/ }));
  fireEvent.click(screen.getByRole("button", { name: /键盘设置/ }));
  fireEvent.click(screen.getByRole("button", { name: /高情商回复/ }));

  expect(onOpenPage.mock.calls).toEqual([["skin"], ["input"], ["screen-keyboard"], ["appearance"], ["input"]]);
});

test("selects thoughtful reply from the home feature entry", () => {
  const onOpenPage = vi.fn();
  const onSelectScheme = vi.fn();
  render(<HomePage preferences={initial.preferences} onOpenPage={onOpenPage} onSelectScheme={onSelectScheme} />);

  fireEvent.click(screen.getByRole("button", { name: /高情商回复/ }));

  expect(onSelectScheme).toHaveBeenCalledWith("thoughtful_reply");
  expect(onOpenPage).toHaveBeenCalledWith("input");
});

test("invokes Android keyboard and system input actions", () => {
  const actions = {
    openKeyboard: vi.fn().mockResolvedValue(undefined),
    openSystemKeyboardSettings: vi.fn().mockResolvedValue(undefined),
    showInputMethodPicker: vi.fn().mockResolvedValue(undefined),
  };
  render(<HomePage preferences={initial.preferences} actions={actions} onOpenPage={vi.fn()} />);

  fireEvent.click(screen.getByRole("button", { name: /试用键盘/ }));
  fireEvent.click(screen.getByRole("button", { name: "系统键盘设置" }));
  fireEvent.click(screen.getByRole("button", { name: "选择输入法" }));

  expect(actions.openKeyboard).toHaveBeenCalledOnce();
  expect(actions.openSystemKeyboardSettings).toHaveBeenCalledOnce();
  expect(actions.showInputMethodPicker).toHaveBeenCalledOnce();
});

test("opens Android on home and preserves the appearance fallback without home capability", async () => {
  render(<SettingsPage client={{ load: async () => initial, save: vi.fn(), home: {
    openKeyboard: vi.fn().mockResolvedValue(undefined),
  } }} />);
  await screen.findByRole("region", { name: "首页" });
  expect(screen.getByRole("button", { name: "首页" }).getAttribute("aria-current")).toBe("page");

  cleanup();
  render(<SettingsPage client={{ load: async () => initial, save: vi.fn() }} />);
  await screen.findByRole("button", { name: "保存设置" });
  expect(screen.getByRole("button", { name: "外观" }).getAttribute("aria-current")).toBe("page");
  expect(screen.queryByRole("region", { name: "首页" })).toBeNull();
});

test("enables and selects thoughtful reply when opened from Android home", async () => {
  render(<SettingsPage client={{ load: async () => initial, save: vi.fn(), touchKeyboardSchemes: true, home: {
    openKeyboard: vi.fn().mockResolvedValue(undefined),
  } }} />);
  await screen.findByRole("region", { name: "首页" });
  fireEvent.click(screen.getByRole("button", { name: /高情商回复/ }));

  expect(screen.getByRole("button", { name: "设为当前输入方案 高情商回复" }).getAttribute("aria-pressed")).toBe("true");
  expect((screen.getByRole("checkbox", { name: "显示输入方案 高情商回复" }) as HTMLInputElement).checked).toBe(true);
});
