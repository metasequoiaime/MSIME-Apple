// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { SettingsPage, type HostCapabilities, type SettingsClient, type Snapshot } from "@msime/ui";

afterEach(cleanup);

const initial: Snapshot = {
  format_version: 1,
  revision: 7,
  preferences: { scheme: "quanpin", shuangpin_profile: "xiaohe", candidate_page_size: 5, learning: true, chinese_punctuation: true },
};

function capabilities(overrides: Partial<HostCapabilities> = {}): HostCapabilities {
  return {
    platform: "windows",
    restart_input_method: true,
    panel_windows: true,
    ime_mode_scope: false,
    typing_statistics: true,
    fuzzy_pinyin: false,
    system_fonts: true,
    window_chrome: true,
    floating_toolbar: true,
    floating_toolbar_appearance: true,
    mode_switch_shortcuts: false,
    panel_shortcuts: false,
    voice_capture_devices: false,
    candidate_font_controls: true,
    candidate_row_colors: true,
    candidate_selection_appearance: true,
    ...overrides,
  };
}

function mount(client: Partial<SettingsClient>) {
  return render(<SettingsPage client={{ load: async () => initial, save: vi.fn(), ...client }} />);
}

test("host capabilities decide platform-specific settings instead of the user agent", async () => {
  // A Windows host that tracks session-wide mode gets the control; the gate is
  // the capability, not the platform name.
  mount({ host: capabilities({ platform: "windows", ime_mode_scope: true }) });
  await screen.findByRole("button", { name: "保存设置" });
  expect(screen.getByLabelText("中英文状态范围")).toBeTruthy();
});

test("a Windows host does not receive the Linux-only mode scope control", async () => {
  mount({ host: capabilities({ platform: "windows" }) });
  await screen.findByRole("button", { name: "保存设置" });
  expect(screen.queryByLabelText("中英文状态范围")).toBeNull();
});

test("a host without capabilities keeps the previous user-agent behaviour", async () => {
  // No host field: the shared UI must fall back to isLinuxDesktop(), which is
  // false under jsdom, so this matches the behaviour shipped before the contract.
  mount({});
  await screen.findByRole("button", { name: "保存设置" });
  expect(screen.queryByLabelText("中英文状态范围")).toBeNull();
});

test("typing statistics follow the injected client on any platform", async () => {
  const statistics = {
    load: vi.fn().mockResolvedValue({ enabled: false, statistics: null }),
    setEnabled: vi.fn().mockResolvedValue(undefined),
    reset: vi.fn().mockResolvedValue(undefined),
  };
  // Previously this category was reachable only when the user agent matched Android.
  mount({ host: capabilities({ platform: "windows" }), typingStatistics: statistics });
  await screen.findByRole("button", { name: "保存设置" });
  expect(screen.getByRole("button", { name: "打字统计" })).toBeTruthy();
});

test("Windows and Linux hosts expose the shared fuzzy-pinyin settings", async () => {
  mount({ host: capabilities({ platform: "windows", fuzzy_pinyin: true }), fuzzyPinyin: true });
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  expect(screen.getByRole("group", { name: "模糊音" })).toBeTruthy();

  cleanup();
  mount({ host: capabilities({ platform: "linux", fuzzy_pinyin: true }), fuzzyPinyin: true });
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  expect(screen.getByRole("group", { name: "模糊音" })).toBeTruthy();
});

test("shortcut groups follow declared capabilities, not the platform name", async () => {
  // A Windows host that declares the capabilities gets the controls, proving the
  // gate is the capability and not a platform-name or user-agent match.
  const capable = mount({
    host: capabilities({ platform: "windows", mode_switch_shortcuts: true, panel_shortcuts: true }),
  });
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "快捷键" }));
  expect(screen.getByRole("group", { name: "面板快捷键" })).toBeTruthy();
  expect(screen.getByRole("group", { name: "输入模式切换快捷键" })).toBeTruthy();
  capable.unmount();

  // A Linux host that does not declare them keeps them hidden.
  mount({ host: capabilities({ platform: "linux" }) });
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "快捷键" }));
  expect(screen.queryByRole("group", { name: "面板快捷键" })).toBeNull();
  expect(screen.queryByRole("group", { name: "输入模式切换快捷键" })).toBeNull();
});

test("the restart action needs both the capability and an injected handler", async () => {
  const withoutHandler = mount({ host: capabilities({ platform: "linux", restart_input_method: true }) });
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "快捷键" }));
  expect(screen.queryByRole("button", { name: "重启" })).toBeNull();
  withoutHandler.unmount();

  mount({ host: capabilities({ platform: "linux", restart_input_method: true }), restartInputMethod: vi.fn() });
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "快捷键" }));
  expect(screen.getByRole("button", { name: "重启" })).toBeTruthy();
});

test("toolbar scale and components are hidden on a host that cannot apply them", async () => {
  // The Linux host stands the toolbar up as an IBus property menu: the enable
  // switch works, but scale, icon size and component visibility have no surface.
  const menuOnly = mount({ host: capabilities({ platform: "linux", floating_toolbar_appearance: false }) });
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "悬浮工具栏" }));
  expect(screen.getByLabelText("在桌面显示悬浮工具栏")).toBeTruthy();
  expect(screen.queryByLabelText("工具栏缩放")).toBeNull();
  expect(screen.queryByLabelText("图标尺寸")).toBeNull();
  menuOnly.unmount();

  // A host that draws its own toolbar keeps the full set.
  mount({ host: capabilities({ platform: "macos", floating_toolbar_appearance: true }) });
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "悬浮工具栏" }));
  expect(screen.getByLabelText("工具栏缩放")).toBeTruthy();
  expect(screen.getByLabelText("图标尺寸")).toBeTruthy();
});

test("the floating-toolbar settings page is hidden when the host has no toolbar", async () => {
  mount({ host: capabilities({ platform: "android", floating_toolbar: false, floating_toolbar_appearance: false }) });
  await screen.findByRole("button", { name: "保存设置" });
  expect(screen.queryByRole("button", { name: "悬浮工具栏" })).toBeNull();
});

test("candidate appearance follows host capabilities", async () => {
  mount({ host: capabilities({ platform: "linux", candidate_font_controls: false, candidate_row_colors: true, candidate_selection_appearance: false }) });
  await screen.findByRole("button", { name: "保存设置" });
  expect(screen.queryByLabelText("候选窗主字体")).toBeNull();
  expect(screen.queryByLabelText("候选字号")).toBeNull();
  expect(screen.queryByLabelText("候选窗预编辑字号")).toBeNull();
  expect(screen.getByLabelText("候选强调色")).toBeTruthy();
  expect(screen.getByLabelText("候选选中色")).toBeTruthy();
  expect(screen.queryByLabelText("候选悬停色")).toBeNull();
  expect(screen.queryByLabelText("候选边框色")).toBeNull();
  expect(screen.getByLabelText("候选文字颜色")).toBeTruthy();
  expect(screen.getByLabelText("候选表面色")).toBeTruthy();
  expect(screen.getByLabelText("候选编号颜色")).toBeTruthy();
  expect(screen.getByText("当前宿主的 IBus 候选面板不支持自定义字体或字号。")).toBeTruthy();
  expect(screen.getByText("当前宿主的候选面板不支持悬停或边框颜色。")).toBeTruthy();
});

test("Windows candidate appearance keeps native controls", async () => {
  mount({ host: capabilities({ platform: "windows", candidate_font_controls: true, candidate_selection_appearance: true }) });
  await screen.findByRole("button", { name: "保存设置" });
  expect(screen.getByLabelText("候选字号")).toBeTruthy();
  expect(screen.getByLabelText("候选强调色")).toBeTruthy();
  expect(screen.getByLabelText("候选边框色")).toBeTruthy();
});
