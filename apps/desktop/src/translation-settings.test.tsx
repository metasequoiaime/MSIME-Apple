// @vitest-environment jsdom
import { afterEach, describe, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { SettingsPage, translationEndpointIssue, type Snapshot } from "@msime/ui";

afterEach(cleanup);

const base: Snapshot = {
  format_version: 1,
  revision: 11,
  preferences: {
    scheme: "quanpin", shuangpin_profile: "xiaohe", candidate_page_size: 5, learning: true, chinese_punctuation: true,
    candidate_translations: true,
    custom_translation: { enabled: true, endpoint: "https://example.com/translate", api_key: "secret-value" },
  },
};

async function mount(preferences: Record<string, unknown> = {}) {
  const snapshot: Snapshot = { ...base, preferences: { ...base.preferences, ...preferences } };
  const mounted = render(<SettingsPage client={{ load: async () => snapshot, save: vi.fn() }} />);
  await screen.findByRole("button", { name: "保存设置" });
  // The translation controls live on the 输入 page; other pages are hidden, and
  // hidden subtrees are absent from the accessibility tree.
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  return mounted;
}

const endpointField = () => screen.getByLabelText("自定义翻译 Endpoint") as HTMLInputElement;

describe("translationEndpointIssue mirrors the Rust rule", () => {
  // client-core::translation::is_supported_endpoint: non-empty, <= 2048 bytes,
  // no control characters, and an http:// or https:// scheme.
  test.each([
    ["", true],
    ["example.com/translate", true],
    ["ftp://example.com", true],
    ["https://example.com/translate", false],
    ["http://example.com/translate", false],
    ["https://example.com/\u0007", true],
    [`https://example.com/${"a".repeat(2048)}`, true],
  ])("%s", (endpoint, expectIssue) => {
    expect(translationEndpointIssue(endpoint) !== "").toBe(expectIssue);
  });
});

test("a scheme-less endpoint warns instead of silently returning no glosses", async () => {
  await mount();
  expect(screen.queryByRole("status")).toBeNull();
  fireEvent.change(endpointField(), { target: { value: "example.com/translate" } });
  expect(screen.getByRole("status").textContent).toContain("http://");
  fireEvent.change(endpointField(), { target: { value: "https://example.com/translate" } });
  expect(screen.queryByRole("status")).toBeNull();
});

test("translation credentials are disabled while candidate translation is off", async () => {
  await mount({ candidate_translations: false });
  expect(endpointField().disabled).toBe(true);
  expect((screen.getByLabelText("自定义翻译 API Key") as HTMLInputElement).disabled).toBe(true);
  // The group and its switch share the label, so select the switch by role.
  expect((screen.getByRole("checkbox", { name: "自定义翻译服务" }) as HTMLInputElement).disabled).toBe(true);
  // A disabled field must not shout about its contents.
  expect(screen.queryByRole("status")).toBeNull();
});

test("the API key can be revealed to check a pasted value", async () => {
  await mount();
  const key = screen.getByLabelText("自定义翻译 API Key") as HTMLInputElement;
  expect(key.type).toBe("password");
  const reveal = screen.getByRole("button", { name: "显示自定义翻译 API Key" });
  expect(reveal.getAttribute("aria-pressed")).toBe("false");
  fireEvent.click(reveal);
  expect((screen.getByLabelText("自定义翻译 API Key") as HTMLInputElement).type).toBe("text");
  expect(screen.getByRole("button", { name: "隐藏自定义翻译 API Key" }).getAttribute("aria-pressed")).toBe("true");
});
