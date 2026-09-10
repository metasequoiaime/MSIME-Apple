// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { SettingsPage, type SettingsClient, type Snapshot } from "@msime/ui";

afterEach(cleanup);

test("frequency values above the upstream dropdown range remain visible", async () => {
  const snapshot: Snapshot = { ...initial, preferences: { ...initial.preferences, frequency: { mode: "halve", trigger_count: 10, linear_step: 7 } } };
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(snapshot), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...snapshot, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  const trigger = await screen.findByLabelText("触发频次(第几次上屏触发)") as HTMLSelectElement;
  expect(trigger.value).toBe("10");
  expect((screen.getByLabelText("线性调频步长") as HTMLSelectElement).value).toBe("7");
  fireEvent.change(screen.getByRole("combobox", { name: "调频方式" }), { target: { value: "pin" } });
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...snapshot.preferences, frequency: { mode: "pin", trigger_count: 10, linear_step: 7 } });
});

test("frequency modes, threshold and step persist independently", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  const mode = await screen.findByRole("combobox", { name: "调频方式" }) as HTMLSelectElement;
  expect(mode.value).toBe("promote");
  expect(Array.from(mode.options, option => option.value)).toEqual(["disabled", "pin", "halve", "linear", "promote"]);
  fireEvent.change(mode, { target: { value: "linear" } });
  fireEvent.change(screen.getByLabelText("触发频次(第几次上屏触发)"), { target: { value: "3" } });
  fireEvent.change(screen.getByLabelText("线性调频步长"), { target: { value: "2" } });
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, frequency: { mode: "linear", trigger_count: 3, linear_step: 2 } });
});

test("frequency settings remain editable independently of learning and mode", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn() };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  const learning = await screen.findByRole("checkbox", { name: /学习选词习惯/ }) as HTMLInputElement;
  const mode = screen.getByRole("combobox", { name: "调频方式" }) as HTMLSelectElement;
  const trigger = screen.getByLabelText("触发频次(第几次上屏触发)") as HTMLSelectElement;
  const step = screen.getByLabelText("线性调频步长") as HTMLSelectElement;
  expect(step.disabled).toBe(false);
  fireEvent.change(mode, { target: { value: "linear" } });
  expect(step.disabled).toBe(false);
  fireEvent.click(learning);
  expect(mode.disabled).toBe(false);
  expect(trigger.disabled).toBe(false);
  expect(step.disabled).toBe(false);
  fireEvent.change(mode, { target: { value: "disabled" } });
  expect(mode.value).toBe("disabled");
  expect(step.disabled).toBe(false);
});

test("word-to-character and paging disable each other while preserving the chosen keys", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  const word = await screen.findByRole("checkbox", { name: /以词定字/ }) as HTMLInputElement;
  const minus = screen.getByRole("radio", { name: "- / =" }) as HTMLInputElement;
  expect(word.checked).toBe(false);
  expect(minus.disabled).toBe(true);
  fireEvent.click(word);
  fireEvent.click(screen.getByRole("checkbox", { name: "[ / ]" }));
  expect(word.checked).toBe(false);
  fireEvent.click(word);
  expect((screen.getByRole("checkbox", { name: "[ / ]" }) as HTMLInputElement).checked).toBe(false);
  fireEvent.click(screen.getByRole("checkbox", { name: "- / =" }));
  expect(minus.disabled).toBe(false);
  fireEvent.click(minus);
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences,
    word_character: { enabled: true, keys: "minus_equal" },
    navigation: { minus_equal: false, comma_period: true, brackets: false, tab: true, page_up_down: true, arrows: true } });
});

test("paging defaults match Windows and individual edits persist", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  const brackets = await screen.findByRole("checkbox", { name: "[ / ]" }) as HTMLInputElement;
  expect(brackets.checked).toBe(false);
  for (const name of ["- / =", ", / .", "Shift+Tab / Tab", "PageUp / PageDown", "上 / 下（移动候选项）"]) {
    expect((screen.getByRole("checkbox", { name }) as HTMLInputElement).checked).toBe(true);
  }
  fireEvent.click(brackets);
  fireEvent.click(screen.getByRole("checkbox", { name: "Shift+Tab / Tab" }));
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, navigation: { minus_equal: true, comma_period: true, brackets: true, tab: false, page_up_down: true, arrows: true } });
});

test("helpcode schemes save independently and retain disabled selections", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "辅助码" }));
  const quanpin = await screen.findByLabelText("全拼辅助码方案") as HTMLSelectElement;
  expect(quanpin.value).toBe("ziranma");
  expect(quanpin.options.length).toBe(5);
  fireEvent.change(quanpin, { target: { value: "xiaohe" } });
  fireEvent.click(screen.getByRole("checkbox", { name: "全拼辅助码" }));
  expect(quanpin.disabled).toBe(true);
  expect(quanpin.value).toBe("xiaohe");
  fireEvent.change(screen.getByLabelText("双拼辅助码方案"), { target: { value: "shouyou2_0" } });
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences,
    quanpin_helpcode: { enabled: false, schema: "xiaohe" },
    shuangpin_helpcode: { enabled: true, schema: "shouyou2_0" } });
});
const initial: Snapshot = { format_version: 1, revision: 7, preferences: { scheme: "quanpin", shuangpin_profile: "xiaohe", candidate_page_size: 5, learning: true, chinese_punctuation: true } };

test("saves a shuangpin profile and retains it when switching schemes", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  await screen.findByRole("radio", { name: "全拼" });
  expect(screen.getByRole("combobox", { name: "双拼方案" })).toBeDefined();
  fireEvent.click(screen.getByRole("radio", { name: "双拼" }));
  const profile = screen.getByRole("combobox", { name: "双拼方案" }) as HTMLSelectElement;
  fireEvent.change(profile, { target: { value: "microsoft" } });
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, scheme: "shuangpin", last_chinese_scheme: "shuangpin", shuangpin_profile: "microsoft" });
  fireEvent.click(screen.getByRole("radio", { name: "全拼" }));
  expect(screen.getByRole("combobox", { name: "双拼方案" })).toBeDefined();
  expect(profile.value).toBe("microsoft");
});

test.each([['quanpin', '全拼'], ['shuangpin', '双拼'], ['wubi', '五笔']] as const)("Japanese mode retains %s across save and reload", async (scheme, label) => {
  let stored: Snapshot = { ...initial, preferences: { ...initial.preferences, scheme } };
  const client: SettingsClient = { load: vi.fn(async () => stored), save: vi.fn(async (revision, preferences) => (stored = { ...stored, revision: revision + 1, preferences })) };
  const mounted = render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  await screen.findByRole("radio", { name: label });
  fireEvent.click(screen.getByRole("radio", { name: "日文" }));
  expect(screen.queryByRole("radio", { name: label })).toBeNull();
  expect((screen.getByRole("radio", { name: "罗马字" }) as HTMLInputElement).checked).toBe(true);
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(stored.preferences.scheme).toBe("japanese");
  expect(stored.preferences.last_chinese_scheme).toBe(scheme);
  mounted.unmount();
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  await screen.findByRole("radio", { name: "罗马字" });
  fireEvent.click(screen.getByRole("radio", { name: "中文" }));
  expect((screen.getByRole("radio", { name: label }) as HTMLInputElement).checked).toBe(true);
  expect(screen.queryByRole("radio", { name: "罗马字" })).toBeNull();
});

test("saves edited preferences against the loaded revision", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  const size = await screen.findByLabelText("每页候选数量");
  fireEvent.change(size, { target: { value: "9" } });
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, candidate_page_size: 9 });
  expect((screen.getByRole("button", { name: "保存设置" }) as HTMLButtonElement).disabled).toBe(true);
});

test("conflicts preserve edits and require an explicit reload", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockRejectedValue({ code: "conflict" }) };
  render(<SettingsPage client={client} />);
  const size = await screen.findByLabelText("每页候选数量");
  fireEvent.change(size, { target: { value: "9" } });
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  expect((await screen.findByRole("alert")).textContent).toContain("其他窗口");
  expect((size as HTMLSelectElement).value).toBe("9");
  expect(client.load).toHaveBeenCalledTimes(1);
  const confirm = vi.spyOn(window, "confirm").mockReturnValue(true);
  fireEvent.click(screen.getByRole("button", { name: "重新读取" }));
  await waitFor(() => expect((size as HTMLSelectElement).value).toBe("5"));
  confirm.mockRestore();
});

test("failed initial load never enables saving fabricated defaults", async () => {
  const client: SettingsClient = { load: vi.fn().mockRejectedValue({ code: "format" }), save: vi.fn() };
  render(<SettingsPage client={client} />);
  await screen.findByRole("alert");
  expect(screen.queryByRole("button", { name: "保存设置" })).toBeNull();
  expect(client.save).not.toHaveBeenCalled();
});

test("legacy autocorrect defaults on and can be saved off", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  const control = await screen.findByRole("checkbox", { name: /全拼纠错/ }) as HTMLInputElement;
  expect(control.checked).toBe(true);
  fireEvent.click(control);
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, autocorrect: false });
  expect(control.checked).toBe(false);
});

test("category navigation preserves one draft and saves edits across pages", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  const appearance = screen.getByRole("button", { name: "外观" });
  expect(appearance.getAttribute("aria-current")).toBe("page");
  fireEvent.change(await screen.findByLabelText("每页候选数量"), { target: { value: "9" } });
  fireEvent.click(screen.getByRole("button", { name: "辅助码" }));
  expect(screen.getByRole("heading", { level: 1 }).textContent).toBe("辅助码");
  expect(screen.queryByRole("combobox", { name: "每页候选数量" })).toBeNull();
  fireEvent.click(screen.getByRole("checkbox", { name: "全拼辅助码" }));
  fireEvent.click(appearance);
  expect((screen.getByRole("combobox", { name: "每页候选数量" }) as HTMLSelectElement).value).toBe("9");
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, candidate_page_size: 9, quanpin_helpcode: { enabled: false, schema: "ziranma" } });
  expect(client.load).toHaveBeenCalledTimes(1);
});
