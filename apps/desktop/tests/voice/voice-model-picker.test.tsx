// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
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
    voice_input: {
      enabled: true,
      language: "zh-CN",
      asr_provider: "local",
      asr_model_path: "/old/model.bin",
    },
  },
};

async function openVoice(client: Record<string, unknown>) {
  render(
    <SettingsPage
      client={{
        load: async () => snapshot,
        save: vi.fn(),
        host: { platform: "macos" } as never,
        ...client,
      }}
    />,
  );
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "语音输入" }));
  return screen.findByLabelText("Whisper 模型文件");
}

test("choosing a model fills the path the recognizer loads", async () => {
  const pickVoiceModelPath = vi.fn(async () => "/Users/someone/models/ggml-base.bin");
  const field = (await openVoice({ pickVoiceModelPath })) as HTMLInputElement;
  expect(field.value).toBe("/old/model.bin");

  fireEvent.click(screen.getByRole("button", { name: "选择…" }));

  await waitFor(() => expect(field.value).toBe("/Users/someone/models/ggml-base.bin"));
  expect(pickVoiceModelPath).toHaveBeenCalledTimes(1);
});

test("cancelling leaves the path that already worked", async () => {
  const pickVoiceModelPath = vi.fn(async () => null);
  const field = (await openVoice({ pickVoiceModelPath })) as HTMLInputElement;

  fireEvent.click(screen.getByRole("button", { name: "选择…" }));

  await waitFor(() => expect(pickVoiceModelPath).toHaveBeenCalledTimes(1));
  expect(field.value).toBe("/old/model.bin");
});

test("a host that cannot pick files offers typing only", async () => {
  const field = (await openVoice({})) as HTMLInputElement;

  expect(screen.queryByRole("button", { name: "选择…" })).toBeNull();
  expect(field.value).toBe("/old/model.bin");
});
