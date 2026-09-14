// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { ASR_PROVIDER_DEFAULTS, SettingsPage, type Snapshot } from "@msime/ui";

afterEach(cleanup);
test.each(["api_key", "legacy"] as const)("Windows Doubao %s tests current edited credentials", async authMode => {
  const snapshot: Snapshot = { format_version: 1, revision: 1, preferences: {
    scheme: "quanpin", shuangpin_profile: "xiaohe", candidate_page_size: 5,
    learning: true, chinese_punctuation: true,
    voice_input: { enabled: true, language: "zh-cn", asr_provider: "doubao",
      doubao_auth_mode: authMode, asr_app_key: "synthetic-app", asr_token: "",
      asr_resource_id: "fixture-resource", asr_endpoint: "" },
  } };
  const probe = vi.fn().mockResolvedValue({ ok: true, message: "fixture complete" });
  render(<SettingsPage initialPage="voice" client={{ load: async () => snapshot,
    save: vi.fn(), testApiCredential: probe, host: { platform: "windows" } as never }} />);
  const button = await screen.findByRole("button", { name: "测试豆包识别配置" });
  expect((button as HTMLButtonElement).disabled).toBe(true);
  expect(probe).not.toHaveBeenCalled();
  fireEvent.change(screen.getByLabelText(authMode === "legacy" ? "识别 API Token" : "Doubao API Key"), { target: { value: "synthetic-key" } });
  expect((button as HTMLButtonElement).disabled).toBe(false);
  if (authMode === "legacy") {
    fireEvent.change(screen.getByLabelText("Doubao App Key"), { target: { value: "" } });
    expect((button as HTMLButtonElement).disabled).toBe(true);
    fireEvent.change(screen.getByLabelText("Doubao App Key"), { target: { value: "synthetic-app-edited" } });
  }
  fireEvent.click(button);
  await screen.findByText("fixture complete");
  expect(probe).toHaveBeenCalledWith("voice.asr", {
    provider: "doubao", ...ASR_PROVIDER_DEFAULTS.doubao, token: "synthetic-key",
    auth_mode: authMode, app_id: authMode === "legacy" ? "synthetic-app-edited" : "",
    resource_id: "fixture-resource",
  });
});
