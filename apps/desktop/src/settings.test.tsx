// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { SettingsPage, type SettingsClient, type Snapshot } from "@msime/ui";

afterEach(cleanup);

test("candidate fallback fonts parse in order and persist", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  const fallback = await screen.findByLabelText("候选窗补充字体") as HTMLInputElement;
  expect(fallback.value).toBe("");
  for (const character of "Noto Sans CJK SC, Segoe UI Emoji,  ") {
    const next = fallback.value + character;
    fireEvent.change(fallback, { target: { value: next } });
    expect(fallback.value).toBe(next);
  }
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, candidate_fallback_fonts: ["Noto Sans CJK SC", "Segoe UI Emoji"] });
  expect(fallback.value).toBe("Noto Sans CJK SC, Segoe UI Emoji,  ");
  fireEvent.click(screen.getByRole("button", { name: "重新读取" }));
  await waitFor(() => expect(fallback.value).toBe(""));
});

test("candidate text color follows theme by default and can be reset", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  const color = await screen.findByLabelText("候选文字颜色") as HTMLInputElement;
  expect(color.value).toBe("#ffffff");
  fireEvent.change(color, { target: { value: "#123456" } });
  fireEvent.click(screen.getByRole("button", { name: "跟随主题" }));
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, candidate_text_color: null });
});

test("candidate preview follows the selected layout", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn() };
  render(<SettingsPage client={client} />);
  const preview = await screen.findByLabelText("候选窗口预览");
  expect(preview.querySelector(".candidate-preview-vertical")).not.toBeNull();
  fireEvent.click(screen.getByRole("button", { name: "纵向" }));
  fireEvent.click(screen.getByRole("option", { name: "横向" }));
  expect(preview.querySelector(".candidate-preview-horizontal")).not.toBeNull();
  expect(preview.querySelector(".candidate-preview-vertical")).toBeNull();
});

test("candidate preedit style persists", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(await screen.findByRole("button", { name: /拼音分词/ }));
  fireEvent.click(screen.getAllByRole("option", { name: "不显示" })[0]);
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, candidate_preedit_style: "empty" });
});

test("candidate preview hides preedit when disabled", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue({ ...initial, preferences: { ...initial.preferences, candidate_preedit_style: "empty" } }), save: vi.fn() };
  render(<SettingsPage client={client} />);
  const preview = await screen.findByLabelText("候选窗口预览");
  expect(preview.querySelector(".candidate-preview-preedit")).toBeNull();
});

test("candidate font size defaults to 16 and persists selected size", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  const font = await screen.findByRole("button", { name: "候选窗字号" });
  expect(font.textContent).toContain("16");
  fireEvent.click(font);
  fireEvent.click(screen.getByRole("option", { name: "24" }));
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, candidate_font_size: 24 });
});

test("candidate preview reflects candidate and preedit font sizes", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn() };
  render(<SettingsPage client={client} />);
  const preview = await screen.findByLabelText("候选窗口预览");
  expect((preview.querySelector(".candidate-preview-card") as HTMLElement).style.fontSize).toBe("16px");
  expect((preview.querySelector(".candidate-preview-preedit") as HTMLElement).style.fontSize).toBe("16px");
  fireEvent.click(screen.getByRole("button", { name: "候选窗字号" }));
  fireEvent.click(screen.getByRole("option", { name: "24" }));
  fireEvent.click(screen.getByRole("button", { name: "候选窗预编辑字号" }));
  fireEvent.click(screen.getByRole("option", { name: "20" }));
  expect((preview.querySelector(".candidate-preview-card") as HTMLElement).style.fontSize).toBe("24px");
  expect((preview.querySelector(".candidate-preview-preedit") as HTMLElement).style.fontSize).toBe("20px");
});

test("theme settings use custom dropdowns and persist", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(await screen.findByRole("button", { name: "主题模式" }));
  fireEvent.click(screen.getByRole("option", { name: "浅色" }));
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, theme: "light" });
});

test("shortcut page reflects enabled navigation shortcuts", async () => {
  render(<SettingsPage client={{ load: vi.fn().mockResolvedValue(initial), save: vi.fn() }} />);
  fireEvent.click(screen.getByRole("button", { name: "快捷键" }));
  expect(await screen.findByText("候选操作")).toBeDefined();
  expect(screen.getAllByText("- / =").length).toBeGreaterThan(0);
  expect(screen.getByText("↑ / ↓")).toBeDefined();
});

test("dictionary page exposes the quick phrase manager", async () => {
  const client: SettingsClient = {
    load: vi.fn().mockResolvedValue(initial),
    save: vi.fn(),
    dictionary: { list: vi.fn().mockResolvedValue({ entries: [], has_more: false }), edit: vi.fn() },
  };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "词库" }));
  expect(await screen.findByRole("region", { name: "快捷短语管理" })).toBeDefined();
  expect(screen.getByText("查询、新增、编辑、导入、导出和删除 Engine 用户词库中的快捷短语")).toBeDefined();
});

test("wubi scheme uses the custom dropdown control", async () => {
  render(<SettingsPage client={{ load: vi.fn().mockResolvedValue(initial), save: vi.fn() }} />);
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  expect((await screen.findByRole("button", { name: "五笔方案" })).textContent).toContain("86 五笔");
});

test("skin page selects and persists candidate theme", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "皮肤" }));
  const dark = (await screen.findAllByRole("radio", { name: /深色/ }))[0];
  fireEvent.click(dark);
  expect(dark.getAttribute("aria-checked")).toBe("true");
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, candidate_theme: "dark" });
});

test("inline preedit style uses the custom dropdown and persists", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(await screen.findByRole("button", { name: "行内预编辑" }));
  fireEvent.click(screen.getAllByRole("option", { name: "拼音分词" })[0]);
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, tsf_preedit_style: "pinyin" });
});


test("utility mode switches preserve defaults and drafts across pages", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "实用功能" }));
  const unicode = await screen.findByRole("checkbox", { name: /^Unicode 便捷录入/ }) as HTMLInputElement;
  expect(unicode.checked).toBe(true);
  fireEvent.click(unicode);
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  fireEvent.click(screen.getByRole("button", { name: "实用功能" }));
  expect(unicode.checked).toBe(false);
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, local_modes: { unicode: false, date_time: true, quick_phrase: true, emoji: true, kaomoji: true, super_jianpin: true, temporary_english: true, temporary_japanese: true } });
});

test("mixed candidate defaults, independent switches and threshold persist", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  const english = await screen.findByRole("checkbox", { name: /^中英混输/ }) as HTMLInputElement;
  const emoji = screen.getByRole("checkbox", { name: /^emoji 混输/ }) as HTMLInputElement;
  const kaomoji = screen.getByRole("checkbox", { name: /^颜文字混输/ }) as HTMLInputElement;
  const threshold = screen.getByRole("button", { name: "触发字符数" }) as HTMLButtonElement;
  expect(english.checked).toBe(true);
  expect(emoji.checked).toBe(false);
  expect(kaomoji.checked).toBe(false);
  expect(threshold.textContent).toContain("2");
  fireEvent.click(threshold);
  fireEvent.click(screen.getByRole("option", { name: "8" }));
  fireEvent.click(english);
  expect(threshold.disabled).toBe(true);
  expect(threshold.textContent).toContain("8");
  fireEvent.click(emoji);
  fireEvent.click(kaomoji);
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, mixed_input: { english: false, minimum_prefix: 8, emoji: true, kaomoji: true } });
});

test("frequency values above the upstream dropdown range remain visible", async () => {
  const snapshot: Snapshot = { ...initial, preferences: { ...initial.preferences, frequency: { mode: "halve", trigger_count: 10, linear_step: 7 } } };
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(snapshot), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...snapshot, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  const trigger = await screen.findByRole("button", { name: "触发频次(第几次上屏触发)" });
  expect(trigger.textContent).toContain("10");
  expect(screen.getByRole("button", { name: "线性调频步长" }).textContent).toContain("7");
  fireEvent.click(screen.getByRole("button", { name: "调频方式" }));
  fireEvent.click(screen.getByRole("option", { name: "一次置顶" }));
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...snapshot.preferences, frequency: { mode: "pin", trigger_count: 10, linear_step: 7 } });
});

test("frequency modes, threshold and step persist independently", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  const mode = await screen.findByRole("button", { name: "调频方式" });
  expect(mode.textContent).toContain("一次置前");
  fireEvent.click(mode);
  fireEvent.click(screen.getByRole("option", { name: "线性调频" }));
  fireEvent.click(screen.getByRole("button", { name: "触发频次(第几次上屏触发)" }));
  fireEvent.click(screen.getByRole("option", { name: "3" }));
  fireEvent.click(screen.getByRole("button", { name: "线性调频步长" }));
  fireEvent.click(screen.getByRole("option", { name: "2" }));
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, frequency: { mode: "linear", trigger_count: 3, linear_step: 2 } });
});

test("frequency settings remain editable independently of learning and mode", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn() };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  const learning = await screen.findByRole("checkbox", { name: /学习选词习惯/ }) as HTMLInputElement;
  const mode = screen.getByRole("button", { name: "调频方式" });
  const trigger = screen.getByRole("button", { name: "触发频次(第几次上屏触发)" });
  const step = screen.getByRole("button", { name: "线性调频步长" });
  fireEvent.click(mode);
  fireEvent.click(screen.getByRole("option", { name: "线性调频" }));
  fireEvent.click(learning);
  expect(mode).toBeDefined();
  expect(trigger).toBeDefined();
  expect(step).toBeDefined();
  fireEvent.click(mode);
  fireEvent.click(screen.getByRole("option", { name: "关闭" }));
  expect(mode.textContent).toContain("关闭");
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
  const quanpin = await screen.findByRole("button", { name: "全拼辅助码方案" }) as HTMLButtonElement;
  expect(quanpin.textContent).toContain("自然码");
  fireEvent.click(quanpin);
  fireEvent.click(screen.getByRole("option", { name: "小鹤" }));
  fireEvent.click(screen.getByRole("checkbox", { name: "全拼辅助码" }));
  expect(quanpin.disabled).toBe(true);
  expect(quanpin.textContent).toContain("小鹤");
  fireEvent.click(screen.getByRole("button", { name: "双拼辅助码方案" }));
  fireEvent.click(screen.getByRole("option", { name: "首右2.0" }));
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
  expect(screen.getByRole("button", { name: "双拼方案" })).toBeDefined();
  fireEvent.click(screen.getByRole("radio", { name: "双拼" }));
  const profile = screen.getByRole("button", { name: "双拼方案" }) as HTMLButtonElement;
  fireEvent.click(profile);
  fireEvent.click(screen.getByRole("option", { name: "微软双拼" }));
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, scheme: "shuangpin", last_chinese_scheme: "shuangpin", shuangpin_profile: "microsoft" });
  fireEvent.click(screen.getByRole("radio", { name: "全拼" }));
  expect(screen.getByRole("button", { name: "双拼方案" })).toBeDefined();
  expect(profile.textContent).toContain("微软双拼");
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
  const size = await screen.findByRole("button", { name: "每页候选数量" });
  fireEvent.click(size);
  fireEvent.click(screen.getByRole("option", { name: "9" }));
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, candidate_page_size: 9 });
  expect((screen.getByRole("button", { name: "保存设置" }) as HTMLButtonElement).disabled).toBe(true);
});

test("conflicts preserve edits and require an explicit reload", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockRejectedValue({ code: "conflict" }) };
  render(<SettingsPage client={client} />);
  const size = await screen.findByRole("button", { name: "每页候选数量" });
  fireEvent.click(size);
  fireEvent.click(screen.getByRole("option", { name: "9" }));
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  expect((await screen.findByRole("alert")).textContent).toContain("其他窗口");
  expect(size.textContent).toContain("9");
  expect(client.load).toHaveBeenCalledTimes(1);
  const confirm = vi.spyOn(window, "confirm").mockReturnValue(true);
  fireEvent.click(screen.getByRole("button", { name: "重新读取" }));
  await waitFor(() => expect(size.textContent).toContain("5"));
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
  const pageSize = await screen.findByRole("button", { name: "每页候选数量" });
  fireEvent.click(pageSize);
  fireEvent.click(screen.getByRole("option", { name: "9" }));
  fireEvent.click(screen.getByRole("button", { name: "辅助码" }));
  expect(screen.getByRole("heading", { level: 1 }).textContent).toBe("辅助码");
  expect(screen.queryByRole("button", { name: "每页候选数量" })).toBeNull();
  fireEvent.click(screen.getByRole("checkbox", { name: "全拼辅助码" }));
  fireEvent.click(appearance);
  expect(screen.getByRole("button", { name: "每页候选数量" }).textContent).toContain("9");
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, candidate_page_size: 9, quanpin_helpcode: { enabled: false, schema: "ziranma" } });
  expect(client.load).toHaveBeenCalledTimes(1);
});
