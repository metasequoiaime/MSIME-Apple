// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { SettingsPage, type Snapshot } from "@msime/ui";

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

const snapshot: Snapshot = {
  format_version: 1,
  revision: 2,
  preferences: {
    scheme: "quanpin",
    shuangpin_profile: "xiaohe",
    candidate_page_size: 5,
    learning: true,
    chinese_punctuation: true,
    ai_assistant: {
      enabled: true,
      provider: "deepseek",
      model: "deepseek-v4-flash",
      endpoint: "https://api.deepseek.com/chat/completions",
      candidate_limit: 3,
      token: "synthetic-token",
      tokens: {},
      prompt_custom_1: "",
      prompt_custom_2: "",
      prompt_custom_3: "",
    },
  },
};

async function openAi(platform: string) {
  render(
    <SettingsPage
      client={{ load: async () => snapshot, save: vi.fn(), host: { platform } as never }}
    />,
  );
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "AI 辅助" }));
}

test("Linux points AI credentials at the private provider config", async () => {
  await openAi("linux");

  expect(screen.queryByLabelText("AI API Token")).toBeNull();
  expect(screen.getByText("ai-provider.json")).toBeTruthy();
  expect(screen.getByLabelText("AI 接口地址")).toBeTruthy();
});

test("Windows keeps the shared AI token field", async () => {
  await openAi("windows");

  expect(screen.getByLabelText("AI API Token")).toBeTruthy();
  expect(screen.queryByText("ai-provider.json")).toBeNull();
});
