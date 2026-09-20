// @vitest-environment jsdom
import { afterEach, expect, test } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";
import {
  TypingStatisticsPage,
  type TypingStatistics,
  type TypingStatisticsStatus,
} from "@msime/ui";

afterEach(cleanup);

function today(): string {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
}

function client(statistics: TypingStatistics) {
  const status: TypingStatisticsStatus = { statistics, availability: "ready" };
  return {
    load: () => Promise.resolve(status),
    setEnabled: () => Promise.resolve(status),
    reset: () => Promise.resolve(status),
  };
}

test("the rhythm cards read the measured activity", async () => {
  const key = today();
  const hours = Array.from({ length: 24 }, (_, hour) => (hour === 9 ? 360 : 0));
  render(
    <TypingStatisticsPage
      client={client({
        enabled: true,
        total: 360,
        days: { [key]: 360 },
        dailyDetails: { [key]: { characters: { han: 360 } } },
        dailyActiveMs: { [key]: 120_000 },
        dailyHours: { [key]: hours },
      })}
    />,
  );
  // 360 characters over two active minutes.
  expect((await screen.findByLabelText("今日输入速度")).textContent).toContain("180");
  expect(screen.getByLabelText("平均输入速度").textContent).toContain("180");
  expect(screen.getByLabelText("今日活跃时长").textContent).toContain("2分");
  expect(screen.getByLabelText("连续输入天数").textContent).toContain("1");
  expect(screen.getByLabelText("今日各时段输入分布")).toBeTruthy();
  expect(screen.getByLabelText("9 时，360 字符")).toBeTruthy();
});

test("a document with no measured activity says so instead of showing a zero speed", async () => {
  const key = today();
  render(
    <TypingStatisticsPage client={client({ enabled: true, total: 120, days: { [key]: 120 } })} />,
  );
  expect((await screen.findByLabelText("今日输入速度")).textContent).toContain("0");
  // Nothing has ever timed typing here, which is different from typing at zero speed.
  expect(screen.getByText(/还没有测量到活跃时长/)).toBeTruthy();
  // No hours recorded, so the section is absent rather than drawn empty.
  expect(screen.queryByLabelText("今日各时段输入分布")).toBeNull();
});
