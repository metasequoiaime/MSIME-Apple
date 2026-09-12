// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { VoicePanel } from "@msime/ui";

afterEach(cleanup);
function setup() {
  let resolve!: () => void;
  let reject!: (error: Error) => void;
  const sendVoiceText = vi.fn(() => new Promise<void>((done, fail) => { resolve = done; reject = fail; }));
  const client = { close: vi.fn().mockResolvedValue(undefined), sendVoiceText };
  const view = render(<VoicePanel client={client} />);
  const input = screen.getByRole("textbox", { name: "识别结果" }) as HTMLTextAreaElement;
  fireEvent.change(input, { target: { value: "fixture-original" } });
  fireEvent.click(screen.getByRole("button", { name: "提交到当前窗口" }));
  return { view, input, client, finish: () => resolve(), fail: () => reject(new Error("fixture")) };
}

test("voice submission runs once and clears the submitted text after success", async () => {
  const host = setup();
  const button = screen.getByRole("button", { name: "正在提交…" }) as HTMLButtonElement;
  expect(button.disabled).toBe(true);
  fireEvent.click(button);
  expect(host.client.sendVoiceText).toHaveBeenCalledExactlyOnceWith("fixture-original");
  expect((screen.getByRole("button", { name: "开始录音" }) as HTMLButtonElement).disabled).toBe(true);
  await act(async () => host.finish());
  expect(host.input.value).toBe("");
});

test("a completed voice submission preserves a newer edit", async () => {
  const host = setup();
  fireEvent.change(host.input, { target: { value: "fixture-new" } });
  await act(async () => host.finish());
  expect(host.input.value).toBe("fixture-new");
  expect((screen.getByRole("button", { name: "提交到当前窗口" }) as HTMLButtonElement).disabled).toBe(false);
});

test("failed submission keeps text and permits retry", async () => {
  const host = setup();
  await act(async () => host.fail());
  expect(host.input.value).toBe("fixture-original");
  expect(screen.getByRole("status").textContent).toContain("提交失败");
  fireEvent.click(screen.getByRole("button", { name: "提交到当前窗口" }));
  expect(host.client.sendVoiceText).toHaveBeenCalledTimes(2);
  await act(async () => host.finish());
});

test("an old host submission cannot clear text after host replacement", async () => {
  const host = setup();
  host.view.rerender(<VoicePanel client={{ close: host.client.close }} />);
  await act(async () => host.finish());
  expect(host.input.value).toBe("fixture-original");
});
