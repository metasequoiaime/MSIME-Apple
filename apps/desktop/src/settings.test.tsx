// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { EmojiPanel, HandwritingPanel, KeyboardPanel, SettingsPage, type SettingsClient, type Snapshot } from "@msime/ui";

afterEach(cleanup);

test("mixed candidate defaults, independent switches and threshold persist", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  const english = await screen.findByRole("checkbox", { name: /^中英混输/ }) as HTMLInputElement;
  const emoji = screen.getByRole("checkbox", { name: /^emoji 混输/ }) as HTMLInputElement;
  const kaomoji = screen.getByRole("checkbox", { name: /^颜文字混输/ }) as HTMLInputElement;
  const threshold = screen.getByLabelText("触发字符数") as HTMLSelectElement;
  expect(english.checked).toBe(true);
  expect(emoji.checked).toBe(false);
  expect(kaomoji.checked).toBe(false);
  expect(threshold.value).toBe("2");
  expect(threshold.options.length).toBe(8);
  fireEvent.change(threshold, { target: { value: "8" } });
  fireEvent.click(english);
  expect(threshold.disabled).toBe(true);
  expect(threshold.value).toBe("8");
  fireEvent.click(emoji);
  fireEvent.click(kaomoji);
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, mixed_input: { english: false, minimum_prefix: 8, emoji: true, kaomoji: true } });
});

test("traditional Chinese output toggle persists", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  const toggle = await screen.findByRole("checkbox", { name: "繁体中文输出" }) as HTMLInputElement;
  expect(toggle.checked).toBe(false);
  fireEvent.click(toggle);
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, traditional_chinese_output: true });
});

test("frequency values above the upstream dropdown range remain visible", async () => {
  const snapshot: Snapshot = { ...initial, preferences: { ...initial.preferences, frequency: { mode: "halve", trigger_count: 10, linear_step: 7 } } };
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(snapshot), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...snapshot, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  const trigger = await screen.findByRole("combobox", { name: "触发频次(第几次上屏触发)" });
  expect(trigger.textContent).toContain("10");
  expect(screen.getByRole("combobox", { name: "线性调频步长" }).textContent).toContain("7");
  fireEvent.change(screen.getByRole("combobox", { name: "调频方式" }), { target: { value: "pin" } });
  fireEvent.click(screen.getByRole("option", { name: "一次置顶" }));
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...snapshot.preferences, frequency: { mode: "pin", trigger_count: 10, linear_step: 7 } });
});

test("frequency modes, threshold and step persist independently", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  const mode = await screen.findByRole("combobox", { name: "调频方式" });
  expect(mode.textContent).toContain("一次置前");
  fireEvent.change(mode, { target: { value: "linear" } });
  fireEvent.change(screen.getByRole("combobox", { name: "触发频次(第几次上屏触发)" }), { target: { value: "3" } });
  fireEvent.change(screen.getByRole("combobox", { name: "线性调频步长" }), { target: { value: "2" } });
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, frequency: { mode: "linear", trigger_count: 3, linear_step: 2 } });
});

test("frequency settings remain editable independently of learning and mode", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn() };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  const learning = await screen.findByRole("checkbox", { name: /学习选词习惯/ }) as HTMLInputElement;
  const mode = screen.getByRole("combobox", { name: "调频方式" });
  const trigger = screen.getByRole("combobox", { name: "触发频次(第几次上屏触发)" });
  const step = screen.getByRole("combobox", { name: "线性调频步长" });
  fireEvent.change(mode, { target: { value: "linear" } });
  fireEvent.click(learning);
  expect(mode).toBeDefined();
  expect(trigger).toBeDefined();
  expect(step).toBeDefined();
  fireEvent.change(mode, { target: { value: "disabled" } });
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
  const quanpin = await screen.findByRole("combobox", { name: "全拼辅助码方案" }) as HTMLSelectElement;
  expect(quanpin.textContent).toContain("自然码");
  fireEvent.change(quanpin, { target: { value: "xiaohe" } });
  fireEvent.click(screen.getByRole("checkbox", { name: "全拼辅助码" }));
  expect(quanpin.disabled).toBe(true);
  expect(quanpin.textContent).toContain("小鹤");
  fireEvent.change(screen.getByRole("combobox", { name: "双拼辅助码方案" }), { target: { value: "shouyou2_0" } });
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences,
    quanpin_helpcode: { enabled: false, schema: "xiaohe" },
    shuangpin_helpcode: { enabled: true, schema: "shouyou2_0" } });
});

test("shortcut page reflects enabled navigation shortcuts", async () => {
  render(<SettingsPage client={{ load: vi.fn().mockResolvedValue(initial), save: vi.fn() }} />);
  fireEvent.click(screen.getByRole("button", { name: "快捷键" }));
  expect(await screen.findByText("候选操作")).toBeDefined();
  expect(screen.getAllByText("- / =").length).toBeGreaterThan(0);
  expect(screen.getByText("↑ / ↓")).toBeDefined();
  expect(screen.getByText("Ctrl+Shift+Alt+C")).toBeDefined();
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

test("clipboard history defaults off, clears when disabled, and saves independently", async () => {
  const clear = vi.fn().mockResolvedValue(undefined);
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })), clipboard: { clear } };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "实用功能" }));
  const clipboard = await screen.findByRole("checkbox", { name: "剪贴板管理" }) as HTMLInputElement;
  expect(clipboard.checked).toBe(false);
  fireEvent.click(clipboard);
  expect(clipboard.checked).toBe(true);
  fireEvent.click(clipboard);
  expect(clear).toHaveBeenCalledTimes(1);
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, clipboard_history: false });
});

test("quick phrase manager queries, edits and removes Engine entries", async () => {
  const quick = { kind: "quick_phrase" as const, key: "x", value: "fixture", weight: 100000 };
  const list = vi.fn().mockResolvedValue({
    entries: [quick, { kind: "pinyin" as const, key: "ni", value: "你好", weight: 100 }],
    has_more: false,
  });
  const edit = vi.fn().mockResolvedValue(undefined);
  const client: SettingsClient = {
    load: vi.fn().mockResolvedValue(initial), save: vi.fn(), dictionary: { list, edit },
  };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "实用功能" }));
  fireEvent.click(await screen.findByRole("button", { name: "查询" }));
  expect(await screen.findByText("fixture")).toBeDefined();
  expect(within(screen.getByRole("region", { name: "快捷短语管理" })).queryByText("你好")).toBeNull();
  expect(list).toHaveBeenCalledWith(0, 100);
  fireEvent.click(screen.getByRole("button", { name: "编辑" }));
  fireEvent.change(screen.getByLabelText("短语"), { target: { value: "updated" } });
  fireEvent.click(screen.getByRole("button", { name: "保存" }));
  await waitFor(() => expect(edit).toHaveBeenCalledWith(quick, { ...quick, value: "updated" }, expect.stringMatching(/^ui-edit-/)));
  fireEvent.click(await screen.findByRole("button", { name: "删除" }));
  await waitFor(() => expect(edit).toHaveBeenCalledWith(quick, null, expect.stringMatching(/^ui-remove-/)));
});
const initial: Snapshot = { format_version: 1, revision: 7, preferences: { scheme: "quanpin", shuangpin_profile: "xiaohe", candidate_page_size: 5, learning: true, chinese_punctuation: true } };

test("candidate appearance settings persist and use legacy defaults", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  expect((await screen.findByLabelText("候选布局") as HTMLSelectElement).value).toBe("vertical");
  expect((screen.getByLabelText("候选字号") as HTMLSelectElement).value).toBe("18");
  fireEvent.change(screen.getByLabelText("候选布局"), { target: { value: "horizontal" } });
  fireEvent.change(screen.getByLabelText("候选字号"), { target: { value: "20" } });
  fireEvent.click(screen.getByRole("button", { name: "皮肤" }));
  expect((screen.getByRole("radio", { name: /Fluent/ }) as HTMLInputElement).checked).toBe(true);
  fireEvent.click(screen.getByRole("radio", { name: /微信绿/ }));
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, candidate_orientation: "horizontal", candidate_font_size: 20, candidate_skin: "wechat" });
});

test("floating toolbar settings use Windows defaults and persist independently", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "悬浮工具栏" }));
  const enabled = await screen.findByRole("checkbox", { name: "在桌面显示悬浮工具栏" }) as HTMLInputElement;
  expect(enabled.checked).toBe(true);
  expect((screen.getByLabelText("工具栏缩放") as HTMLSelectElement).value).toBe("100");
  expect((screen.getByLabelText("图标尺寸") as HTMLSelectElement).value).toBe("24");
  expect((screen.getByRole("checkbox", { name: "全角 / 半角" }) as HTMLInputElement).checked).toBe(true);
  expect((screen.getByRole("checkbox", { name: "屏幕键盘" }) as HTMLInputElement).checked).toBe(false);
  fireEvent.change(screen.getByLabelText("工具栏缩放"), { target: { value: "125" } });
  fireEvent.change(screen.getByLabelText("图标尺寸"), { target: { value: "28" } });
  fireEvent.click(screen.getByRole("checkbox", { name: "在桌面显示悬浮工具栏" }));
  fireEvent.click(screen.getByRole("checkbox", { name: "全角 / 半角" }));
  fireEvent.click(screen.getByRole("checkbox", { name: "屏幕键盘" }));
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, floating_toolbar: {
    enabled: false, fullwidth: false, punctuation: true, character_set: true, emoji: true,
    screen_keyboard: true, settings: true, scale: 125, font_size: 28,
  } });
});

test("help, about and feedback pages expose their Windows content and actions", async () => {
  const openExternalUrl = vi.fn().mockResolvedValue(undefined);
  const copyText = vi.fn().mockResolvedValue(undefined);
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn(), openExternalUrl, copyText };
  render(<SettingsPage client={client} />);

  fireEvent.click(screen.getByRole("button", { name: "帮助" }));
  expect(await screen.findByText("快速上手")).toBeDefined();
  expect(screen.getByText(/Win \+ Space/)).toBeDefined();

  fireEvent.click(screen.getByRole("button", { name: "关于" }));
  expect(await screen.findByText("Metasequoia IME")).toBeDefined();
  fireEvent.click(screen.getByRole("button", { name: "开源许可协议" }));
  await waitFor(() => expect(openExternalUrl).toHaveBeenCalledWith("https://github.com/metasequoiaime/MSIME-Windows/blob/main/LICENSE"));

  fireEvent.click(screen.getByRole("button", { name: "反馈" }));
  expect(await screen.findByText("GitHub Issues")).toBeDefined();
  fireEvent.click(screen.getByRole("button", { name: "复制群号" }));
  await waitFor(() => expect(copyText).toHaveBeenCalledWith("829919142"));
  fireEvent.click(screen.getByRole("button", { name: "查看 Issues" }));
  await waitFor(() => expect(openExternalUrl).toHaveBeenCalledWith("https://github.com/metasequoiaime/MSIME-Windows/issues"));
});

test("about page validates a newer release before offering its URL", async () => {
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
    ok: true,
    json: async () => ({ version: "v1.2.0", releaseUrl: "https://github.com/metasequoiaime/MSIME-Windows/releases", signed: true }),
  }));
  const openExternalUrl = vi.fn().mockResolvedValue(undefined);
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn(), openExternalUrl };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "关于" }));
  fireEvent.click(await screen.findByRole("button", { name: "检查更新" }));
  expect(await screen.findByText("发现新版本 v1.2.0")).toBeDefined();
  fireEvent.click(screen.getByRole("button", { name: "前往下载" }));
  await waitFor(() => expect(openExternalUrl).toHaveBeenCalledWith("https://github.com/metasequoiaime/MSIME-Windows/releases"));
  vi.unstubAllGlobals();
});

test("screen keyboard and handwriting pages expose the native panel actions", async () => {
  const openScreenKeyboard = vi.fn().mockResolvedValue(undefined);
  const openHandwriting = vi.fn().mockResolvedValue(undefined);
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn(), openScreenKeyboard, openHandwriting };
  render(<SettingsPage client={client} />);

  fireEvent.click(screen.getByRole("button", { name: "屏幕键盘" }));
  expect(await screen.findByText("打开屏幕键盘")).toBeDefined();
  expect(screen.getByLabelText("屏幕键盘预览")).toBeDefined();
  fireEvent.click(screen.getByRole("button", { name: "打开" }));
  await waitFor(() => expect(openScreenKeyboard).toHaveBeenCalledTimes(1));

  fireEvent.click(screen.getByRole("button", { name: "手写识别板" }));
  expect(await screen.findByText("打开手写识别板")).toBeDefined();
  expect(screen.getByLabelText("手写识别板预览")).toBeDefined();
  fireEvent.click(screen.getByRole("button", { name: "打开" }));
  await waitFor(() => expect(openHandwriting).toHaveBeenCalledTimes(1));
});

test("native panel views support close, modifier, drawing and undo interactions", async () => {
  const close = vi.fn().mockResolvedValue(undefined);
  const keyboard = render(<KeyboardPanel client={{ close }} />);
  const shifts = screen.getAllByRole("button", { name: "Shift" });
  fireEvent.click(shifts[0]);
  expect(shifts[0].getAttribute("aria-pressed")).toBe("true");
  fireEvent.click(screen.getByRole("button", { name: "A" }));
  expect(screen.getByRole("status").textContent).toContain("Shift+A");
  fireEvent.click(screen.getByRole("button", { name: "关闭" }));
  await waitFor(() => expect(close).toHaveBeenCalledTimes(1));
  keyboard.unmount();

  const panel = render(<HandwritingPanel client={{ close }} />);
  const canvas = screen.getByLabelText("手写画布");
  fireEvent.pointerDown(canvas, { clientX: 20, clientY: 20, pointerId: 1 });
  fireEvent.pointerMove(canvas, { clientX: 80, clientY: 80, pointerId: 1 });
  fireEvent.pointerUp(canvas, { clientX: 100, clientY: 100, pointerId: 1 });
  expect(screen.getByRole("status").textContent).toContain("识别结果");
  fireEvent.click(screen.getByRole("button", { name: /撤销/ }));
  expect(screen.getByText("请在左侧书写，松开鼠标后自动识别")).toBeDefined();
  panel.unmount();
});

test("emoji panel searches, copies items, tracks recent use and reads clipboard history", async () => {
  const close = vi.fn().mockResolvedValue(undefined);
  const copyText = vi.fn().mockResolvedValue(undefined);
  const list = vi.fn().mockResolvedValue(["fixture clipboard entry"]);
  const panel = render(<EmojiPanel client={{ close, copyText, clipboard: { list } }} />);

  expect(screen.getByRole("heading", { name: "Emoji" })).toBeDefined();
  fireEvent.click(screen.getByRole("button", { name: "😀" }));
  fireEvent.click(screen.getByRole("button", { name: "😂" }));
  await waitFor(() => expect(copyText).toHaveBeenCalledWith("😂"));
  expect(screen.getByRole("status").textContent).toContain("已复制：😂");

  fireEvent.change(screen.getByRole("textbox", { name: "搜索" }), { target: { value: "laugh" } });
  expect(screen.getByRole("button", { name: "😂" })).toBeDefined();
  fireEvent.click(screen.getByRole("button", { name: "剪贴板" }));
  expect(await screen.findByText("fixture clipboard entry")).toBeDefined();
  fireEvent.click(screen.getByRole("button", { name: "fixture clipboard entry" }));
  await waitFor(() => expect(copyText).toHaveBeenLastCalledWith("fixture clipboard entry"));
  expect(list).toHaveBeenCalled();
  fireEvent.click(screen.getByRole("button", { name: "关闭" }));
  await waitFor(() => expect(close).toHaveBeenCalledTimes(1));
  panel.unmount();
});

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
  const size = await screen.findByRole("combobox", { name: "每页候选数量" });
  fireEvent.change(size, { target: { value: "9" } });
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, candidate_page_size: 9 });
  expect((screen.getByRole("button", { name: "保存设置" }) as HTMLButtonElement).disabled).toBe(true);
});

test("conflicts preserve edits and require an explicit reload", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockRejectedValue({ code: "conflict" }) };
  render(<SettingsPage client={client} />);
  const size = await screen.findByRole("combobox", { name: "每页候选数量" });
  fireEvent.change(size, { target: { value: "9" } });
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  expect((await screen.findByRole("alert")).textContent).toContain("其他窗口");
  expect(size.textContent).toContain("9");
  expect(client.load).toHaveBeenCalledTimes(1);
  const confirm = vi.spyOn(window, "confirm").mockReturnValue(true);
  fireEvent.click(screen.getByRole("button", { name: "重新读取" }));
  await waitFor(() => expect(size.textContent).toContain("5"));
  confirm.mockRestore();
});

test("applies external preference revisions when clean and preserves dirty edits", async () => {
  let changed: ((snapshot: Snapshot) => void) | undefined;
  const client: SettingsClient = {
    load: vi.fn().mockResolvedValue(initial),
    save: vi.fn(),
    onPreferencesChanged: vi.fn(async listener => {
      changed = listener;
      return () => { changed = undefined; };
    }),
  };
  render(<SettingsPage client={client} />);
  const size = await screen.findByRole("combobox", { name: "每页候选数量" }) as HTMLSelectElement;
  await waitFor(() => expect(changed).toBeDefined());
  changed?.({ ...initial, revision: 8, preferences: { ...initial.preferences, candidate_page_size: 9 } });
  await waitFor(() => expect(size.value).toBe("9"));
  fireEvent.change(size, { target: { value: "7" } });
  changed?.({ ...initial, revision: 9, preferences: { ...initial.preferences, candidate_page_size: 5 } });
  expect(size.value).toBe("7");
  expect(await screen.findByText("设置已被其他窗口修改。请重新读取后再保存。")).toBeDefined();
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
  const pageSize = await screen.findByRole("combobox", { name: "每页候选数量" });
  fireEvent.change(pageSize, { target: { value: "9" } });
  fireEvent.click(screen.getByRole("button", { name: "辅助码" }));
  expect(screen.getByRole("heading", { level: 1 }).textContent).toBe("辅助码");
  expect(screen.queryByRole("combobox", { name: "每页候选数量" })).toBeNull();
  fireEvent.click(screen.getByRole("checkbox", { name: "全拼辅助码" }));
  fireEvent.click(appearance);
  expect(screen.getByRole("combobox", { name: "每页候选数量" }).textContent).toContain("9");
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, candidate_page_size: 9, quanpin_helpcode: { enabled: false, schema: "ziranma" } });
  expect(client.load).toHaveBeenCalledTimes(1);
});
