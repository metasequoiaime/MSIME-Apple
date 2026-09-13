// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { SettingsPage, type DictionaryEntry, type Snapshot } from "@msime/ui";
// Not re-exported from the package root; take it from the module that owns it.
import { DICTIONARY_PAGE_SIZE } from "../../../packages/ui/src/dictionary-file";

afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const snapshot: Snapshot = {
  format_version: 1, revision: 3,
  preferences: { scheme: "quanpin", shuangpin_profile: "xiaohe", candidate_page_size: 5, learning: true, chinese_punctuation: true },
};

function entries(count: number): DictionaryEntry[] {
  return Array.from({ length: count }, (_, index) => ({
    kind: "quick_phrase" as const, key: `k${index}`, value: `短语${index}`, weight: 100,
  }));
}

/** A dictionary client whose pages always fill, so 下一页 stays enabled. */
function dictionaryClient(overrides: Record<string, unknown> = {}) {
  return {
    list: vi.fn().mockImplementation(async () => ({ entries: entries(DICTIONARY_PAGE_SIZE), has_more: true })),
    edit: vi.fn().mockResolvedValue(undefined),
    ...overrides,
  };
}

async function openDictionary(dictionary: ReturnType<typeof dictionaryClient>) {
  render(<SettingsPage client={{ load: async () => snapshot, save: vi.fn(), dictionary: dictionary as never }} />);
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "词库" }));
  // The page lists on demand rather than on open.
  fireEvent.click(await screen.findByRole("button", { name: "查询" }));
  // Wait for the rows themselves; the call resolving is not the same as a render.
  await screen.findAllByRole("button", { name: "删除" });
}

test("deleting an entry asks first and does nothing when declined", async () => {
  const confirm = vi.spyOn(window, "confirm").mockReturnValue(false);
  const dictionary = dictionaryClient();
  await openDictionary(dictionary);
  fireEvent.click(screen.getAllByRole("button", { name: "删除" })[0]);
  expect(confirm).toHaveBeenCalled();
  // Declining must not reach the host at all.
  expect(dictionary.edit).not.toHaveBeenCalled();
});

test("a confirmed delete reloads the page the user was reading", async () => {
  vi.spyOn(window, "confirm").mockReturnValue(true);
  const dictionary = dictionaryClient();
  await openDictionary(dictionary);
  // Move to the second page before deleting.
  fireEvent.click(screen.getByRole("button", { name: "下一页" }));
  await waitFor(() => expect(dictionary.list).toHaveBeenCalledTimes(2));
  expect(dictionary.list.mock.calls[1][0]).toBe(DICTIONARY_PAGE_SIZE);

  fireEvent.click(screen.getAllByRole("button", { name: "删除" })[0]);
  await waitFor(() => expect(dictionary.edit).toHaveBeenCalled());
  await waitFor(() => expect(dictionary.list).toHaveBeenCalledTimes(3));
  // Previously this reloaded at offset 0 and threw the reader back to page 1.
  expect(dictionary.list.mock.calls[2][0]).toBe(DICTIONARY_PAGE_SIZE);
});

test("deleting the only row on a later page steps back instead of showing nothing", async () => {
  vi.spyOn(window, "confirm").mockReturnValue(true);
  const dictionary = dictionaryClient({
    list: vi.fn().mockImplementation(async (offset: number) => (
      offset === 0
        ? { entries: entries(DICTIONARY_PAGE_SIZE), has_more: true }
        : { entries: entries(1), has_more: false }
    )),
  });
  await openDictionary(dictionary);
  fireEvent.click(screen.getByRole("button", { name: "下一页" }));
  await waitFor(() => expect(dictionary.list).toHaveBeenCalledTimes(2));

  fireEvent.click(screen.getAllByRole("button", { name: "删除" })[0]);
  await waitFor(() => expect(dictionary.list).toHaveBeenCalledTimes(3));
  expect(dictionary.list.mock.calls[2][0]).toBe(0);
});
