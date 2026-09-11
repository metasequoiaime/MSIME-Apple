import { expect, test, vi } from "vitest";
import { subscribeWindowState, type WindowStateSource } from "./window-state";

function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason: Error) => void;
  const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

function host() {
  let resize = () => {};
  const unlisten = vi.fn();
  const source = {
    isMaximized: vi.fn<WindowStateSource["isMaximized"]>().mockResolvedValue(false),
    onResized: vi.fn<WindowStateSource["onResized"]>().mockImplementation(async listener => {
      resize = listener;
      return unlisten;
    }),
  };
  return { source, unlisten, resize: () => resize() };
}

test("registers before reading and cleans up exactly once", async () => {
  const { source, unlisten } = host();
  const listener = vi.fn();
  source.isMaximized.mockImplementation(async () => {
    expect(source.onResized).toHaveBeenCalledTimes(1);
    return true;
  });
  const dispose = await subscribeWindowState(source, listener);
  expect(listener).toHaveBeenCalledExactlyOnceWith(true);
  dispose(); dispose();
  expect(unlisten).toHaveBeenCalledTimes(1);
});

test("a resize during initial read supersedes the old initial state", async () => {
  const { source, resize } = host();
  const first = deferred<boolean>();
  source.isMaximized.mockReturnValueOnce(first.promise).mockResolvedValueOnce(true);
  const listener = vi.fn();
  const subscription = subscribeWindowState(source, listener);
  await Promise.resolve();
  resize();
  await Promise.resolve();
  first.resolve(false);
  const dispose = await subscription;
  expect(listener).toHaveBeenCalledExactlyOnceWith(true);
  dispose();
});

test("out-of-order resize reads cannot overwrite newer state", async () => {
  const { source, resize } = host();
  const listener = vi.fn();
  const dispose = await subscribeWindowState(source, listener);
  listener.mockClear();
  const first = deferred<boolean>();
  const second = deferred<boolean>();
  source.isMaximized.mockReturnValueOnce(first.promise).mockReturnValueOnce(second.promise);
  resize(); resize();
  second.resolve(false);
  await Promise.resolve();
  first.resolve(true);
  await Promise.resolve();
  expect(listener).toHaveBeenCalledExactlyOnceWith(false);
  dispose();
});

test("dispose silences in-flight results and late events", async () => {
  const { source, resize, unlisten } = host();
  const listener = vi.fn();
  const onError = vi.fn();
  const dispose = await subscribeWindowState(source, listener, onError);
  listener.mockClear();
  const pending = deferred<boolean>();
  source.isMaximized.mockReturnValueOnce(pending.promise);
  resize();
  dispose();
  pending.reject(new Error("closed"));
  await Promise.resolve();
  resize();
  expect(source.isMaximized).toHaveBeenCalledTimes(2);
  expect(listener).not.toHaveBeenCalled();
  expect(onError).not.toHaveBeenCalled();
  expect(unlisten).toHaveBeenCalledTimes(1);
});

test("initial read failure removes the listener and rejects setup", async () => {
  const { source, unlisten } = host();
  source.isMaximized.mockRejectedValueOnce(new Error("unavailable"));
  await expect(subscribeWindowState(source, vi.fn())).rejects.toThrow("unavailable");
  expect(unlisten).toHaveBeenCalledTimes(1);
});

test("subscription failure does not read window state", async () => {
  const { source } = host();
  source.onResized.mockRejectedValueOnce(new Error("unavailable"));
  await expect(subscribeWindowState(source, vi.fn())).rejects.toThrow("unavailable");
  expect(source.isMaximized).not.toHaveBeenCalled();
});

test("current read failures report once and later events can recover", async () => {
  const { source, resize } = host();
  const listener = vi.fn();
  const onError = vi.fn();
  const dispose = await subscribeWindowState(source, listener, onError);
  source.isMaximized.mockRejectedValueOnce(new Error("unavailable"));
  resize();
  await Promise.resolve();
  expect(onError).toHaveBeenCalledTimes(1);
  source.isMaximized.mockResolvedValueOnce(true);
  resize();
  await Promise.resolve();
  expect(listener).toHaveBeenLastCalledWith(true);
  dispose();
});

test("obsolete read failures do not report errors for a newer successful state", async () => {
  const { source, resize } = host();
  const onError = vi.fn();
  const listener = vi.fn();
  const dispose = await subscribeWindowState(source, listener, onError);
  const pending = deferred<boolean>();
  source.isMaximized.mockReturnValueOnce(pending.promise).mockResolvedValueOnce(true);
  resize(); resize();
  await Promise.resolve();
  pending.reject(new Error("obsolete"));
  await Promise.resolve();
  expect(onError).not.toHaveBeenCalled();
  expect(listener).toHaveBeenLastCalledWith(true);
  dispose();
});
