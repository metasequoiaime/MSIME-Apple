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
  fireEvent.click(screen.getByRole("button", { name: "停止录音" }));
  expect(cancelVoice).toHaveBeenCalledOnce();
  expect(screen.getByRole("button", { name: "开始录音" })).toHaveProperty("disabled", false);
  await act(async () => resolve({ text: "过期结果" }));
  expect((screen.getByRole("textbox", { name: "识别结果" }) as HTMLTextAreaElement).value).toBe("");
});
