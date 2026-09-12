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

test("emoji panel paginates catalog items and resets on search", async () => {
  const items = Array.from({ length: 60 }, (_, index) => ({ text: `😀${index}`, keywords: `item${index}` }));
  const client = { close: async () => {}, loadCatalog: async () => ({ emoji: [{ title: "All", icon: "😀", items }], kaomoji: [], symbols: [] }) };
  render(<EmojiPanel client={client} />);
  (await screen.findByRole("button", { name: "Emoji" })).click();
  expect(screen.getByText("第 1 / 2 页")).toBeDefined();
  screen.getByRole("button", { name: "下一页" }).click();
  expect(screen.getByText("第 2 / 2 页")).toBeDefined();
  screen.getByRole("textbox", { name: "搜索" }).dispatchEvent(new Event("input", { bubbles: true }));
});
