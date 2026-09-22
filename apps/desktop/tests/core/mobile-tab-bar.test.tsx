// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { SettingsPage, type HostCapabilities, type Snapshot } from "@msime/ui";

afterEach(cleanup);

const initial: Snapshot = {
  format_version: 1,
  revision: 1,
  preferences: {
    scheme: "quanpin",
    shuangpin_profile: "xiaohe",
    touch_keyboard_skin: "forest",
    candidate_page_size: 5,
    learning: true,
    chinese_punctuation: true,
  },
};

function mount() {
  render(
    <SettingsPage
      client={{
        load: async () => initial,
        save: vi.fn(),
        home: {},
        // The four tabs only exist where their pages do, and each page is gated on the capability
        // behind it. Harmony has all four.
        account: {} as never,
        typingStatistics: {} as never,
        communitySkins: {} as never,
        host: { platform: "harmony" } as HostCapabilities,
      }}
    />,
  );
}

/** The four the source shows, in its own words: 键盘 / 社区 / 统计 / 我的. */
const tabs = ["键盘", "社区", "统计", "我的"];

// The bar used to hold five cells, and the fifth was a `<select>` of thirteen page names — a form
// control sitting where a tab belongs, and the only way into most of the app. The source's bar is
// four tabs of an icon over a word and nothing else.
test("the phone tab bar is the source's four tabs, each an icon over a word", async () => {
  mount();
  await screen.findByRole("button", { name: "保存设置" });

  const bar = screen.getByRole("navigation", { name: "主要功能" });
  const buttons = [...bar.querySelectorAll("button")];
  expect(buttons.map((button) => button.textContent)).toEqual(tabs);
  expect(buttons.every((button) => button.querySelector("img"))).toBe(true);
  // The icons have to differ from one another, or the bar reads as four of the same thing.
  const sources = buttons.map((button) => button.querySelector("img")!.getAttribute("src"));
  expect(new Set(sources).size).toBe(tabs.length);
  expect(bar.querySelector("select")).toBeNull();
});

// The reason the `<select>` existed. Dropping it without giving those pages another door would have
// left most of the app unreachable on a phone, so this is the condition that has to hold instead:
// whatever the sidebar can reach, a phone can reach too, through a tab or through the 键盘 tab's own
// list. Asserted against the sidebar rather than a written-out list of names so that a page added
// later is covered without anyone remembering to come back here.
test("every page the sidebar reaches is reachable on a phone", async () => {
  mount();
  await screen.findByRole("button", { name: "保存设置" });

  const sidebar = screen.getByRole("navigation", { name: "设置分类" });
  const reachable = new Set(tabs);
  fireEvent.click(screen.getByRole("button", { name: /全部设置/ }));
  const list = screen.getByRole("region", { name: "全部设置" });
  for (const button of list.querySelectorAll("button")) {
    // The row is a title, a note and a chevron, so the title is the part to compare.
    reachable.add(button.querySelector("strong")?.textContent ?? "");
  }
  // The tabs carry the source's shorter words; the sidebar carries the page's own title.
  for (const title of ["首页", "打字统计"]) reachable.add(title);

  const stranded = [...sidebar.querySelectorAll("button")]
    .map((button) => button.textContent ?? "")
    .filter((title) => !reachable.has(title));
  expect(stranded).toEqual([]);
});

// Drilling into a page that has no tab does not leave the bar blank: the page was reached from the
// 键盘 tab, so the 键盘 tab is still where you are. The source keeps its first tab selected for
// everything its navigation stack pushes.
test("the 键盘 tab stays lit on the pages reached from it", async () => {
  mount();
  await screen.findByRole("button", { name: "保存设置" });

  const bar = screen.getByRole("navigation", { name: "主要功能" });
  const keyboard = within(bar).getByRole("button", { name: "键盘" });
  expect(keyboard.getAttribute("aria-current")).toBe("page");

  fireEvent.click(screen.getByRole("button", { name: /全部设置/ }));
  const list = screen.getByRole("region", { name: "全部设置" });
  const row = [...list.querySelectorAll("button")].find(
    (item) => item.querySelector("strong")?.textContent === "输入",
  )!;
  fireEvent.click(row);

  expect(within(bar).getByRole("button", { name: "键盘" }).getAttribute("aria-current")).toBe(
    "page",
  );
  expect(within(bar).getByRole("button", { name: "我的" }).getAttribute("aria-current")).toBeNull();
});
