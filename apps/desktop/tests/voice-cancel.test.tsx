// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { VoicePanel } from "@msime/ui";

afterEach(cleanup);

test("voice panel stops an in-flight recognition request", async () => {
  let resolve!: (value: { text: string }) => void;
  const cancelVoice = vi.fn().mockResolvedValue(undefined);
  const recognizeVoice = vi.fn(() => new Promise<{ text: string }>(done => { resolve = done; }));
  render(<VoicePanel client={{ close: async () => {}, recognizeVoice, cancelVoice }} />);
  fireEvent.click(screen.getByRole("button", { name: "开始录音" }));
  await act(async () => { fireEvent.click(screen.getByRole("button", { name: "停止录音" })); });
  expect(cancelVoice).toHaveBeenCalledOnce();
  expect((screen.getByRole("button", { name: "开始录音" }) as HTMLButtonElement).disabled).toBe(false);
  await act(async () => resolve({ text: "过期结果" }));
  expect((screen.getByRole("textbox", { name: "识别结果" }) as HTMLTextAreaElement).value).toBe("");
});

test.each([false, true])("old recognition completion does not end a restarted recording (reject=%s)", async rejectOld => {
  const pending: { resolve: (value: { text: string }) => void; reject: (error: Error) => void }[] = [];
  const recognizeVoice = vi.fn(() => new Promise<{ text: string }>((resolve, reject) => { pending.push({ resolve, reject }); }));
  const cancelVoice = vi.fn().mockResolvedValue(undefined);
  render(<VoicePanel client={{ close: async () => {}, recognizeVoice, cancelVoice, sendText: vi.fn() }} />);
  fireEvent.click(screen.getByRole("button", { name: "开始录音" }));
  await act(async () => fireEvent.click(screen.getByRole("button", { name: "停止录音" })));
  fireEvent.click(screen.getByRole("button", { name: "开始录音" }));
  expect(recognizeVoice).toHaveBeenCalledTimes(2);
  await act(async () => {
    if (rejectOld) pending[0].reject(new Error("fixture failure"));
    else pending[0].resolve({ text: "fixture-old" });
  });
  expect(screen.getByRole("button", { name: "停止录音" })).toBeDefined();
  expect((screen.getByRole("textbox", { name: "识别结果" }) as HTMLTextAreaElement).value).toBe("");
  expect((screen.getByRole("button", { name: "提交到当前窗口" }) as HTMLButtonElement).disabled).toBe(true);
  await act(async () => pending[1].resolve({ text: "fixture-current" }));
  expect(screen.getByRole("button", { name: "开始录音" })).toBeDefined();
  expect((screen.getByRole("textbox", { name: "识别结果" }) as HTMLTextAreaElement).value).toBe("fixture-current");
});

test("voice updates are ignored before recording and after cancellation", async () => {
  let update!: (value: { text: string; final: boolean }) => void;
  const onVoiceUpdate = vi.fn(async listener => { update = listener; return vi.fn(); });
  const recognizeVoice = vi.fn(() => new Promise<{ text: string }>(() => {}));
  render(<VoicePanel client={{ close: async () => {}, recognizeVoice, cancelVoice: async () => {}, onVoiceUpdate }} />);
  await act(async () => update({ text: "fixture-idle", final: false }));
  const result = screen.getByRole("textbox", { name: "识别结果" }) as HTMLTextAreaElement;
  expect(result.value).toBe("");
  fireEvent.click(screen.getByRole("button", { name: "开始录音" }));
  await act(async () => update({ text: "fixture-active", final: false }));
  expect(result.value).toBe("fixture-active");
  await act(async () => fireEvent.click(screen.getByRole("button", { name: "停止录音" })));
  await act(async () => update({ text: "fixture-late", final: true }));
  expect(result.value).toBe("fixture-active");
  expect(screen.getByRole("status").textContent).toBe("录音已停止");
});
