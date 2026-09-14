// @vitest-environment jsdom
import { expect, test } from "vitest";
import { dictionaryExportName, dictionaryExportPayload } from "@msime/ui";

test("each dictionary kind exports under its own shipped name", () => {
  expect(dictionaryExportName("pinyin")).toBe("水杉IME-拼音用户词库.txt");
  expect(dictionaryExportName("wubi")).toBe("水杉IME-五笔用户词库.txt");
  expect(dictionaryExportName("english")).toBe("水杉IME-英文用户词库.txt");
  expect(dictionaryExportName("quick_phrase")).toBe("水杉IME-快捷短语用户词库.txt");
  // The old single generic name said nothing about which book it held.
  expect(new Set(["pinyin", "wubi", "english", "quick_phrase"].map(k => dictionaryExportName(k as never))).size).toBe(4);
});

test("the payload starts with a UTF-8 BOM", () => {
  // Without it Notepad and Excel on a GBK-default Windows show mojibake.
  const { body } = dictionaryExportPayload("wubi", "standard", "你好\twq\t9\n");
  expect(body.charCodeAt(0)).toBe(0xfeff);
  expect(body).toContain("你好\twq\t9");
  expect(body.endsWith("\n")).toBe(true);
});

test("single-character pinyin rows are dropped as learning artefacts", () => {
  const text = "你好\tni'hao\t9\n的\tde\t99\n世界\tshi'jie\t8\n";
  const { body, rows } = dictionaryExportPayload("pinyin", "standard", text);
  expect(rows).toBe(2);
  expect(body).toContain("你好");
  expect(body).toContain("世界");
  expect(body).not.toContain("\t de");
  expect(body.split("\n").filter(Boolean).some(l => l.startsWith("的"))).toBe(false);
});

test("the word column follows the format, so windows exports are not misread", () => {
  // Windows puts the code first. Reading column 0 there would measure the
  // pinyin, and "de" is two characters, so the row would wrongly survive.
  const windows = "de\t的\t99\nni'hao\t你好\t9\n";
  const { rows, body } = dictionaryExportPayload("pinyin", "windows", windows);
  expect(rows).toBe(1);
  expect(body).toContain("你好");
  expect(body).not.toContain("的");
});

test("other kinds keep their single-character rows", () => {
  // Only the pinyin book accumulates learning artefacts; a one-character quick
  // phrase or wubi entry is a real entry the user made.
  const text = "好\thao\t9\n";
  expect(dictionaryExportPayload("wubi", "standard", text).rows).toBe(1);
  expect(dictionaryExportPayload("quick_phrase", "standard", text).rows).toBe(1);
  expect(dictionaryExportPayload("english", "standard", text).rows).toBe(1);
});

test("an empty result reports nothing to export rather than downloading a blank file", () => {
  expect(dictionaryExportPayload("pinyin", "standard", "").rows).toBe(0);
  expect(dictionaryExportPayload("pinyin", "standard", "\n  \n").rows).toBe(0);
  // A pinyin book holding only single characters is also nothing to export.
  expect(dictionaryExportPayload("pinyin", "standard", "的\tde\t99\n").rows).toBe(0);
  expect(dictionaryExportPayload("pinyin", "standard", "").body).toBe("");
});
