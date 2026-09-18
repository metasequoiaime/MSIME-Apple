// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { VoicePanel } from "@msime/ui";

afterEach(cleanup);

test("late recognition result is ignored after closing the panel", async () => {
  let resolve!: (value: { text: string }) => void;
  const recognizeVoice = vi.fn(() => new Promise<{ text: string }>(done => { resolve = done; }));
  const close = vi.fn(async () => {});
  const view = render(<VoicePanel client={{ close, recognizeVoice }} />);
  fireEvent.click(screen.getByRole("button", { name: "开始录音" }));
  fireEvent.click(screen.getByRole("button", { name: "关闭" }));
  await act(async () => resolve({ text: "过期结果" }));
  expect((screen.getByRole("textbox", { name: "识别结果" }) as HTMLTextAreaElement).value).toBe("");
  view.unmount();
});
