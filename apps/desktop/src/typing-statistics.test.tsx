// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { SettingsPage, type SettingsClient, type Snapshot, type TypingStatistics, type TypingStatisticsStatus } from "@msime/ui";

afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const preferences: Snapshot = {
  format_version: 1,
  revision: 1,
  preferences: { scheme: "quanpin", shuangpin_profile: "xiaohe", candidate_page_size: 5, learning: true, chinese_punctuation: true },
};

function key(offset: number): string {
  const now = new Date();
  const date = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  date.setDate(date.getDate() + offset);
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

function label(offset: number): string {
  const now = new Date();
  const date = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  date.setDate(date.getDate() + offset);
  return `${date.getMonth() + 1}月${date.getDate()}日`;
}

const initialStatistics: TypingStatistics = {
  enabled: true,
  total: 23,
  days: { [key(0)]: 4, [key(-1)]: 6, [key(-8)]: 10 },
  detail: {
    characters: { han: 4, latin: 6, emoji: 10 },
    sources: { quanpin: 4, english: 6, ai: 10 },
  },
  dailyDetails: {
    [key(0)]: { characters: { han: 4 }, sources: { quanpin: 4 } },
    [key(-1)]: { characters: { latin: 6 }, sources: { english: 6 } },
    [key(-8)]: { characters: { emoji: 10 }, sources: { ai: 10 } },
  },
};

function status(statistics: TypingStatistics = initialStatistics): TypingStatisticsStatus {
  return { statistics, availability: "ready", lastWrittenMs: Date.now() };
}

function baseClient(): SettingsClient {
  return { load: async () => preferences, save: vi.fn() };
}

test("desktop settings omit typing statistics without the Android capability", async () => {
  render(<SettingsPage client={baseClient()} />);
  await screen.findByRole("button", { name: "保存设置" });
  expect(screen.queryByRole("button", { name: "打字统计" })).toBeNull();
});

test("statistics capability provides 7 day, 30 day, cumulative and selected-day scopes", async () => {
  const typingStatistics = { load: vi.fn().mockResolvedValue(status()), setEnabled: vi.fn(), reset: vi.fn() };
  render(<SettingsPage client={{ ...baseClient(), typingStatistics }} />);
  fireEvent.click(await screen.findByRole("button", { name: "打字统计" }));
  expect((await screen.findByLabelText("当前范围输入字符数")).textContent).toBe("10");
  expect(screen.queryByRole("button", { name: "保存设置" })).toBeNull();
  expect(screen.queryByRole("button", { name: "重新读取" })).toBeNull();

  fireEvent.click(screen.getByRole("button", { name: "30 天" }));
  expect(screen.getByLabelText("当前范围输入字符数").textContent).toBe("20");
  fireEvent.click(screen.getByRole("button", { name: "累计" }));
  expect(screen.getByLabelText("当前范围输入字符数").textContent).toBe("23");
  expect(screen.getAllByLabelText(/历史未分类 3 字符/).length).toBeGreaterThanOrEqual(2);

  fireEvent.click(screen.getByRole("button", { name: `${label(0)}，4 字符` }));
  const selectedTotal = screen.getByLabelText("当前范围输入字符数");
  expect(selectedTotal.textContent).toBe("4");
  expect(selectedTotal.parentElement?.querySelector("span")?.textContent).toBe(label(0));
  expect(screen.getByLabelText(/汉字 4 字符/)).not.toBeNull();
  expect(screen.queryByText("private fixture text")).toBeNull();
});

test("statistics toggle refreshes immediately and reset requires confirmation without re-enabling", async () => {
  const disabled = { ...initialStatistics, enabled: false };
  const cleared: TypingStatistics = { enabled: false, total: 0, days: {}, detail: { characters: {}, sources: {} }, dailyDetails: {} };
  const typingStatistics = {
    load: vi.fn().mockResolvedValue(status()),
    setEnabled: vi.fn().mockResolvedValue(status(disabled)),
    reset: vi.fn().mockResolvedValue(status(cleared)),
  };
  render(<SettingsPage client={{ ...baseClient(), typingStatistics }} />);
  fireEvent.click(await screen.findByRole("button", { name: "打字统计" }));
  const toggle = await screen.findByRole("checkbox", { name: "记录打字统计" });
  fireEvent.click(toggle);
  await waitFor(() => expect(typingStatistics.setEnabled).toHaveBeenCalledWith(false));
  await waitFor(() => expect((toggle as HTMLInputElement).checked).toBe(false));

  vi.spyOn(window, "confirm").mockReturnValueOnce(false).mockReturnValueOnce(true);
  fireEvent.click(screen.getByRole("button", { name: "清空统计" }));
  expect(typingStatistics.reset).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole("button", { name: "清空统计" }));
  await waitFor(() => expect(typingStatistics.reset).toHaveBeenCalledTimes(1));
  await waitFor(() => expect(screen.getByLabelText("当前范围输入字符数").textContent).toBe("0"));
  expect((toggle as HTMLInputElement).checked).toBe(false);
});

test("never-written status explains the empty local-only data channel", async () => {
  const empty: TypingStatistics = { enabled: true, total: 0, days: {} };
  const typingStatistics = { load: vi.fn().mockResolvedValue({ ...status(empty), availability: "neverWritten" as const, lastWrittenMs: null }), setEnabled: vi.fn(), reset: vi.fn() };
  render(<SettingsPage client={{ ...baseClient(), typingStatistics }} />);
  fireEvent.click(await screen.findByRole("button", { name: "打字统计" }));
  expect(await screen.findByText(/键盘从未写入过统计/)).not.toBeNull();
  expect(screen.getByText(/不保存输入内容/)).not.toBeNull();
});
