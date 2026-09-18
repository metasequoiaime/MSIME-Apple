// @vitest-environment jsdom
import { expect, test } from "vitest";
import { dictionaryErrorMessage } from "@msime/ui";

const FALLBACK = "全拼保存失败，请稍后重试。";

test("the three actionable host reasons no longer read identically", () => {
  const busy = dictionaryErrorMessage({ code: "dictionary_busy" }, FALLBACK);
  const rejected = dictionaryErrorMessage({ code: "dictionary_import_rejected" }, FALLBACK);
  const unavailable = dictionaryErrorMessage({ code: "dictionary_unavailable" }, FALLBACK);
  for (const message of [busy, rejected, unavailable]) {
    expect(message).not.toBe(FALLBACK);
  }
  expect(new Set([busy, rejected, unavailable]).size).toBe(3);
});

test("a locked dictionary tells the user what to close, not to retry", () => {
  // This was the worst case: the IME being held by another process read as
  // "please retry later", which never becomes true on its own.
  const message = dictionaryErrorMessage({ code: "dictionary_busy" }, FALLBACK);
  expect(message).toContain("关闭");
  expect(message).not.toContain("稍后重试。");
});

test("the remaining host reasons are distinguished too", () => {
  expect(dictionaryErrorMessage({ code: "dictionary_read_rejected" }, FALLBACK)).toContain("读取");
  expect(dictionaryErrorMessage({ code: "dictionary_pinyin_unavailable" }, FALLBACK)).toContain("拼音表");
});

test("an unknown or absent code keeps the caller's sentence", () => {
  expect(dictionaryErrorMessage({ code: "storage" }, FALLBACK)).toBe(FALLBACK);
  expect(dictionaryErrorMessage({}, FALLBACK)).toBe(FALLBACK);
  expect(dictionaryErrorMessage(undefined, FALLBACK)).toBe(FALLBACK);
  expect(dictionaryErrorMessage(new Error("boom"), FALLBACK)).toBe(FALLBACK);
  expect(dictionaryErrorMessage("boom", FALLBACK)).toBe(FALLBACK);
});
