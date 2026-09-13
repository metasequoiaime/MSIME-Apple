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
    restart_input_method: false,
    panel_windows: true,
    ime_mode_scope: false,
    typing_statistics: true,
    system_fonts: true,
    window_chrome: true,
    floating_toolbar: true,
    ...overrides,
  };
}

function mount(client: Partial<SettingsClient>) {
  return render(<SettingsPage client={{ load: async () => initial, save: vi.fn(), ...client }} />);
}

test("host capabilities decide platform-specific settings instead of the user agent", async () => {
  // jsdom reports a Linux-like user agent, so the legacy probe would say "not Linux".
  // A host that declares itself Linux must win regardless.
  mount({ host: capabilities({ platform: "linux", ime_mode_scope: true }) });
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

test("host-gated shortcut groups follow the declared platform", async () => {
  const linux = mount({ host: capabilities({ platform: "linux" }), restartInputMethod: vi.fn() });
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "快捷键" }));
  expect(screen.getByRole("group", { name: "Linux 面板快捷键" })).toBeTruthy();
  linux.unmount();

  mount({ host: capabilities({ platform: "windows" }), restartInputMethod: vi.fn() });
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "快捷键" }));
  expect(screen.queryByRole("group", { name: "Linux 面板快捷键" })).toBeNull();
});
