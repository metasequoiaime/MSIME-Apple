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

test("Caps Lock and Shift invert letters while commit keys drop sticky modifiers", async () => {
  const sendKey = vi.fn().mockResolvedValue(undefined);
  render(<KeyboardPanel client={{ close: async () => {}, sendKey }} platform="windows" />);

  fireEvent.click(screen.getByRole("button", { name: "Caps Lock" }));
  const upper = screen.getByRole("button", { name: "A" });
  fireEvent.click(upper);
  expect(sendKey).toHaveBeenLastCalledWith(
    expect.objectContaining({ virtual_key: 0x41, shift: true }),
  );

  fireEvent.click(screen.getAllByRole("button", { name: "Shift" })[0]);
  const lower = screen.getByRole("button", { name: "a" });
  fireEvent.click(lower);
  expect(sendKey).toHaveBeenLastCalledWith(
    expect.objectContaining({ virtual_key: 0x41, shift: false }),
  );

  fireEvent.click(screen.getByRole("button", { name: "Ctrl" }));
  fireEvent.click(screen.getByRole("button", { name: "Enter" }));
  expect(sendKey).toHaveBeenLastCalledWith(
    expect.objectContaining({
      virtual_key: 0x0d,
      include_sticky_modifiers: false,
    }),
  );
});

test("Linux stops held-key retries after delivery failure and does not repeat Num Lock", async () => {
  vi.useFakeTimers();
  const sendKey = vi
    .fn()
    .mockResolvedValueOnce(undefined)
    .mockRejectedValueOnce(new Error("synthetic"));
  render(<KeyboardPanel client={{ close: async () => {}, sendKey }} platform="linux" />);
  const key = screen.getByRole("button", { name: "a" });
  fireEvent.pointerDown(key, { button: 0, isPrimary: true, pointerId: 3 });
  expect(sendKey).toHaveBeenCalledTimes(1);
  await act(async () => {
    vi.advanceTimersByTime(450);
    await Promise.resolve();
  });
  expect(sendKey).toHaveBeenCalledTimes(2);
  expect(screen.getByRole("status").textContent).toContain("后续排队按键已取消");
  await act(async () => {
    vi.advanceTimersByTime(600);
    await Promise.resolve();
  });
  expect(sendKey).toHaveBeenCalledTimes(2);

  const numLock = screen.getByRole("button", { name: "Num Lock" });
  fireEvent.pointerDown(numLock, { button: 0, isPrimary: true, pointerId: 4 });
  fireEvent.click(numLock, { detail: 1 });
  await act(async () => {
    vi.advanceTimersByTime(900);
    await Promise.resolve();
  });
  expect(sendKey).toHaveBeenCalledTimes(3);
});
