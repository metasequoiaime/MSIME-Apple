// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import {
  TypingStatisticsPage,
  retentionChoices,
  type TypingStatistics,
  type TypingStatisticsStatus,
} from "@msime/ui";

afterEach(cleanup);

function status(statistics: TypingStatistics): TypingStatisticsStatus {
  return { statistics, availability: "ready" };
}

test("the cleanup window is offered with the reference's choices and saved on selection", async () => {
  const value: TypingStatistics = {
    enabled: true,
    total: 10,
    days: { "2026-09-21": 10 },
    retention: "forever",
  };
  const setRetention = vi.fn(async (retention: string) =>
    status({ ...value, retention: retention as TypingStatistics["retention"] }),
  );
  render(
    <TypingStatisticsPage
      client={{
        load: async () => status(value),
        setEnabled: async () => status(value),
        setRetention,
        reset: async () => status(value),
      }}
    />,
  );

  const control = (await screen.findByLabelText("自动清理")) as HTMLSelectElement;
  expect(Array.from(control.options).map((option) => [option.value, option.textContent])).toEqual(
    retentionChoices,
  );
  // An unset window shows as "keep everything", which is what it means.
  expect(control.value).toBe("forever");

  fireEvent.change(control, { target: { value: "90d" } });
  await waitFor(() => expect(setRetention).toHaveBeenCalledWith("90d"));
});

test("statistics written before cleanup existed read as keeping everything", async () => {
  const value: TypingStatistics = { enabled: true, total: 10, days: { "2026-09-21": 10 } };
  render(
    <TypingStatisticsPage
      client={{
        load: async () => status(value),
        setEnabled: async () => status(value),
        setRetention: async () => status(value),
        reset: async () => status(value),
      }}
    />,
  );
  expect(((await screen.findByLabelText("自动清理")) as HTMLSelectElement).value).toBe("forever");
});

test("a host that does not keep the statistics is not offered the control", async () => {
  const value: TypingStatistics = { enabled: true, total: 10, days: { "2026-09-21": 10 } };
  render(
    <TypingStatisticsPage
      client={{
        load: async () => status(value),
        setEnabled: async () => status(value),
        reset: async () => status(value),
      }}
    />,
  );
  // The toggle is there, so the page has rendered its controls.
  await screen.findByLabelText("记录打字统计");
  // A dead control that silently does nothing would be worse than no control.
  expect(screen.queryByLabelText("自动清理")).toBeNull();
});
