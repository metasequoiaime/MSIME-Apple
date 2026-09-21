// @vitest-environment jsdom
import { expect, test } from "vitest";
import { decodeDictionaryBytes } from "@msime/ui";

const row = "你好\tni'hao\n";

function utf8(text: string): Uint8Array {
  return new TextEncoder().encode(text);
}

test("a byte-order mark is an envelope marker, not the first word", () => {
  expect(decodeDictionaryBytes(utf8(`﻿${row}`))).toBe(row);
});

test("UTF-16 dictionaries decode instead of turning into NULs", () => {
  const units = Array.from(`﻿${row}`, (character) => character.charCodeAt(0));
  const little = new Uint8Array(units.flatMap((unit) => [unit & 0xff, unit >> 8]));
  const big = new Uint8Array(units.flatMap((unit) => [unit >> 8, unit & 0xff]));
  expect(decodeDictionaryBytes(little)).toBe(row);
  expect(decodeDictionaryBytes(big)).toBe(row);
});

test("GB18030 dictionaries decode instead of becoming replacement characters", () => {
  // "你好\tni'hao\n" as GB18030, which is what Windows tools still write.
  const bytes = new Uint8Array([
    0xc4, 0xe3, 0xba, 0xc3, 0x09, 0x6e, 0x69, 0x27, 0x68, 0x61, 0x6f, 0x0a,
  ]);
  // Decoded as UTF-8 these become U+FFFD and - this is the part that mattered - contain no NUL,
  // so a reader that only guards against NUL accepts a file of replacement characters.
  const asUtf8 = new TextDecoder("utf-8").decode(bytes);
  expect(asUtf8).toContain("�");
  expect(asUtf8.includes("\u0000")).toBe(false);
  expect(decodeDictionaryBytes(bytes)).toBe(row);
});

test("plain UTF-8 is unchanged", () => {
  expect(decodeDictionaryBytes(utf8(row))).toBe(row);
});
