// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import {
  AccountPage,
  SettingsPage,
  type AccountClient,
  type AccountProfile,
  type AccountUser,
  type Snapshot,
} from "@msime/ui";

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

const user: AccountUser = {
  id: "fixture-user-id",
  displayName: "水杉测试用户",
  createdAt: "2026-01-01T00:00:00Z",
};
const profile: AccountProfile = { user, providers: ["email"] };

function account(overrides: Partial<AccountClient> = {}): AccountClient {
  return {
    status: vi.fn().mockResolvedValue({ user: null }),
    providers: vi.fn().mockResolvedValue({ email: true, phone: true }),
    requestCode: vi.fn().mockResolvedValue({ challengeId: "fixture-challenge", expiresIn: 300 }),
    login: vi.fn().mockResolvedValue({ user }),
    profile: vi.fn().mockResolvedValue(profile),
    rename: vi.fn().mockResolvedValue(profile),
    logout: vi.fn().mockResolvedValue(undefined),
    deleteAccount: vi.fn().mockResolvedValue(undefined),
    clearExpired: vi.fn().mockResolvedValue(undefined),
    ...overrides,
  };
}

test("code login trims the target, requires six ASCII digits and loads the profile", async () => {
  const client = account();
  render(<AccountPage client={client} />);
  fireEvent.click(await screen.findByRole("button", { name: "邮箱登录" }));
  fireEvent.change(screen.getByRole("textbox", { name: "邮箱地址" }), {
    target: { value: "  fixture@example.test  " },
  });
  fireEvent.click(screen.getByRole("button", { name: "获取验证码" }));
  await waitFor(() => expect(client.requestCode).toHaveBeenCalledWith("email", "fixture@example.test"));
  const login = await screen.findByRole("button", { name: "登录" });
  expect((login as HTMLButtonElement).disabled).toBe(true);
  fireEvent.change(screen.getByRole("textbox", { name: "6 位验证码" }), {
    target: { value: "12a３3456" },
  });
  expect((screen.getByRole("textbox", { name: "6 位验证码" }) as HTMLInputElement).value).toBe("123456");
  fireEvent.click(screen.getByRole("button", { name: "登录" }));
  await waitFor(() => expect(client.login).toHaveBeenCalledWith("fixture-challenge", "123456"));
  expect(await screen.findByText("水杉测试用户")).not.toBeNull();
  expect(screen.getByText("邮箱")).not.toBeNull();
  expect(screen.queryByText("fixture-challenge")).toBeNull();
});

test("profile rename, logout-all confirmation and account deletion use explicit actions", async () => {
  const renamed = { ...user, displayName: "新昵称" };
  const client = account({
    status: vi.fn().mockResolvedValue({ user }),
    rename: vi.fn().mockResolvedValue({ user: renamed, providers: ["email"] }),
  });
  render(<AccountPage client={client} />);
  const name = await screen.findByRole("textbox", { name: "社区昵称" });
  fireEvent.change(name, { target: { value: "  新昵称  " } });
  fireEvent.click(screen.getByRole("button", { name: "保存昵称" }));
  await waitFor(() => expect(client.rename).toHaveBeenCalledWith("新昵称"));

  fireEvent.click(screen.getByRole("button", { name: "退出所有设备" }));
  expect(screen.getByRole("alertdialog", { name: "确认退出所有设备" })).not.toBeNull();
  fireEvent.click(screen.getByRole("button", { name: "取消" }));
  expect(client.logout).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole("button", { name: "退出所有设备" }));
  fireEvent.click(screen.getByRole("button", { name: "确认退出所有设备" }));
  await waitFor(() => expect(client.logout).toHaveBeenCalledWith(true));
});

test("account deletion requires its destructive confirmation", async () => {
  const client = account({ status: vi.fn().mockResolvedValue({ user }) });
  render(<AccountPage client={client} />);
  await screen.findByRole("textbox", { name: "社区昵称" });
  fireEvent.click(screen.getByRole("button", { name: "注销账号" }));
  expect(client.deleteAccount).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole("button", { name: "确认注销账号" }));
  await waitFor(() => expect(client.deleteAccount).toHaveBeenCalledTimes(1));
});

test("account errors are stable and never expose backend text", async () => {
  const client = account({
    providers: vi.fn().mockRejectedValue({ code: "account_rate_limited", message: "private backend detail" }),
  });
  render(<AccountPage client={client} />);
  expect((await screen.findByRole("alert")).textContent).toBe("操作过于频繁，请稍后再试。");
  expect(screen.queryByText(/private backend detail/)).toBeNull();
});

test("logged-in accounts can open their published skin list", async () => {
  const openPublishedSkins = vi.fn();
  const client = account({ status: vi.fn().mockResolvedValue({ user }) });
  render(<AccountPage client={client} onOpenPublishedSkins={openPublishedSkins} />);
  fireEvent.click(await screen.findByRole("button", { name: "我发布的皮肤" }));
  expect(openPublishedSkins).toHaveBeenCalledTimes(1);
});

test("logged-in accounts expose local designs and every community collection", async () => {
  const openLocalDesigns = vi.fn();
  const openCommunity = vi.fn();
  const client = account({ status: vi.fn().mockResolvedValue({ user }) });
  render(<AccountPage client={client} onOpenLocalDesigns={openLocalDesigns} onOpenCommunity={openCommunity} />);
  fireEvent.click(await screen.findByRole("button", { name: "打开设计器" }));
  fireEvent.click(screen.getByRole("button", { name: "我发布的皮肤" }));
  fireEvent.click(screen.getByRole("button", { name: "我发布的词库" }));
  fireEvent.click(screen.getByRole("button", { name: "我发布的回复" }));
  fireEvent.click(screen.getByRole("button", { name: "收藏的词库" }));
  fireEvent.click(screen.getByRole("button", { name: "收藏的回复" }));
  expect(openLocalDesigns).toHaveBeenCalledTimes(1);
  expect(openCommunity.mock.calls).toEqual([
    ["published-skins"], ["published-dictionary"], ["published-reply"],
    ["saved-dictionary"], ["saved-reply"],
  ]);
});

test("local designs remain available without an account", async () => {
  const openLocalDesigns = vi.fn();
  render(<AccountPage client={account()} onOpenLocalDesigns={openLocalDesigns} />);
  fireEvent.click(await screen.findByRole("button", { name: "打开设计器" }));
  expect(openLocalDesigns).toHaveBeenCalledTimes(1);
});

test("Android app icon choices read the launcher state and use an explicit selection", async () => {
  const set = vi.fn().mockResolvedValue({ supported: true, selected: "forest" });
  const client = account({
    appIcon: {
      info: vi.fn().mockResolvedValue({ supported: true, selected: "classic" }),
      set,
    },
  });
  render(<AccountPage client={client} />);
  expect((await screen.findByRole("button", { name: "原版，经典黑白，简洁如初" })).getAttribute("aria-pressed")).toBe("true");
  fireEvent.click(screen.getByRole("button", { name: "杉林，杉叶青绿，沉静自然" }));
  await waitFor(() => expect(set).toHaveBeenCalledWith("forest"));
  expect(screen.getByRole("button", { name: "杉林，杉叶青绿，沉静自然" }).getAttribute("aria-pressed")).toBe("true");
});

test("settings sync requires confirmation and preserves a remote conflict error", async () => {
  const upload = vi.fn().mockResolvedValue({ revision: 8, settings: { "input.schema": "shuangpin" } });
  const apply = vi.fn().mockRejectedValue({ code: "account_conflict" });
  const client = account({
    status: vi.fn().mockResolvedValue({ user }),
    settingsSync: {
      schema: vi.fn().mockResolvedValue({
        fields: { "input.schema": { type: "string" } }, maximumBytes: 65536,
        updateMode: "replace", revisionRequired: true,
      }),
      load: vi.fn().mockResolvedValue({ revision: 7, settings: { "input.schema": "quanpin" } }),
      upload,
      apply,
    },
  });
  render(<AccountPage client={client} />);
  expect(await screen.findByText("云端版本：7")).not.toBeNull();
  fireEvent.click(screen.getByRole("button", { name: "上传本机设置" }));
  expect(upload).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole("button", { name: "确认上传" }));
  await waitFor(() => expect(upload).toHaveBeenCalledTimes(1));

  fireEvent.click(screen.getByRole("button", { name: "下载并应用云端设置" }));
  fireEvent.click(screen.getByRole("button", { name: "确认应用" }));
  await waitFor(() => expect(apply).toHaveBeenCalledWith("fixture-user-id", { revision: 8, settings: { "input.schema": "shuangpin" } }));
  expect(await screen.findByText("云端设置已被其他设备更新，请刷新后重新确认。")).not.toBeNull();
});

const preferences: Snapshot = {
  format_version: 1,
  revision: 1,
  preferences: {
    scheme: "quanpin",
    shuangpin_profile: "xiaohe",
    candidate_page_size: 5,
    learning: true,
    chinese_punctuation: true,
  },
};

test("settings expose My only with the Android capability and omit preference actions there", async () => {
  const without = render(<SettingsPage client={{ load: async () => preferences, save: vi.fn() }} />);
  await screen.findByRole("button", { name: "保存设置" });
  expect(screen.queryByRole("button", { name: "我的" })).toBeNull();
  without.unmount();

  render(<SettingsPage client={{ load: async () => preferences, save: vi.fn(), account: account() }} initialPage="account" />);
  expect(await screen.findByRole("heading", { name: "我的" })).not.toBeNull();
  await screen.findByText("欢迎来到水杉");
  expect(screen.queryByRole("button", { name: "保存设置" })).toBeNull();
  expect(screen.queryByRole("button", { name: "重新读取" })).toBeNull();
});
