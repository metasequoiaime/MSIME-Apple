// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { VoicePanel } from "@msime/ui";

afterEach(cleanup);
function setup(failure = false) {
  let resolve!: (value: { text: string }) => void;
  const stopVoice = failure ? vi.fn().mockRejectedValue(new Error("fixture")) : vi.fn().mockResolvedValue(undefined);
  const cancelVoice = vi.fn().mockResolvedValue(undefined);
  const recognizeVoice = vi.fn(() => new Promise<{ text: string }>(done => { resolve = done; }));
  render(<VoicePanel client={{ close: async () => {}, recognizeVoice, stopVoice, cancelVoice, sendText: vi.fn() }} />);
  fireEvent.click(screen.getByRole("button", { name: "开始录音" }));
  return { stopVoice, cancelVoice, finish: (text: string) => resolve({ text }) };
}

test("stop waits for final recognition and permits committing it", async () => {
  const host = setup();
  await act(async () => fireEvent.click(screen.getByRole("button", { name: "停止录音" })));
  expect(host.stopVoice).toHaveBeenCalledOnce();
  expect(host.cancelVoice).not.toHaveBeenCalled();
  expect((screen.getByRole("button", { name: "正在完成识别…" }) as HTMLButtonElement).disabled).toBe(true);
  expect((screen.getByRole("button", { name: "提交到当前窗口" }) as HTMLButtonElement).disabled).toBe(true);
  await act(async () => host.finish("fixture-final"));
  expect((screen.getByRole("textbox", { name: "识别结果" }) as HTMLTextAreaElement).value).toBe("fixture-final");
  expect((screen.getByRole("button", { name: "提交到当前窗口" }) as HTMLButtonElement).disabled).toBe(false);
  expect(screen.getByRole("button", { name: "开始录音" })).toBeDefined();
});

test("cancel remains available while waiting for the stopped recording", async () => {
  const host = setup();
  await act(async () => fireEvent.click(screen.getByRole("button", { name: "停止录音" })));
  await act(async () => fireEvent.click(screen.getByRole("button", { name: "取消录音" })));
  expect(host.cancelVoice).toHaveBeenCalledOnce();
  await act(async () => host.finish("fixture-stale"));
  expect((screen.getByRole("textbox", { name: "识别结果" }) as HTMLTextAreaElement).value).toBe("");
});

test("failed stop permits retry and cancellation", async () => {
  const host = setup(true);
  await act(async () => fireEvent.click(screen.getByRole("button", { name: "停止录音" })));
  expect(screen.getByRole("status").textContent).toContain("停止录音失败");
  await act(async () => fireEvent.click(screen.getByRole("button", { name: "停止录音" })));
  expect(host.stopVoice).toHaveBeenCalledTimes(2);
  await act(async () => fireEvent.click(screen.getByRole("button", { name: "取消录音" })));
  expect(host.cancelVoice).toHaveBeenCalledOnce();
});
