// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import {
  SettingsPage,
  tencentCredentialIssue,
  tencentSecretConfigured,
  type Preferences,
  type Snapshot,
} from "@msime/ui";

afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const snapshot: Snapshot = {
  format_version: 1, revision: 2,
  preferences: {
    scheme: "quanpin", shuangpin_profile: "xiaohe", candidate_page_size: 5,
    learning: true, chinese_punctuation: true, candidate_translations: true,
  },
};

test("a placeholder is not a configured secret", () => {
  // Mirrors usable_tencent_secret in client-core: the shipped config template
  // carries <YOUR_TENCENT_SECRET_ID>, which must not read as configured.
  expect(tencentSecretConfigured("")).toBe(false);
  expect(tencentSecretConfigured("   ")).toBe(false);
  expect(tencentSecretConfigured("<YOUR_TENCENT_SECRET_ID>")).toBe(false);
  expect(tencentSecretConfigured("FAKESECRET_abc")).toBe(false);
  expect(tencentSecretConfigured("AKIDreal")).toBe(true);
});

test("credential rules match the ones that would reject the save", () => {
  // Preferences::validate refuses these outright, so the page says so first
  // rather than letting the save fail with no explanation.
  expect(tencentCredentialIssue("AKID_ok-1", "key", "ap-guangzhou")).toBe("");
  expect(tencentCredentialIssue("has space", "key", "ap-guangzhou")).toContain("SecretId");
  expect(tencentCredentialIssue("AKID", "key", "ap guangzhou")).toContain("地域");
  expect(tencentCredentialIssue("AKID", "key", "a".repeat(65))).toContain("地域");
  expect(tencentCredentialIssue("a".repeat(4097), "key", "ap-guangzhou")).toContain("过长");
  expect(tencentCredentialIssue("AKID", "bad\u0001key", "ap-guangzhou")).toContain("控制字符");
});

test("the credentials can be entered and are saved", async () => {
  const save = vi.fn(async (_revision: number, _preferences: Preferences) => snapshot);
  render(<SettingsPage client={{ load: async () => snapshot, save }} />);
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "输入" }));

  // Before this change there was no way to enter these at all.
  const id = await screen.findByLabelText("腾讯云 SecretId");
  fireEvent.change(id, { target: { value: "AKIDexample" } });
  fireEvent.change(screen.getByLabelText("腾讯云 SecretKey"), { target: { value: "s3cret" } });
  fireEvent.change(screen.getByLabelText("腾讯云地域"), { target: { value: "ap-shanghai" } });

  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await waitFor(() => expect(save).toHaveBeenCalled());
  const saved = save.mock.calls[0][1];
  expect(saved.tencent_tmt).toEqual({
    enabled: true, secret_id: "AKIDexample", secret_key: "s3cret", region: "ap-shanghai",
  });
});

test("empty credentials are called out instead of silently returning nothing", async () => {
  render(<SettingsPage client={{ load: async () => snapshot, save: vi.fn() }} />);
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "输入" }));

  // This is the user-visible defect: translation on, no keys, no explanation.
  await screen.findByText(/未填写腾讯云凭据/);

  // Entering a usable pair clears it.
  fireEvent.change(screen.getByLabelText("腾讯云 SecretId"), { target: { value: "AKIDexample" } });
  fireEvent.change(screen.getByLabelText("腾讯云 SecretKey"), { target: { value: "s3cret" } });
  await waitFor(() => expect(screen.queryByText(/未填写腾讯云凭据/)).toBeNull());

  // A malformed SecretId reports the rule that would reject the save instead.
  fireEvent.change(screen.getByLabelText("腾讯云 SecretId"), { target: { value: "bad id" } });
  await screen.findByText(/SecretId 只能包含/);
});

test("the copy no longer claims a Linux provider on every platform", async () => {
  render(<SettingsPage client={{ load: async () => snapshot, save: vi.fn() }} />);
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  await screen.findByLabelText("腾讯云 SecretId");
  // Windows performs the request natively in TranslationWorker, so telling
  // every user it goes through a Linux provider socket was simply wrong.
  // Scoped to the translation groups: the voice sections carry the same wrong
  // claim, but that is a separate gap and is not touched here.
  const online = screen.getByRole("group", { name: "在线翻译服务" });
  const custom = screen.getByRole("group", { name: "自定义翻译服务" });
  expect(online.textContent).not.toContain("Linux provider");
  expect(custom.textContent).not.toContain("Linux provider");
  expect(custom.textContent).toContain("DeepLX");
});
