// @vitest-environment jsdom
import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { KeyboardPanel } from "@msime/ui";

afterEach(() => {
  cleanup();
  vi.useRealTimers();
});

test("pointer hold repeats ordinary keys after the native delay and stops on release", async () => {
  vi.useFakeTimers();
  const sendKey = vi.fn().mockResolvedValue(undefined);
  render(<KeyboardPanel client={{ close: async () => {}, sendKey }} platform="macos" />);
  const key = screen.getByRole("button", { name: "a" });

  await act(async () => {
    fireEvent.pointerDown(key, { button: 0, isPrimary: true, pointerId: 1 });
    await Promise.resolve();
  });
  expect(sendKey).toHaveBeenCalledTimes(1);

  await act(async () => {
    vi.advanceTimersByTime(449);
    await Promise.resolve();
  });
  expect(sendKey).toHaveBeenCalledTimes(1);

  await act(async () => {
    vi.advanceTimersByTime(151);
    await Promise.resolve();
  });
  expect(sendKey).toHaveBeenCalledTimes(4);

  fireEvent.pointerUp(key, { button: 0, isPrimary: true, pointerId: 1 });
  await act(async () => {
    vi.advanceTimersByTime(300);
    await Promise.resolve();
  });
  expect(sendKey).toHaveBeenCalledTimes(4);
});

test("modifier holds toggle only on activation and keyboard clicks remain single-shot", async () => {
  vi.useFakeTimers();
  const sendKey = vi.fn().mockResolvedValue(undefined);
  render(<KeyboardPanel client={{ close: async () => {}, sendKey }} platform="macos" />);
  const shift = screen.getAllByRole("button", { name: "Shift" })[0];

  fireEvent.pointerDown(shift, { button: 0, isPrimary: true, pointerId: 2 });
  await act(async () => {
    vi.advanceTimersByTime(900);
    await Promise.resolve();
  });
  expect(shift.getAttribute("aria-pressed")).toBe("false");
  fireEvent.click(shift, { detail: 1 });
  expect(shift.getAttribute("aria-pressed")).toBe("true");

  const letter = screen.getByRole("button", { name: "A" });
  await act(async () => {
    fireEvent.click(letter, { detail: 0 });
    await Promise.resolve();
  });
  expect(sendKey).toHaveBeenCalledTimes(1);
  expect(sendKey).toHaveBeenCalledWith(expect.objectContaining({ virtual_key: 0x41, shift: true }));
});
