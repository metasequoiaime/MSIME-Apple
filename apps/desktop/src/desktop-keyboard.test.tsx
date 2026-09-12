// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { act, cleanup, render, screen, waitFor } from "@testing-library/react";
import type { Snapshot } from "@msime/ui";
import { DesktopKeyboard } from "./desktop-keyboard";

afterEach(() => { cleanup(); vi.unstubAllGlobals(); });
const snapshot = (revision: number, theme: "light" | "dark" | "system", surface: "follow" | "light" | "dark" = "follow"): Snapshot => ({
  format_version: 1, revision, preferences: { scheme: "quanpin", shuangpin_profile: "xiaohe", candidate_page_size: 6, learning: true, chinese_punctuation: true, theme, screen_keyboard_theme: surface },
});
const panel = { close: async () => {} };
const theme = () => screen.getByRole("main", { name: "屏幕键盘" }).getAttribute("data-keyboard-theme");

test("keyboard subscribes before load and rejects stale snapshots without remounting", async () => {
  let emit!: (value: Snapshot) => void;
  let resolve!: (value: Snapshot) => void;
  const stop = vi.fn();
  const order: string[] = [];
  const rememberInputTarget = vi.fn().mockResolvedValue(undefined);
  const preferences = {
    onPreferencesChanged: async (listener: typeof emit) => { order.push("subscribe"); emit = listener; return stop; },
    load: () => { order.push("load"); return new Promise<Snapshot>(done => { resolve = done; }); },
  };
  const view = render(<DesktopKeyboard client={{ ...panel, rememberInputTarget }} preferences={preferences} />);
  await waitFor(() => expect(order).toEqual(["subscribe", "load"]));
  act(() => emit(snapshot(3, "dark", "light")));
  expect(theme()).toBe("light");
  await act(async () => resolve(snapshot(2, "dark")));
  expect(theme()).toBe("light");
  act(() => emit(snapshot(1, "dark")));
  expect(theme()).toBe("light");
  act(() => emit(snapshot(4, "light", "dark")));
  expect(theme()).toBe("dark");
  expect(rememberInputTarget).toHaveBeenCalledTimes(1);
  view.unmount();
  expect(stop).toHaveBeenCalledTimes(1);
});

test("late subscription is cleaned up and never loads after unmount", async () => {
  let finish!: (stop: () => void) => void;
  const load = vi.fn();
  const view = render(<DesktopKeyboard client={panel} preferences={{ load, onPreferencesChanged: () => new Promise(done => { finish = done; }) }} />);
  view.unmount();
  const stop = vi.fn();
  await act(async () => finish(stop));
  expect(stop).toHaveBeenCalledOnce();
  expect(load).not.toHaveBeenCalled();
});

test("keyboard follows system changes and loads despite subscription failure", async () => {
  let change!: () => void;
  const media = { matches: true, addEventListener: vi.fn((_name, listener) => { change = listener; }), removeEventListener: vi.fn() };
  vi.stubGlobal("matchMedia", () => media);
  const view = render(<DesktopKeyboard client={panel} preferences={{ load: async () => snapshot(1, "system"), onPreferencesChanged: async () => { throw new Error("synthetic"); } }} />);
  await waitFor(() => expect(theme()).toBe("light"));
  act(() => { media.matches = false; change(); });
  expect(theme()).toBe("dark");
  view.unmount();
  expect(media.removeEventListener).toHaveBeenCalledWith("change", change);
});

test("failed initial load retains default dark theme", async () => {
  const load = vi.fn().mockRejectedValue(new Error("synthetic"));
  render(<DesktopKeyboard client={panel} preferences={{ load }} />);
  await waitFor(() => expect(load).toHaveBeenCalledOnce());
  expect(theme()).toBe("dark");
});
