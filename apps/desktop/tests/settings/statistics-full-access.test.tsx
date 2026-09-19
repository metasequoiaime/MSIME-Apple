// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { TypingStatisticsPage, type TypingStatisticsStatus } from "@msime/ui";

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

const neverWritten: TypingStatisticsStatus = {
  availability: "neverWritten",
  statistics: { enabled: true, total: 0, days: {} },
};
const ready: TypingStatisticsStatus = {
  availability: "ready",
  statistics: { enabled: true, total: 0, days: {} },
};

function client(status: TypingStatisticsStatus) {
  return { load: async () => status, setEnabled: vi.fn(), reset: vi.fn() };
}

// Telling an iOS user to type more characters is advice that cannot work: without Full Access
// the extension never reaches the shared container, so the count stays at zero however much
// they type. The message has to name the prerequisite.
test("iOS names Full Access and offers the settings entry", async () => {
  const openSystemSettings = vi.fn(async () => {});
  render(
    <TypingStatisticsPage
      client={client(neverWritten)}
      platform="ios"
      openSystemSettings={openSystemSettings}
    />,
  );
  await screen.findByText(/键盘从未写入过统计/);

  expect(screen.getByText(/允许完全访问/)).toBeTruthy();
  fireEvent.click(screen.getByRole("button", { name: "打开系统键盘设置" }));
  expect(openSystemSettings).toHaveBeenCalled();
});

test("other platforms keep the plain guidance and no settings entry", async () => {
  render(
    <TypingStatisticsPage
      client={client(neverWritten)}
      platform="windows"
      openSystemSettings={vi.fn()}
    />,
  );
  await screen.findByText(/键盘从未写入过统计/);

  expect(screen.queryByText(/允许完全访问/)).toBeNull();
  expect(screen.queryByRole("button", { name: "打开系统键盘设置" })).toBeNull();
});

// A host that cannot open Settings must not render a dead button.
test("iOS without the settings capability still explains the requirement", async () => {
  render(<TypingStatisticsPage client={client(neverWritten)} platform="ios" />);
  await screen.findByText(/允许完全访问/);

  expect(screen.queryByRole("button", { name: "打开系统键盘设置" })).toBeNull();
});

// Full Access is only the explanation for "never written". Once the file exists, a zero count
// means something else, and pointing at Settings would send the user somewhere useless.
test("an established statistics file does not blame Full Access", async () => {
  render(
    <TypingStatisticsPage client={client(ready)} platform="ios" openSystemSettings={vi.fn()} />,
  );
  await screen.findByText(/统计文件已建立/);

  expect(screen.queryByText(/允许完全访问/)).toBeNull();
  expect(screen.queryByRole("button", { name: "打开系统键盘设置" })).toBeNull();
});
