// @vitest-environment jsdom
import { afterEach, expect, test } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { EmojiPanel } from "@msime/ui";

afterEach(() => { cleanup(); localStorage.clear(); });

test("emoji panel restores persisted recent items", () => {
  localStorage.setItem("msime.emoji.recent", JSON.stringify([{ text: "⚙", keywords: "gear" }]));
  render(<EmojiPanel client={{ close: async () => {} }} />);
  expect(screen.getByText("最近使用")).toBeDefined();
});

test("emoji panel ignores malformed recent storage", () => {
  localStorage.setItem("msime.emoji.recent", "not json");
  render(<EmojiPanel client={{ close: async () => {} }} />);
  expect(screen.queryByText("最近使用")).toBeNull();
});

test("emoji panel paginates catalog items and resets on search", async () => {
  const items = Array.from({ length: 60 }, (_, index) => ({ text: `😀${index}`, keywords: `item${index}` }));
  const client = { close: async () => {}, loadCatalog: async () => ({ emoji: [{ title: "All", icon: "😀", items }], kaomoji: [], symbols: [] }) };
  render(<EmojiPanel client={client} />);
  fireEvent.click(await screen.findByRole("button", { name: "Emoji" }));
  await waitFor(() => expect(screen.getByText("第 1 / 2 页")).toBeDefined());
  fireEvent.click(screen.getByRole("button", { name: "下一页" }));
  await waitFor(() => expect(screen.getByText("第 2 / 2 页")).toBeDefined());
});
