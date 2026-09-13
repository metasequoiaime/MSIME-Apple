// @vitest-environment jsdom
import { expect, test } from "vitest";
import { emojiDisplayName } from "@msime/ui";

test("a tooltip is a short name, not the whole keyword blob", () => {
  // Keywords are a space-separated blob; showing all of it is noise.
  expect(emojiDisplayName("grinning face smile happy 笑 高兴 开心")).toBe("笑");
  // Prefers the first CJK token wherever it sits.
  expect(emojiDisplayName("thumbs up 赞")).toBe("赞");
  // With no CJK it falls back to the first token rather than the blob.
  expect(emojiDisplayName("alpha beta gamma")).toBe("alpha");
});

test("an item with no usable keywords falls back to its own text", () => {
  // Symbol keywords often default to the category name or are missing; the
  // glyph itself is a better tooltip than an empty one.
  expect(emojiDisplayName("", "±")).toBe("±");
  expect(emojiDisplayName(undefined, "±")).toBe("±");
  expect(emojiDisplayName("   ", "±")).toBe("±");
  expect(emojiDisplayName("")).toBe("");
});

test("extra whitespace between keywords is tolerated", () => {
  expect(emojiDisplayName("  grinning   face  笑  ")).toBe("笑");
  expect(emojiDisplayName("\n\tsmile\t\n")).toBe("smile");
});
