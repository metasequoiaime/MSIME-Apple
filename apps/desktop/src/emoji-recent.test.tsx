// @vitest-environment jsdom
import { afterEach, expect, test } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";
import { EmojiPanel } from "@msime/ui";

afterEach(() => { cleanup(); localStorage.clear(); });

test("emoji panel restores persisted recent items", () => {
  localStorage.setItem("msime.emoji.recent", JSON.stringify([{ text: "⚙", keywords: "gear" }]));
  render(<EmojiPanel client={{ close: async () => {} }} />);
  expect(screen.getByText("Recently used")).toBeDefined();
});

test("emoji panel ignores malformed recent storage", () => {
  localStorage.setItem("msime.emoji.recent", "not json");
  render(<EmojiPanel client={{ close: async () => {} }} />);
  expect(screen.queryByText("Recently used")).toBeNull();
});
