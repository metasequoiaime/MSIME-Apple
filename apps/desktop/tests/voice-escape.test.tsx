// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { VoicePanel } from "@msime/ui";

afterEach(cleanup);
function escape(extra = {}) {
  const event = new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true, ...extra });
  fireEvent(window, event);
  return event.defaultPrevented;
}
function setup() {
  let resolve!: (value: { text: string }) => void;
  const cancelVoice = vi.fn().mockResolvedValue(undefined);
  const stopVoice = vi.fn().mockResolvedValue(undefined);
  const view = render(<VoicePanel client={{ close: vi.fn(), cancelVoice, stopVoice,
    recognizeVoice: () => new Promise<{ text: string }>(done => { resolve = done; }) }} />);
  return { view, cancelVoice, finish: () => resolve({ text: "fixture-late" }) };
}

test.each([false, true])("Escape cancels active recording or final recognition (stopping=%s)", async stopping => {
  const host = setup();
  expect(escape()).toBe(false);
  fireEvent.click(screen.getByRole("button", { name: "开始录音" }));
  expect(screen.getByText("按 Esc 取消录音")).toBeDefined();
  if (stopping) await act(async () => fireEvent.click(screen.getByRole("button", { name: "停止录音" })));
  await act(async () => expect(escape()).toBe(true));
  expect(host.cancelVoice).toHaveBeenCalledOnce();
  expect(escape({ repeat: true })).toBe(false);
  await act(async () => host.finish());
  expect((screen.getByRole("textbox", { name: "识别结果" }) as HTMLTextAreaElement).value).toBe("");
  expect(screen.getByRole("button", { name: "开始录音" })).toBeDefined();
});

test("modified and composing Escape do not cancel voice input", () => {
  const host = setup();
  fireEvent.click(screen.getByRole("button", { name: "开始录音" }));
  for (const modifier of ["ctrlKey", "altKey", "metaKey", "shiftKey", "isComposing"]) expect(escape({ [modifier]: true })).toBe(false);
  expect(host.cancelVoice).not.toHaveBeenCalled();
});

test("unmount removes the Escape listener and cancels only once", () => {
  const host = setup();
  fireEvent.click(screen.getByRole("button", { name: "开始录音" }));
  host.view.unmount();
  expect(host.cancelVoice).toHaveBeenCalledOnce();
  expect(escape()).toBe(false);
  expect(host.cancelVoice).toHaveBeenCalledOnce();
});

test("a host without cancellation does not consume Escape", () => {
  render(<VoicePanel client={{ close: vi.fn(), recognizeVoice: () => new Promise(() => {}) }} />);
  fireEvent.click(screen.getByRole("button", { name: "开始录音" }));
  expect(escape()).toBe(false);
});
