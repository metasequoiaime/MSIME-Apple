// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { ASR_PROVIDER_DEFAULTS, SettingsPage, type Snapshot } from "@msime/ui";

afterEach(cleanup);
test.each(["openai", "siliconflow", "groq"])("Windows %s ASR test uses synthetic-audio command configuration", async provider => {
  const snapshot: Snapshot = { format_version: 1, revision: 1, preferences: {
    scheme: "quanpin", shuangpin_profile: "xiaohe", candidate_page_size: 5,
    learning: true, chinese_punctuation: true,
    voice_input: { enabled: true, language: "zh-cn", asr_provider: provider,
      asr_endpoint: "", asr_model: "", asr_token: "synthetic-key" },
  } };
  const probe = vi.fn().mockResolvedValue({ ok: true, message: "fixture complete" });
  render(<SettingsPage initialPage="voice" client={{ load: async () => snapshot,
    save: vi.fn(), testApiCredential: probe, host: { platform: "windows" } as never }} />);
  const button = await screen.findByRole("button", { name: "测试语音识别配置" });
  expect(probe).not.toHaveBeenCalled();
  expect(screen.getByText(/一秒合成静音/)).toBeTruthy();
  fireEvent.click(button);
  await screen.findByText("fixture complete");
  expect(probe).toHaveBeenCalledWith("voice.asr", {
    provider, ...ASR_PROVIDER_DEFAULTS[provider], token: "synthetic-key",
  });
  // Switching to a streaming provider must not send its credentials through
  // the multipart batch probe; Linux has its separate provider-based control.
  fireEvent.change(screen.getByLabelText("识别服务"), { target: { value: "doubao" } });
  expect(screen.queryByRole("button", { name: "测试语音识别配置" })).toBeNull();
});
