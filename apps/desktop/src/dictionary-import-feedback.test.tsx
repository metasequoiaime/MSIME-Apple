// @vitest-environment jsdom
import { afterEach, describe, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { SettingsPage, describeImportResult, type Snapshot } from "@msime/ui";

afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const snapshot: Snapshot = {
  format_version: 1, revision: 2,
  preferences: { scheme: "quanpin", shuangpin_profile: "xiaohe", candidate_page_size: 5, learning: true, chinese_punctuation: true },
};

describe("describeImportResult", () => {
  test("a clean import states the count only", () => {
    const message = describeImportResult("快捷短语", { applied: 12 });
    expect(message).toContain("12");
    expect(message).not.toContain("跳过");
    expect(message).not.toContain("过长");
  });

  test("skipped rows are counted and the first line numbers named", () => {
    const message = describeImportResult("全拼", {
      applied: 8, failed: 3, first_failures: [{ line: 2, issue: "column_count" }, { line: 9, issue: "key_alphabet" }],
    });
    expect(message).toContain("8");
    expect(message).toContain("跳过 3 行");
    expect(message).toContain("2、9");
  });

  test("a truncated import says so", () => {
    expect(describeImportResult("五笔", { applied: 1000, truncated: true })).toContain("过长");
  });

  test("a host without the report degrades to the count", () => {
    // Older hosts return {applied} only; the message must not invent failures.
    const message = describeImportResult("英文", { applied: 5 });
    expect(message).toContain("5");
    expect(message).not.toContain("跳过");
  });
});

async function importFile(dictionary: Record<string, unknown>) {
  render(<SettingsPage client={{ load: async () => snapshot, save: vi.fn(), dictionary: dictionary as never }} />);
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "词库" }));
  const input = document.querySelector('input[type="file"]') as HTMLInputElement;
  const file = new File(["你好\tni'hao\n"], "dict.txt", { type: "text/plain" });
  Object.defineProperty(input, "files", { value: [file] });
  fireEvent.change(input);
}

test("an import that skipped rows reports them instead of looking clean", async () => {
  const dictionary = {
    list: vi.fn().mockResolvedValue({ entries: [], has_more: false }),
    edit: vi.fn(),
    import: vi.fn().mockResolvedValue({ applied: 2, failed: 1, first_failures: [{ line: 2, issue: "column_count" }] }),
  };
  await importFile(dictionary);
  await waitFor(() => expect(dictionary.import).toHaveBeenCalled());
  const notice = await screen.findByRole("status");
  expect(notice.textContent).toContain("跳过 1 行");
  expect(notice.textContent).toContain("第 2 行");
});

test("a failed import surfaces the host's reason rather than a generic hint", async () => {
  const dictionary = {
    list: vi.fn().mockResolvedValue({ entries: [], has_more: false }),
    edit: vi.fn(),
    import: vi.fn().mockRejectedValue(new Error("dictionary import is too large")),
  };
  await importFile(dictionary);
  const alert = await screen.findByRole("alert");
  expect(alert.textContent).toContain("dictionary import is too large");
});

test("an engine rejection is explained differently from a malformed line", () => {
  // These parse cleanly but the engine refuses them, so "check the text
  // format" would send the user looking in the wrong place.
  const message = describeImportResult("全拼", {
    applied: 40, failed: 2,
    first_failures: [{ line: 7, issue: "rejected" }, { line: 12, issue: "rejected" }],
  });
  expect(message).toContain("40");
  expect(message).toContain("跳过 2 行");
  expect(message).toContain("7、12");
  expect(message).toContain("音节");

  // A purely malformed file keeps the original wording.
  const malformed = describeImportResult("全拼", {
    applied: 3, failed: 1, first_failures: [{ line: 2, issue: "column_count" }],
  });
  expect(malformed).not.toContain("音节");
});
