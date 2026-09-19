// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { EmojiPanel } from "@msime/ui";

afterEach(() => {
  cleanup();
  localStorage.clear();
});

test("emoji panel restores persisted recent items", () => {
  localStorage.setItem("msime.emoji.recent", JSON.stringify([{ text: "⚙", keywords: "gear" }]));
  render(<EmojiPanel client={{ close: async () => {} }} />);
  expect(screen.getByRole("button", { name: "最近使用" })).toBeDefined();
});

test("emoji panel ignores malformed recent storage", () => {
  localStorage.setItem("msime.emoji.recent", "not json");
  render(<EmojiPanel client={{ close: async () => {} }} />);
  expect(screen.queryByRole("button", { name: "⚙" })).toBeNull();
});

test("emoji panel paginates catalog items and resets on search", async () => {
  const items = Array.from({ length: 60 }, (_, index) => ({
    text: `😀${index}`,
    keywords: `item${index}`,
  }));
  const client = {
    close: async () => {},
    loadCatalog: async () => ({
      emoji: [{ title: "All", icon: "😀", items }],
      kaomoji: [],
      symbols: [],
    }),
  };
  render(<EmojiPanel client={client} />);
  fireEvent.click(await screen.findByRole("button", { name: "Emoji" }));
  await waitFor(() => expect(screen.getByText("第 1 / 2 页")).toBeDefined());
  fireEvent.click(screen.getByRole("button", { name: "下一页" }));
  await waitFor(() => expect(screen.getByText("第 2 / 2 页")).toBeDefined());
  fireEvent.change(screen.getByRole("textbox", { name: "搜索" }), { target: { value: "item0" } });
  await waitFor(() => expect(screen.queryByText("第 2 / 2 页")).toBeNull());
});

test("clipboard panel exposes host paste and keeps copy separate", async () => {
  const paste = vi.fn().mockResolvedValue(undefined);
  const copyText = vi.fn().mockResolvedValue(undefined);
  render(
    <EmojiPanel
      client={{
        close: async () => {},
        copyText,
        clipboard: { list: async () => ["synthetic clipboard entry"], paste },
      }}
    />,
  );

  fireEvent.click(screen.getByRole("button", { name: "剪贴板" }));
  expect(await screen.findByText("synthetic clipboard entry")).toBeDefined();
  fireEvent.click(screen.getByRole("button", { name: "粘贴此条记录到原应用" }));
  await waitFor(() => expect(paste).toHaveBeenCalledWith("synthetic clipboard entry"));
  expect(copyText).not.toHaveBeenCalled();
});
