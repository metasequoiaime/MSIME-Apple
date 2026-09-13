// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { SettingsPage, type Snapshot } from "@msime/ui";

afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const snapshot: Snapshot = {
  format_version: 1, revision: 2,
  preferences: {
    scheme: "quanpin", shuangpin_profile: "xiaohe", candidate_page_size: 5,
    learning: true, chinese_punctuation: true,
    voice_input: { enabled: true, language: "zh-CN", asr_provider: "doubao", asr_token: "secret-token" },
  },
};

function host(platform: string) {
  return { platform, voice_capture_devices: true } as never;
}

async function openVoice(platform: string) {
  render(<SettingsPage client={{ load: async () => snapshot, save: vi.fn(), host: host(platform) }} />);
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "语音输入" }));
  // The token fields are hidden on Linux, where credentials belong to the
  // provider service, so wait on a control both platforms render.
  return await screen.findByLabelText(platform === "android" ? "识别语言" : "识别服务");
}

test("a pasted recognition token can be revealed to check it", async () => {
  await openVoice("windows");
  const token = await screen.findByLabelText("识别 API Token");
  // Before this the field was a bare <input type=password>: a truncated or
  // mistyped paste could not be checked, even though SecretInput already
  // existed and was used for the translation key.
  expect((token as HTMLInputElement).type).toBe("password");
  fireEvent.click(screen.getByRole("button", { name: "显示识别 API Token" }));
  expect((screen.getByLabelText("识别 API Token") as HTMLInputElement).type).toBe("text");
  expect((screen.getByLabelText("识别 API Token") as HTMLInputElement).value).toBe("secret-token");
  fireEvent.click(screen.getByRole("button", { name: "隐藏识别 API Token" }));
  expect((screen.getByLabelText("识别 API Token") as HTMLInputElement).type).toBe("password");
});

test("the Doubao app key and polish token get the same toggle", async () => {
  await openVoice("windows");
  expect(screen.getByRole("button", { name: "显示Doubao App Key" })).toBeTruthy();
  expect(screen.getByRole("button", { name: "显示润色 API Token" })).toBeTruthy();
});

// Asserted element by element rather than over document.body: every page is
// mounted at once, so a whole-body scan also picks up unrelated sections.
test("Windows is not told its voice input runs through a Linux provider", async () => {
  await openVoice("windows");
  // On Windows these options drive VoiceHotkeyController, CuePlayer and
  // SystemAudioMuter in-process; there is no provider socket involved.
  expect(screen.getByText("语音快捷键")).toBeTruthy();
  expect(screen.getByText("录音行为")).toBeTruthy();
  expect(screen.queryByText("Linux IBus 快捷键")).toBeNull();
  expect(screen.queryByText("Linux provider 行为")).toBeNull();
  expect(screen.queryByText(/IBus 属性/)).toBeNull();
  expect(screen.queryByText(/录音和识别由已配置的 provider 服务完成/)).toBeNull();
  expect(screen.getByText(/录音和识别在本机完成/)).toBeTruthy();
  expect(screen.getByText(/随识别请求发送给豆包/)).toBeTruthy();
});

test("Linux keeps the wording that is accurate there", async () => {
  await openVoice("linux");
  expect(screen.getByText("Linux provider 行为")).toBeTruthy();
  expect(screen.getByText("Linux IBus 快捷键")).toBeTruthy();
  expect(screen.getByText(/IBus 属性/)).toBeTruthy();
  expect(screen.queryByText("语音快捷键")).toBeNull();
  expect(screen.queryByText("录音行为")).toBeNull();
});

test("Android uses the system recognizer and hides desktop voice controls", async () => {
  await openVoice("android");
  expect(screen.getByText("Android 系统语音")).toBeTruthy();
  expect(screen.getByText("从键盘工具栏的“语音”入口调用设备上的系统语音识别服务。识别结果会回到键盘，确认后才插入当前输入框。")).toBeTruthy();
  expect(screen.getByLabelText("识别语言")).toBeTruthy();
  expect(screen.queryByLabelText("识别服务")).toBeNull();
  expect(screen.queryByLabelText("识别 API Token")).toBeNull();
  expect(screen.queryByLabelText("结果提交策略")).toBeNull();
  expect(screen.queryByText("录音行为")).toBeNull();
  expect(screen.queryByText("文本润色 provider")).toBeNull();
  expect(screen.queryByText("语音快捷键")).toBeNull();
  expect(screen.queryByRole("button", { name: "打开" })).toBeNull();
});
