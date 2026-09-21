import { expect, test } from "vitest";
import {
  activityMetrics,
  addDays,
  currentStreak,
  formatActiveTime,
  longestStreak,
  type TypingStatistics,
} from "@msime/ui";

function statistics(overrides: Partial<TypingStatistics> = {}): TypingStatistics {
  return { enabled: true, total: 0, days: {}, ...overrides };
}

test("day arithmetic crosses months, years and leap days without a calendar library", () => {
  expect(addDays("2026-09-21", 1)).toBe("2026-09-22");
  expect(addDays("2026-09-01", -1)).toBe("2026-08-31");
  expect(addDays("2026-01-01", -1)).toBe("2025-12-31");
  expect(addDays("2026-12-31", 1)).toBe("2027-01-01");
  // 2028 is a leap year and 2026 is not, so the day after 2 February differs between them.
  expect(addDays("2028-02-28", 1)).toBe("2028-02-29");
  expect(addDays("2026-02-28", 1)).toBe("2026-03-01");
  // A key that is not a date is returned unchanged rather than becoming "NaN-NaN-NaN".
  expect(addDays("not-a-day", 1)).toBe("not-a-day");
});

test("today still in progress does not break a streak", () => {
  const recorded = ["2026-09-18", "2026-09-19", "2026-09-20"];
  // Nothing typed today yet: the run ending yesterday is the current streak.
  expect(currentStreak(recorded, "2026-09-21")).toBe(3);
  // Typing today extends it.
  expect(currentStreak([...recorded, "2026-09-21"], "2026-09-21")).toBe(4);
  // A missing yesterday ends it, whatever came before.
  expect(currentStreak(recorded, "2026-09-22")).toBe(0);
  expect(currentStreak([], "2026-09-21")).toBe(0);
});

test("longest streak counts the longest run, not the last one", () => {
  expect(longestStreak(["2026-09-01", "2026-09-02", "2026-09-03", "2026-09-10"])).toBe(3);
  expect(longestStreak(["2026-09-01", "2026-09-03", "2026-09-05"])).toBe(1);
  expect(longestStreak(["2026-09-01"])).toBe(1);
  expect(longestStreak([])).toBe(0);
  // Across a month boundary, which a naive numeric comparison of the keys would miss.
  expect(longestStreak(["2026-08-30", "2026-08-31", "2026-09-01"])).toBe(3);
});

test("speed counts readable characters per active minute", () => {
  const value = statistics({
    total: 600,
    days: { "2026-09-21": 600 },
    dailyDetails: {
      "2026-09-21": {
        characters: { han: 200, latin: 100, otherLetter: 60, number: 100, punctuation: 140 },
      },
    },
    dailyActiveMs: { "2026-09-21": 120_000 },
  });
  const metrics = activityMetrics(value, "2026-09-21");
  // 360 readable characters over two active minutes. Digits and punctuation stay out: a phone
  // number typed quickly is not prose and would read as a burst of speed.
  expect(metrics.todaySpeed).toBe(180);
  expect(metrics.averageSpeed).toBe(180);
  expect(metrics.todayActiveMs).toBe(120_000);
  expect(metrics.hasActivity).toBe(true);
});

test("kana count toward speed, unlike the Windows baseline", () => {
  const value = statistics({
    total: 60,
    days: { "2026-09-21": 60 },
    dailyDetails: { "2026-09-21": { characters: { otherLetter: 60 } } },
    dailyActiveMs: { "2026-09-21": 60_000 },
  });
  // The baseline files kana under "other" and would report a Japanese-only day as zero speed.
  expect(activityMetrics(value, "2026-09-21").todaySpeed).toBe(60);
});

test("days that predate the measurement are unknown rather than instant", () => {
  const value = statistics({
    total: 500,
    days: { "2026-09-19": 200, "2026-09-20": 300 },
    dailyDetails: { "2026-09-20": { characters: { han: 300 } } },
    // Only one of the two days was measured.
    dailyActiveMs: { "2026-09-20": 60_000 },
  });
  const metrics = activityMetrics(value, "2026-09-21");
  // The unmeasured day contributes neither characters nor time to the average; including it as
  // zero time would divide by zero, and including its characters would inflate the rate.
  expect(metrics.averageSpeed).toBe(300);
  expect(metrics.totalActiveMs).toBe(60_000);
  // It still counts as a recorded day for the per-day average and the streaks.
  expect(metrics.recordedDays).toBe(2);
  expect(metrics.averagePerDay).toBe(250);
  expect(metrics.currentStreak).toBe(2);
});

test("a day too short to mean anything cannot win fastest", () => {
  const value = statistics({
    total: 120,
    days: { "2026-09-19": 20, "2026-09-20": 100 },
    dailyDetails: {
      "2026-09-19": { characters: { han: 20 } },
      "2026-09-20": { characters: { han: 100 } },
    },
    // Twenty characters in two seconds is 600/min and would top the ranking forever.
    dailyActiveMs: { "2026-09-19": 2_000, "2026-09-20": 120_000 },
  });
  const metrics = activityMetrics(value, "2026-09-21");
  expect(metrics.fastestDay).toBe("2026-09-20");
  expect(metrics.fastestSpeed).toBe(50);
  // The short day is still part of the average, which is a ratio of totals rather than a ranking.
  expect(metrics.averageSpeed).toBeCloseTo((120 / 122_000) * 60_000, 6);
});

test("the best day is the one with the most characters, earliest on a tie", () => {
  const value = statistics({
    total: 300,
    days: { "2026-09-19": 150, "2026-09-20": 100, "2026-09-21": 150 },
  });
  const metrics = activityMetrics(value, "2026-09-21");
  expect(metrics.bestDay).toBe("2026-09-19");
  expect(metrics.bestDayCharacters).toBe(150);
});

test("an empty document derives zeroes rather than NaN", () => {
  const metrics = activityMetrics(statistics(), "2026-09-21");
  expect(metrics).toMatchObject({
    recordedDays: 0,
    averagePerDay: 0,
    todaySpeed: 0,
    averageSpeed: 0,
    fastestSpeed: 0,
    fastestDay: null,
    currentStreak: 0,
    longestStreak: 0,
    bestDay: null,
    todayHours: null,
    hasActivity: false,
  });
});

test("hourly buckets are only used when they describe a whole day", () => {
  const hours = Array.from({ length: 24 }, (_, hour) => (hour === 9 ? 42 : 0));
  expect(
    activityMetrics(
      statistics({ total: 42, days: { "2026-09-21": 42 }, dailyHours: { "2026-09-21": hours } }),
      "2026-09-21",
    ).todayHours,
  ).toEqual(hours);
  // A truncated list is dropped rather than padded: padding would silently move the missing
  // hours' typing to midnight.
  expect(
    activityMetrics(
      statistics({ total: 42, days: { "2026-09-21": 42 }, dailyHours: { "2026-09-21": [42, 0] } }),
      "2026-09-21",
    ).todayHours,
  ).toBeNull();
  // Yesterday's buckets are not today's.
  expect(
    activityMetrics(
      statistics({ total: 42, days: { "2026-09-20": 42 }, dailyHours: { "2026-09-20": hours } }),
      "2026-09-21",
    ).todayHours,
  ).toBeNull();
});

test("active time reads as a duration rather than milliseconds", () => {
  expect(formatActiveTime(0)).toBe("0分");
  expect(formatActiveTime(-1)).toBe("0分");
  expect(formatActiveTime(45_000)).toBe("45秒");
  expect(formatActiveTime(12 * 60_000)).toBe("12分");
  expect(formatActiveTime(60 * 60_000)).toBe("1小时");
  expect(formatActiveTime(83 * 60_000)).toBe("1小时23分");
});
