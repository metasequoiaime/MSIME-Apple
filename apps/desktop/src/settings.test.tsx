// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { act, cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import minimizeIcon from "../../../packages/ui/src/assets/minimize.svg";
import maximizeIcon from "../../../packages/ui/src/assets/maximize.svg";
import restoreIcon from "../../../packages/ui/src/assets/restore.svg";
import closeIcon from "../../../packages/ui/src/assets/close.svg";
import keyboardCapability from "../src-tauri/capabilities/keyboard.json";
import { CloudCandidatesPanel, CloudClipboardPanel, CloudDictionaryCatalogPanel, CloudDictionaryPanel, EmojiPanel, HandwritingPanel, KeyboardPanel, VoicePanel, SettingsPage, aiCredentialOrigin, type CustomSkinLibraryAction, type SavedTouchKeyboardSkin, type SettingsClient, type Snapshot, type TouchKeyboardSkinDesign } from "@msime/ui";

afterEach(cleanup);

test("titlebar sits above the shared sidebar and content body", async () => {
  const mounted = render(<SettingsPage client={{ load: async () => initial, save: vi.fn(),
    windowControl: vi.fn().mockResolvedValue(undefined) }} />);
  await screen.findByRole("button", { name: "保存设置" });
  const body = mounted.container.querySelector(".settings-body")!;
  expect(body.contains(screen.getByRole("navigation", { name: "设置分类" }))).toBe(true);
  expect(body.contains(screen.getByRole("main"))).toBe(true);
  expect(body.contains(screen.getByRole("banner", { name: "窗口控制" }))).toBe(false);
  expect(body.previousElementSibling).toBe(screen.getByRole("banner", { name: "窗口控制" }));
  expect(screen.getByRole("button", { name: "关闭" }).classList.contains("window-close")).toBe(true);
  expect(mounted.container.querySelector(".window-title")?.textContent).toBe("水杉 IME");
});

test("Android fuzzy-pinyin settings preserve rules while disabled and reset explicitly", async () => {
  const save = vi.fn().mockResolvedValue(initial);
  const confirm = vi.spyOn(window, "confirm").mockReturnValue(true);
  render(<SettingsPage client={{ load: async () => initial, save, fuzzyPinyin: true }} />);
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  const enabled = screen.getByRole("checkbox", { name: "启用模糊音" }) as HTMLInputElement;
  const rule = screen.getByRole("checkbox", { name: "模糊音规则 z-zh" }) as HTMLInputElement;
  expect(enabled.checked).toBe(false);
  expect(rule.disabled).toBe(true);
  fireEvent.click(enabled);
  fireEvent.click(rule);
  expect(rule.checked).toBe(true);
  fireEvent.click(enabled);
  expect(rule.checked).toBe(true);
  expect(rule.disabled).toBe(true);
  fireEvent.click(screen.getByRole("button", { name: "重置模糊音配置" }));
  expect(confirm).toHaveBeenCalledWith("关闭模糊音并清空所有规则？");
  expect(enabled.checked).toBe(false);
  expect(rule.checked).toBe(false);
  confirm.mockRestore();
});

const touchSchemeLabels = ["全拼 26 键", "全拼 9 键", "小鹤双拼", "自然码双拼", "微软双拼", "首道双拼", "86 五笔", "日语 9 键", "日语 26 键", "手写", "高情商回复"];
const touchSchemeIds = ["quanpin", "nine_key", "xiaohe", "ziranma", "microsoft", "shoudao", "wubi", "japanese_nine_key", "japanese", "handwriting", "thoughtful_reply"];

test("Android touch schemes follow Apple order and stay absent on hosts without the capability", async () => {
  const enabled = render(<SettingsPage client={{ load: async () => initial, save: vi.fn(), touchKeyboardSchemes: true }} />);
  fireEvent.click(await screen.findByRole("button", { name: "输入" }));
  const group = screen.getByRole("group", { name: "输入方案" });
  expect(within(group).getAllByRole("button").map(button => button.textContent?.replace("✓", ""))).toEqual(touchSchemeLabels);
  expect(within(group).getAllByRole("checkbox")).toHaveLength(11);
  enabled.unmount();
  render(<SettingsPage client={{ load: async () => initial, save: vi.fn() }} />);
  fireEvent.click(await screen.findByRole("button", { name: "输入" }));
  expect(screen.queryByRole("checkbox", { name: "显示输入方案 全拼 26 键" })).toBeNull();
});

test("Android offline candidate gloss is hidden elsewhere, defaults off and persists", async () => {
  const save = vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences }));
  const enabled = render(<SettingsPage client={{ load: async () => initial, save, candidateEnglishGloss: true }} />);
  fireEvent.click(await screen.findByRole("button", { name: "输入" }));
  const toggle = screen.getByRole("checkbox", { name: "显示英文释义" }) as HTMLInputElement;
  expect(toggle.checked).toBe(false);
  expect(screen.getByText(/释义来自随键盘打包的离线词库，不联网/)).toBeDefined();
  fireEvent.click(toggle);
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(save).toHaveBeenCalledWith(7, {
    ...initial.preferences,
    candidate_english_gloss: true,
  });
  enabled.unmount();
  render(<SettingsPage client={{ load: async () => initial, save: vi.fn() }} />);
  fireEvent.click(await screen.findByRole("button", { name: "输入" }));
  expect(screen.queryByRole("checkbox", { name: "显示英文释义" })).toBeNull();
});

test("Android touch scheme selection, fallback, last-visible guard and save payload match Apple", async () => {
  const save = vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences }));
  render(<SettingsPage client={{ load: async () => initial, save, touchKeyboardSchemes: true }} />);
  fireEvent.click(await screen.findByRole("button", { name: "输入" }));
  fireEvent.click(screen.getByRole("button", { name: "设为当前输入方案 全拼 9 键" }));
  expect(screen.getByRole("button", { name: "设为当前输入方案 全拼 9 键" }).getAttribute("aria-pressed")).toBe("true");
  fireEvent.click(screen.getByRole("checkbox", { name: "显示输入方案 全拼 9 键" }));
  expect(screen.getByRole("button", { name: "设为当前输入方案 全拼 26 键" }).getAttribute("aria-pressed")).toBe("true");
  for (const label of touchSchemeLabels.slice(1)) {
    const toggle = screen.getByRole("checkbox", { name: `显示输入方案 ${label}` }) as HTMLInputElement;
    if (toggle.checked) fireEvent.click(toggle);
  }
  const last = screen.getByRole("checkbox", { name: "显示输入方案 全拼 26 键" }) as HTMLInputElement;
  expect(last.checked).toBe(true);
  expect(last.disabled).toBe(true);
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(save).toHaveBeenCalledWith(7, expect.objectContaining({
    scheme: "quanpin",
    last_chinese_scheme: "quanpin",
    touch_keyboard_layout: "twenty_six_key",
    touch_keyboard_schemes: { enabled: ["quanpin"], selected: "quanpin" },
  }));
});

test("Android selecting nine-key saves the shared selected scheme and matching engine layout", async () => {
  const save = vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences }));
  render(<SettingsPage client={{ load: async () => initial, save, touchKeyboardSchemes: true }} />);
  fireEvent.click(await screen.findByRole("button", { name: "输入" }));
  fireEvent.click(screen.getByRole("button", { name: "设为当前输入方案 全拼 9 键" }));
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(save).toHaveBeenCalledWith(7, expect.objectContaining({
    scheme: "quanpin",
    touch_keyboard_layout: "nine_key",
    touch_keyboard_schemes: { enabled: touchSchemeIds, selected: "nine_key" },
  }));
});

test("Android touch schemes display the first enabled fallback for a valid selection-less snapshot", async () => {
  const snapshot = { ...initial, preferences: { ...initial.preferences,
    touch_keyboard_schemes: { enabled: ["wubi" as const] } } };
  render(<SettingsPage client={{ load: async () => snapshot, save: vi.fn(), touchKeyboardSchemes: true }} />);
  fireEvent.click(await screen.findByRole("button", { name: "输入" }));
  expect(screen.getByRole("button", { name: "设为当前输入方案 86 五笔" }).getAttribute("aria-pressed")).toBe("true");
  expect((screen.getByRole("checkbox", { name: "显示输入方案 86 五笔" }) as HTMLInputElement).disabled).toBe(true);
});

test("window SVGs follow host state and retain accessible controls", async () => {
  let publish: (maximized: boolean) => void = () => {};
  const windowControl = vi.fn().mockResolvedValue(undefined);
  render(<SettingsPage client={{ load: async () => initial, save: vi.fn(), windowControl,
    onWindowStateChanged: async listener => { publish = listener; return () => {}; } }} />);
  await screen.findByRole("button", { name: "保存设置" });
  function icon(label: string, source: string) {
    const button = screen.getByRole("button", { name: label });
    const img = button.querySelector("img")!;
    expect(img).not.toBeNull();
    expect(img.getAttribute("src")).toBe(source);
    expect(img.alt).toBe("");
    expect(img.draggable).toBe(false);
    expect(img.className).toBe("window-icon");
    expect(button.textContent).toBe("");
    return button;
  }
  fireEvent.click(icon("最小化", minimizeIcon));
  expect(windowControl).toHaveBeenLastCalledWith("minimize");
  fireEvent.click(icon("最大化", maximizeIcon));
  expect(windowControl).toHaveBeenLastCalledWith("maximize");
  act(() => publish(true));
  expect(screen.queryByRole("button", { name: "最大化" })).toBeNull();
  fireEvent.click(icon("还原", restoreIcon));
  expect(windowControl).toHaveBeenLastCalledWith("restore");
  act(() => publish(false));
  expect(screen.queryByRole("button", { name: "还原" })).toBeNull();
  icon("最大化", maximizeIcon);
  fireEvent.click(icon("关闭", closeIcon));
  expect(windowControl).toHaveBeenLastCalledWith("close");
});

test("resize starts on edge press, not pointer movement", async () => {
  const resizeWindow = vi.fn().mockResolvedValue(undefined);
  const mounted = render(<SettingsPage client={{ load: async () => initial, save: vi.fn(), resizeWindow }} />);
  await screen.findByRole("button", { name: "保存设置" });
  const shell = mounted.container.querySelector(".settings-shell")!;
  vi.spyOn(shell, "getBoundingClientRect").mockReturnValue({ left: 0, top: 0, right: 800, bottom: 600, width: 800, height: 600, x: 0, y: 0, toJSON() {} });
  fireEvent(shell, new MouseEvent("pointermove", { bubbles: true, buttons: 1, clientX: 1, clientY: 1 }));
  expect(resizeWindow).not.toHaveBeenCalled();
  fireEvent(shell, new MouseEvent("pointerdown", { bubbles: true, button: 0, clientX: 799, clientY: 599 }));
  expect(resizeWindow).toHaveBeenCalledWith("se");
  fireEvent(shell, new MouseEvent("pointerdown", { bubbles: true, button: 2, clientX: 1, clientY: 1 }));
  expect(resizeWindow).toHaveBeenCalledTimes(1);
});

function titlebarPointer(target: Element, type: string, x: number, y: number, detail = 1, buttons = 1) {
  fireEvent(target, new MouseEvent(type, { bubbles: true, button: 0, buttons, clientX: x, clientY: y, detail }));
}

test("titlebar drag waits for upstream two-pixel threshold and starts only once", async () => {
  const beginWindowDrag = vi.fn().mockResolvedValue(undefined);
  render(<SettingsPage client={{ load: async () => initial, save: vi.fn(), beginWindowDrag }} />);
  await screen.findByRole("button", { name: "保存设置" });
  const titlebar = screen.getByRole("banner", { name: "窗口控制" });
  titlebarPointer(titlebar, "pointerdown", 100, 16);
  expect(beginWindowDrag).not.toHaveBeenCalled();
  titlebarPointer(titlebar, "pointermove", 101, 16);
  expect(beginWindowDrag).not.toHaveBeenCalled();
  titlebarPointer(titlebar, "pointermove", 101, 17);
  expect(beginWindowDrag).toHaveBeenCalledTimes(1);
  titlebarPointer(titlebar, "pointermove", 110, 17);
  expect(beginWindowDrag).toHaveBeenCalledTimes(1);
});

test.each(["pointerup", "pointercancel", "pointerout", "blur", "released", "double-press"])(
  "%s cancels or excludes a pending titlebar drag", async reason => {
    const beginWindowDrag = vi.fn().mockResolvedValue(undefined);
    render(<SettingsPage client={{ load: async () => initial, save: vi.fn(), beginWindowDrag }} />);
    await screen.findByRole("button", { name: "保存设置" });
    const titlebar = screen.getByRole("banner", { name: "窗口控制" });
    titlebarPointer(titlebar, "pointerdown", 100, 16, reason === "double-press" ? 2 : 1);
    if (reason === "blur") fireEvent(window, new Event("blur"));
    else if (reason === "released") titlebarPointer(titlebar, "pointermove", 100, 16, 1, 0);
    else if (reason !== "double-press") titlebarPointer(titlebar, reason, 100, 16);
    titlebarPointer(titlebar, "pointermove", 110, 16);
    expect(beginWindowDrag).not.toHaveBeenCalled();
  },
);

test("resize edges do not drag or double-click maximize the titlebar", async () => {
  const beginWindowDrag = vi.fn().mockResolvedValue(undefined);
  const resizeWindow = vi.fn().mockResolvedValue(undefined);
  const windowControl = vi.fn().mockResolvedValue(undefined);
  const mounted = render(<SettingsPage client={{ load: async () => initial, save: vi.fn(), beginWindowDrag, resizeWindow, windowControl }} />);
  await screen.findByRole("button", { name: "保存设置" });
  vi.spyOn(mounted.container.querySelector(".settings-shell")!, "getBoundingClientRect")
    .mockReturnValue({ left: 0, top: 0, right: 800, bottom: 780, width: 800, height: 780, x: 0, y: 0, toJSON() {} });
  const titlebar = screen.getByRole("banner", { name: "窗口控制" });
  titlebarPointer(titlebar, "pointerdown", 100, 2);
  titlebarPointer(titlebar, "pointermove", 110, 16);
  expect(resizeWindow).toHaveBeenCalledWith("n");
  expect(beginWindowDrag).not.toHaveBeenCalled();
  fireEvent.doubleClick(titlebar, { button: 0, clientX: 100, clientY: 2 });
  fireEvent.doubleClick(titlebar, { button: 2, clientX: 100, clientY: 16 });
  expect(windowControl).not.toHaveBeenCalled();
  fireEvent.doubleClick(titlebar, { button: 0, clientX: 100, clientY: 16 });
  expect(windowControl).toHaveBeenCalledWith("maximize");
});

test.each([false, true])("titlebar drag handles host failure (synchronous=%s)", async synchronous => {
  const beginWindowDrag = vi.fn(() => {
    if (synchronous) throw new Error("host unavailable");
    return Promise.reject(new Error("host unavailable"));
  });
  render(<SettingsPage client={{ load: async () => initial, save: vi.fn(), beginWindowDrag }} />);
  await screen.findByRole("button", { name: "保存设置" });
  const titlebar = screen.getByRole("banner", { name: "窗口控制" });
  titlebarPointer(titlebar, "pointerdown", 100, 16);
  titlebarPointer(titlebar, "pointermove", 110, 16);
  expect(await screen.findByText("无法移动窗口，请重试。")).toBeTruthy();
});

test("window state subscription failures are handled", async () => {
  render(<SettingsPage client={{ load: async () => initial, save: vi.fn(),
    onWindowStateChanged: async () => { throw new Error("unavailable"); } }} />);
  expect(await screen.findByText("无法读取窗口状态，请重试。")).toBeTruthy();
});

test("window state update errors are shown and detached hosts cannot report errors", async () => {
  let reportError = () => {};
  const client: SettingsClient = { load: async () => initial, save: vi.fn(),
    onWindowStateChanged: async (_listener, onError) => { reportError = onError!; return () => {}; } };
  const mounted = render(<SettingsPage client={client} />);
  await screen.findByRole("button", { name: "保存设置" });
  act(() => reportError());
  expect(screen.getByText("无法读取窗口状态，请重试。")).toBeTruthy();
  mounted.rerender(<SettingsPage client={{ load: async () => initial, save: vi.fn() }} />);
  fireEvent.click(screen.getByRole("button", { name: "重新读取" }));
  await waitFor(() => expect(screen.queryByText("无法读取窗口状态，请重试。")).toBeNull());
  act(() => reportError());
  expect(screen.queryByText("无法读取窗口状态，请重试。")).toBeNull();
});

test("late window subscriptions are disposed and old callbacks ignored", async () => {
  let publish: (value: boolean) => void = () => {};
  let finish: (cleanup: () => void) => void = () => {};
  const unsubscribe = vi.fn();
  const windowControl = vi.fn().mockResolvedValue(undefined);
  const client: SettingsClient = { load: async () => initial, save: vi.fn(), windowControl,
    onWindowStateChanged: listener => {
      publish = listener;
      return new Promise(resolve => { finish = resolve; });
    } };
  const mounted = render(<SettingsPage client={client} />);
  await screen.findByRole("button", { name: "保存设置" });
  mounted.rerender(<SettingsPage client={{ load: async () => initial, save: vi.fn(), windowControl }} />);
  finish(unsubscribe);
  await waitFor(() => expect(unsubscribe).toHaveBeenCalledTimes(1));
  publish(true);
  expect(screen.queryByRole("button", { name: "还原" })).toBeNull();
  expect(screen.getByRole("button", { name: "最大化" })).toBeTruthy();
});

test("drag-only hosts do not expose unavailable window controls", async () => {
  render(<SettingsPage client={{ load: async () => initial, save: vi.fn(), beginWindowDrag: vi.fn() }} />);
  await screen.findByRole("button", { name: "保存设置" });
  expect(screen.queryByRole("button", { name: "关闭" })).toBeNull();
  expect(screen.queryByRole("button", { name: "最大化" })).toBeNull();
});

test("window buttons do not bubble drag or double-click maximize", async () => {
  const windowControl = vi.fn().mockResolvedValue(undefined);
  const beginWindowDrag = vi.fn().mockResolvedValue(undefined);
  render(<SettingsPage client={{ load: async () => initial, save: vi.fn(), windowControl, beginWindowDrag,
    onWindowStateChanged: async listener => { listener(true); return () => {}; } }} />);
  const restore = await screen.findByRole("button", { name: "还原" });
  fireEvent.pointerDown(restore, { button: 0 });
  fireEvent.doubleClick(restore);
  expect(beginWindowDrag).not.toHaveBeenCalled();
  expect(windowControl).not.toHaveBeenCalled();
  fireEvent.click(restore);
  expect(windowControl).toHaveBeenLastCalledWith("restore");
  fireEvent.doubleClick(screen.getByRole("banner", { name: "窗口控制" }));
  expect(windowControl).toHaveBeenLastCalledWith("restore");
});

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

test("voice settings persist under the shared voice_input contract", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "语音输入" }));
  const enabled = await screen.findByRole("checkbox", { name: "启用语音输入" }) as HTMLInputElement;
  expect(enabled.checked).toBe(true);
  fireEvent.click(enabled);
  fireEvent.change(screen.getByRole("combobox", { name: "识别服务" }), { target: { value: "doubao" } });
  fireEvent.change(screen.getByLabelText("识别语言"), { target: { value: "en-US" } });
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, {
    ...initial.preferences,
    // Picking a provider now also writes that provider's endpoint and model.
    // That is the point of the change: the shipped endpoint default is Doubao's
    // websocket URL, and leaving it behind routed other providers' tokens to
    // ByteDance.
    voice_input: { enabled: false, asr_provider: "doubao", language: "en-US", asr_resource_id: "volc.seedasr.sauc.duration", asr_endpoint: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async", asr_model: "",
      // Tokens are kept per provider, so switching also moves the credential
      // into the slot being left rather than carrying it to the new endpoint.
      asr_token: "", asr_tokens: {} },
  });
});

test("AI credentials stay scoped to the normalized HTTPS origin", async () => {
  expect(aiCredentialOrigin("https://Fixture.Invalid/v1/chat/completions")).toBe("https://fixture.invalid:443");
  expect(aiCredentialOrigin("https://fixture.invalid:444/v1/chat/completions")).toBe("https://fixture.invalid:444");
  expect(aiCredentialOrigin("http://fixture.invalid/v1/chat/completions")).toBeNull();
  const firstOrigin = "https://fixture.invalid:443";
  const snapshot: Snapshot = { ...initial, preferences: { ...initial.preferences, ai_assistant: {
    enabled: true, provider: "openai", model: "fixture-model",
    endpoint: "https://fixture.invalid/v1/chat/completions", candidate_limit: 3,
    tokens: { [firstOrigin]: "first-origin-fixture" }, prompt_id: "polish",
    prompt: "保持原意", prompt_custom_1: "", prompt_custom_2: "", prompt_custom_3: "",
  } } };
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(snapshot),
    save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...snapshot, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "AI 辅助" }));
  const endpoint = await screen.findByLabelText("AI 接口地址") as HTMLInputElement;
  const token = screen.getByLabelText("AI API Token") as HTMLInputElement;
  expect(token.value).toBe("first-origin-fixture");
  fireEvent.change(endpoint, { target: { value: "https://fixture.invalid/v2/chat/completions" } });
  expect(token.value).toBe("first-origin-fixture");
  fireEvent.change(endpoint, { target: { value: "https://other.invalid/v1/chat/completions" } });
  expect(token.value).toBe("");
  fireEvent.change(token, { target: { value: "second-origin-fixture" } });
  fireEvent.change(endpoint, { target: { value: "https://fixture.invalid/v1/chat/completions" } });
  expect(token.value).toBe("first-origin-fixture");
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  const saved = vi.mocked(client.save).mock.calls[0][1].ai_assistant!;
  expect(saved.token).toBe("");
  expect(saved.tokens).toEqual({
    [firstOrigin]: "first-origin-fixture",
    "https://other.invalid:443": "second-origin-fixture",
  });
});

test("Android AI settings fetch models and run a native-hosted polish test", async () => {
  const fetchModels = vi.fn().mockResolvedValue(["fixture-model", "fixture-fast"]);
  const testAi = vi.fn().mockResolvedValue("fixture-polished");
  render(<SettingsPage client={{ load: async () => initial, save: vi.fn(), aiAssistant: { fetchModels, test: testAi } }} />);
  fireEvent.click(await screen.findByRole("button", { name: "AI 辅助" }));
  fireEvent.change(screen.getByLabelText("AI API Token"), { target: { value: "fixture-token" } });
  fireEvent.click(screen.getByRole("button", { name: "获取模型列表" }));
  await screen.findByText("已获取 2 个可用模型。");
  fireEvent.change(screen.getByRole("combobox", { name: "已获取的 AI 模型" }), { target: { value: "fixture-fast" } });
  fireEvent.change(screen.getByLabelText("AI 测试输入"), { target: { value: "fixture input" } });
  fireEvent.click(screen.getByRole("button", { name: "发送并润色" }));
  await screen.findByText("fixture-polished");
  expect(fetchModels).toHaveBeenCalledWith({ endpoint: "https://api.deepseek.com/chat/completions", token: "fixture-token" });
  expect(testAi).toHaveBeenCalledWith({ endpoint: "https://api.deepseek.com/chat/completions", model: "fixture-fast", prompt: "请润色以下文字，保持原意，只返回修改后的文字。", token: "fixture-token", text: "fixture input" });
});

test("input parity controls persist cloud, translation and punctuation settings", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  fireEvent.click(await screen.findByRole("checkbox", { name: /云联想/ }));
  fireEvent.click(screen.getByRole("checkbox", { name: /候选翻译/ }));
  fireEvent.change(screen.getByLabelText("候选翻译目标语言"), { target: { value: "ja" } });
  fireEvent.click(screen.getByRole("checkbox", { name: /智能标点/ }));
  fireEvent.change(screen.getByLabelText("标点锁定"), { target: { value: "english" } });
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, {
    ...initial.preferences,
    cloud_candidates: false,
    candidate_translations: false,
    translation_target_language: "ja",
    smart_punctuation: false,
    punctuation_lock: "english",
  });
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

test("candidate-panel mouse-wheel paging is opt-in and persists", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  const wheel = await screen.findByRole("checkbox", { name: "鼠标滚轮（候选面板支持时翻页）" }) as HTMLInputElement;
  expect(wheel.checked).toBe(false);
  fireEvent.click(wheel);
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, expect.objectContaining({
    navigation: expect.objectContaining({ mouse_wheel: true }),
  }));
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
    quanpin_helpcode: { enabled: false, schema: "xiaohe", show_in_candidate_window: true },
    shuangpin_helpcode: { enabled: true, schema: "shouyou2_0", show_in_candidate_window: true } });
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

test("dictionary manager queries, edits and removes Engine entries", async () => {
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
  fireEvent.click(screen.getByRole("button", { name: "词库" }));
  fireEvent.click(await screen.findByRole("button", { name: "查询" }));
  expect(await screen.findByText("fixture")).toBeDefined();
  expect(within(screen.getByRole("region", { name: "快捷短语管理" })).queryByText("你好")).toBeNull();
  expect(list).toHaveBeenCalledWith(0, 100);
  fireEvent.click(screen.getByRole("button", { name: "编辑" }));
  fireEvent.change(screen.getByLabelText("短语"), { target: { value: "updated" } });
  fireEvent.click(screen.getByRole("button", { name: "保存" }));
  await waitFor(() => expect(edit).toHaveBeenCalledWith(quick, { ...quick, value: "updated" }, expect.stringMatching(/^ui-edit-/)));
  // Deletion is not undoable, so it asks first.
  const confirmRemoval = vi.spyOn(window, "confirm").mockReturnValue(true);
  fireEvent.click(await screen.findByRole("button", { name: "删除" }));
  await waitFor(() => expect(edit).toHaveBeenCalledWith(quick, null, expect.stringMatching(/^ui-remove-/)));
  expect(confirmRemoval).toHaveBeenCalled();
  confirmRemoval.mockRestore();
});

test("dictionary manager pages through entries instead of loading the whole dictionary", async () => {
  const page = (offset: number, count: number, has_more: boolean) => ({
    entries: Array.from({ length: count }, (_, index) => ({
      kind: "pinyin" as const, key: `k${offset + index}`, value: `词${offset + index}`, weight: 100,
    })),
    has_more,
  });
  const list = vi.fn()
    .mockResolvedValueOnce(page(0, 100, true))
    .mockResolvedValueOnce(page(100, 20, false));
  const client: SettingsClient = {
    load: vi.fn().mockResolvedValue(initial), save: vi.fn(), dictionary: { list, edit: vi.fn() },
  };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "词库" }));
  fireEvent.change(await screen.findByLabelText("本地词库类型"), { target: { value: "pinyin" } });
  fireEvent.click(screen.getByRole("button", { name: "查询" }));
  expect(await screen.findByText("第 1–100 条，后面还有结果")).toBeDefined();
  expect(list).toHaveBeenCalledWith(0, 100);
  // The first page must not be followed by a second request on its own.
  expect(list).toHaveBeenCalledTimes(1);
  expect(screen.getByRole("button", { name: "上一页" })).toHaveProperty("disabled", true);
  fireEvent.click(screen.getByRole("button", { name: "下一页" }));
  expect(await screen.findByText("第 101–120 条")).toBeDefined();
  expect(list).toHaveBeenLastCalledWith(100, 100);
  expect(screen.getByRole("button", { name: "下一页" })).toHaveProperty("disabled", true);
  expect(screen.getByRole("button", { name: "上一页" })).toHaveProperty("disabled", false);
});

test("diagnostic logging starts off and each host is saved separately", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "关于" }));
  const server = await screen.findByLabelText("Server 端日志") as HTMLInputElement;
  const tsf = screen.getByLabelText("TSF 端日志") as HTMLInputElement;
  // A configuration that never mentioned diagnostics must not start logging.
  expect(server.checked).toBe(false);
  expect(tsf.checked).toBe(false);
  fireEvent.click(server);
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, diagnostic_log: { server: true, tsf: false } });
  expect(server.checked).toBe(true);
  expect(tsf.checked).toBe(false);
});

const initial: Snapshot = { format_version: 1, revision: 7, preferences: { scheme: "quanpin", shuangpin_profile: "xiaohe", candidate_page_size: 5, learning: true, chinese_punctuation: true } };

test("candidate appearance settings persist and use legacy defaults", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  expect((await screen.findByLabelText("候选布局") as HTMLSelectElement).value).toBe("vertical");
  expect((screen.getByLabelText("候选字号") as HTMLSelectElement).value).toBe("16");
  fireEvent.change(screen.getByLabelText("候选布局"), { target: { value: "horizontal" } });
  fireEvent.change(screen.getByLabelText("候选字号"), { target: { value: "20" } });
  fireEvent.click(screen.getByRole("button", { name: "皮肤" }));
  expect(screen.getByRole("switch", { name: /Fluent/ }).getAttribute("aria-checked")).toBe("true");
  fireEvent.click(screen.getByRole("switch", { name: /微信绿/ }));
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, candidate_layout: "horizontal", candidate_font_size: 20, candidate_skin: "wechat" });
});

test("font family controls preserve order, validate drafts and save Unicode", async () => {
  const save = vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences }));
  const mounted = render(<SettingsPage client={{ load: async () => initial, save }} />);
  const primary = await screen.findByLabelText("候选窗主字体");
  expect((primary as HTMLInputElement).value).toBe("Segoe UI");
  fireEvent.change(primary, { target: { value: "示例主字体" } });
  fireEvent.click(screen.getByRole("button", { name: "添加补充字体" }));
  expect((screen.getByRole("button", { name: "保存设置" }) as HTMLButtonElement).disabled).toBe(true);
  fireEvent.submit(mounted.container.querySelector("form")!);
  expect(save).not.toHaveBeenCalled();
  fireEvent.change(screen.getByLabelText("补充字体 1"), { target: { value: "示例一" } });
  fireEvent.click(screen.getByRole("button", { name: "添加补充字体" }));
  fireEvent.change(screen.getByLabelText("补充字体 2"), { target: { value: "示例二" } });
  fireEvent.click(screen.getByRole("button", { name: "上移补充字体 2" }));
  expect((screen.getByLabelText("补充字体 1") as HTMLInputElement).value).toBe("示例二");
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(save).toHaveBeenLastCalledWith(7, { ...initial.preferences, candidate_font_family: "示例主字体", candidate_fallback_fonts: ["示例二", "示例一"] });
  fireEvent.click(screen.getByRole("button", { name: "移除补充字体 1" }));
  fireEvent.change(primary, { target: { value: "字".repeat(43) } });
  expect((screen.getByRole("button", { name: "保存设置" }) as HTMLButtonElement).disabled).toBe(true);
  fireEvent.change(primary, { target: { value: "有效示例" } });
  expect((screen.getByRole("button", { name: "保存设置" }) as HTMLButtonElement).disabled).toBe(false);
});

test("font controls allow 32 existing fallbacks but prevent a 33rd", async () => {
  render(<SettingsPage client={{ load: async () => ({ ...initial, preferences: { ...initial.preferences, candidate_fallback_fonts: Array.from({ length: 32 }, (_, i) => `示例${i}`) } }), save: vi.fn() }} />);
  await screen.findByLabelText("补充字体 32");
  expect((screen.getByRole("button", { name: "添加补充字体" }) as HTMLButtonElement).disabled).toBe(true);
  fireEvent.click(screen.getByRole("button", { name: "移除补充字体 32" }));
  expect((screen.getByRole("button", { name: "添加补充字体" }) as HTMLButtonElement).disabled).toBe(false);
});

test("automatic color swatch follows candidate theme without persisting a color override", async () => {
  const save = vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, preferences }));
  render(<SettingsPage client={{ load: async () => initial, save }} />);
  const color = await screen.findByLabelText("候选文字颜色") as HTMLInputElement;
  const change = (label: string, value: string) => fireEvent.change(screen.getByLabelText(label), { target: { value } });
  expect(color.value).toBe("#e9e8e8");
  change("全局主题", "light");
  expect(color.value).toBe("#1a1a1a");
  change("设置窗口主题", "dark");
  expect(color.value).toBe("#1a1a1a");
  change("候选窗主题", "dark");
  expect(color.value).toBe("#e9e8e8");
  change("候选文字颜色", "#123456");
  change("候选窗主题", "light");
  expect(color.value).toBe("#123456");
  fireEvent.click(screen.getByRole("button", { name: "跟随主题" }));
  expect(color.value).toBe("#1a1a1a");
  const preview = screen.getByRole("region", { name: "候选窗口预览" }).querySelector<HTMLElement>(".appearance-candidate-preview")!;
  expect(preview.style.getPropertyValue("--cand-text")).toBe("");
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await waitFor(() => expect(save).toHaveBeenCalledWith(7, expect.objectContaining({ candidate_text_color: null })));
});

test("screen keyboard header drag is bounded and separate from close and keys", async () => {
  expect(keyboardCapability.windows).toEqual(["keyboard-panel"]);
  expect(keyboardCapability.permissions).toEqual(["core:window:allow-start-dragging", "core:event:allow-listen", "core:event:allow-unlisten"]);
  const beginWindowDrag = vi.fn().mockResolvedValue(undefined);
  const close = vi.fn().mockResolvedValue(undefined);
  const sendKey = vi.fn().mockResolvedValue(undefined);
  const view = render(<KeyboardPanel client={{ close, beginWindowDrag, sendKey }} />);
  const header = view.container.querySelector(".native-panel-header")!;
  titlebarPointer(header, "pointerdown", 100, 14);
  titlebarPointer(header, "pointermove", 101, 14);
  expect(beginWindowDrag).not.toHaveBeenCalled();
  titlebarPointer(header, "pointermove", 103, 14);
  titlebarPointer(header, "pointermove", 110, 14);
  expect(beginWindowDrag).toHaveBeenCalledTimes(1);
  for (const target of [screen.getByRole("button", { name: "关闭" }), screen.getByRole("button", { name: "a" })]) {
    titlebarPointer(target, "pointerdown", 100, 14);
    titlebarPointer(target, "pointermove", 110, 14);
  }
  expect(beginWindowDrag).toHaveBeenCalledTimes(1);
  expect(close).not.toHaveBeenCalled();
  expect(sendKey).not.toHaveBeenCalled();
  for (const reason of ["pointerup", "pointercancel", "pointerout", "blur"]) {
    titlebarPointer(header, "pointerdown", 100, 14);
    if (reason === "blur") fireEvent(window, new Event("blur"));
    else titlebarPointer(header, reason, 100, 14);
    titlebarPointer(header, "pointermove", 110, 14);
    expect(beginWindowDrag).toHaveBeenCalledTimes(1);
  }
});

test.each([false, true])("keyboard drag reports host failure (synchronous=%s)", async synchronous => {
  const view = render(<KeyboardPanel client={{ close: async () => {}, beginWindowDrag: () => {
    if (synchronous) throw new Error("synthetic");
    return Promise.reject(new Error("synthetic"));
  } }} />);
  const header = view.container.querySelector(".native-panel-header")!;
  titlebarPointer(header, "pointerdown", 100, 14);
  titlebarPointer(header, "pointermove", 110, 14);
  await waitFor(() => expect(screen.getByRole("status").textContent).toBe("无法移动窗口，请重试。"));
});

test("screen keyboard matches upstream Shift and Caps posting combinations", async () => {
  for (const caps of [false, true]) for (const shift of [false, true]) {
    const sendKey = vi.fn().mockResolvedValue(undefined);
    const panel = render(<KeyboardPanel client={{ close: async () => {}, sendKey }} />);
    if (caps) fireEvent.click(screen.getByRole("button", { name: "Caps Lock" }));
    if (shift) fireEvent.click(screen.getAllByRole("button", { name: "Shift" })[0]);
    // Find the key by what it types: the preview's row layout is presentation
    // and has already been rearranged once.
    const letter = Array.from(panel.container.querySelectorAll<HTMLButtonElement>(".keyboard-row button"))
      .find(button => button.textContent === (shift ? "A" : "a"))!;
    expect(letter).toBeDefined();
    expect(screen.getByRole("button", { name: "Space" })).toBeDefined();
    fireEvent.click(letter);
    expect(sendKey).toHaveBeenLastCalledWith(expect.objectContaining({ virtual_key: 0x41, shift: caps || shift, include_sticky_modifiers: true }));
    await waitFor(() => expect(screen.getByRole("status").textContent).toContain("已发送"));
    expect(letter.textContent).toBe("a");
    panel.unmount();
  }
});

test("screen keyboard sends every digit as an unmodified IME selection key", async () => {
  const sendKey = vi.fn().mockResolvedValue(undefined);
  render(<KeyboardPanel client={{ close: async () => {}, sendKey }} />);
  for (const modifier of ["Ctrl", "Alt", "Win"]) {
    fireEvent.click(screen.getAllByRole("button", { name: modifier })[0]);
  }
  for (const [index, digit] of [..."1234567890"].entries()) {
    fireEvent.click(screen.getAllByRole("button", { name: "Shift" })[0]);
    fireEvent.click(screen.getByRole("button", { name: [..."!@#$%^&*()"][index] }));
    expect(sendKey).toHaveBeenLastCalledWith({
      virtual_key: digit.charCodeAt(0), shift: false,
      modifiers: { ctrl: true, alt: true, win: true }, include_sticky_modifiers: false,
    });
    expect(screen.getAllByRole("button", { name: "Shift" })[0].getAttribute("aria-pressed")).toBe("false");
  }
  await waitFor(() => expect(screen.getByRole("status").textContent).toContain("已发送"));
});

test("screen keyboard Shift key faces match punctuation and preserve virtual keys", async () => {
  const sendKey = vi.fn().mockResolvedValue(undefined);
  render(<KeyboardPanel client={{ close: async () => {}, sendKey }} />);
  const keys: [string, string, number][] = [["`", "~", 0xc0], ["-", "_", 0xbd], ["=", "+", 0xbb], ["[", "{", 0xdb], ["]", "}", 0xdd], ["\\", "|", 0xdc], [";", ":", 0xba], ["'", '"', 0xde], [",", "<", 0xbc], [".", ">", 0xbe], ["/", "?", 0xbf]];
  for (const [normal, shifted, code] of keys) {
    fireEvent.click(screen.getAllByRole("button", { name: "Shift" })[0]);
    fireEvent.click(screen.getByRole("button", { name: shifted }));
    expect(sendKey).toHaveBeenLastCalledWith(expect.objectContaining({ virtual_key: code, shift: true, include_sticky_modifiers: true }));
    expect(screen.getByRole("button", { name: normal })).toBeDefined();
  }
  await waitFor(() => expect(screen.getByRole("status").textContent).toContain("已发送"));
});

test("screen keyboard theme and Apple skin load, save independently and reload", async () => {
  let snapshot: Snapshot = { ...initial, preferences: { ...initial.preferences, theme: "light", screen_keyboard_theme: "light", toolbar_theme: "dark", candidate_skin: "graphite", touch_keyboard_skin: "typewriter" } };
  const save = vi.fn().mockImplementation(async (_revision, preferences) => {
    snapshot = { ...snapshot, revision: 8, preferences }; return snapshot;
  });
  render(<SettingsPage client={{ load: async () => snapshot, save }} />);
  const select = await screen.findByLabelText("屏幕键盘主题") as HTMLSelectElement;
  fireEvent.click(screen.getByRole("button", { name: "屏幕键盘" }));
  expect(select.value).toBe("light");
  const preview = screen.getByRole("img", { name: "屏幕键盘完整布局预览" });
  expect(preview.getAttribute("data-preview-theme")).toBe("light");
  expect(preview.getAttribute("data-preview-skin")).toBe("typewriter");
  const skins = screen.getAllByRole("switch", { name: /屏幕键盘皮肤/ });
  expect(skins.map(button => button.getAttribute("aria-label"))).toEqual([
    "屏幕键盘皮肤 水杉绿", "屏幕键盘皮肤 海盐蓝", "屏幕键盘皮肤 浅蔷薇", "屏幕键盘皮肤 素白瓷",
    "屏幕键盘皮肤 纸上时光", "屏幕键盘皮肤 奶油桃桃", "屏幕键盘皮肤 霓虹夜航", "屏幕键盘皮肤 工程蓝图",
  ]);
  fireEvent.click(screen.getByRole("switch", { name: "屏幕键盘皮肤 霓虹夜航" }));
  expect(preview.getAttribute("data-preview-skin")).toBe("midnight");
  expect(preview.querySelectorAll("[data-keyboard-key]")).toHaveLength(61);
  expect([...preview.querySelectorAll("[data-keyboard-row]")].map(row => row.children.length)).toEqual([14, 14, 13, 12, 8]);
  expect(preview.querySelectorAll("button, [tabindex], a")).toHaveLength(0);
  for (const row of preview.querySelectorAll("[data-keyboard-row]")) {
    let right = 0;
    for (const rect of row.querySelectorAll("rect")) {
      const x = Number(rect.getAttribute("x"));
      const y = Number(rect.getAttribute("y"));
      const width = Number(rect.getAttribute("width"));
      const height = Number(rect.getAttribute("height"));
      expect(x).toBeGreaterThanOrEqual(right);
      expect(x + width).toBeLessThanOrEqual(1100);
      expect(y + height).toBeLessThanOrEqual(400);
      expect(width).toBeGreaterThan(0);
      right = x + width;
    }
  }
  fireEvent.change(select, { target: { value: "dark" } });
  expect(preview.getAttribute("data-preview-theme")).toBe("dark");
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await waitFor(() => expect(save).toHaveBeenCalledWith(7, expect.objectContaining({ screen_keyboard_theme: "dark", toolbar_theme: "dark", candidate_skin: "graphite", touch_keyboard_skin: "midnight" })));
  fireEvent.click(screen.getByRole("switch", { name: "屏幕键盘皮肤 水杉绿" }));
  expect(preview.getAttribute("data-preview-skin")).toBe("forest");
  fireEvent.change(select, { target: { value: "follow" } });
  expect(preview.getAttribute("data-preview-theme")).toBe("light");
  const confirm = vi.spyOn(window, "confirm").mockReturnValueOnce(true);
  fireEvent.click(screen.getByRole("button", { name: "重新读取" }));
  confirm.mockRestore();
  await waitFor(() => expect(select.value).toBe("dark"));
  expect(preview.getAttribute("data-preview-theme")).toBe("dark");
  expect(preview.getAttribute("data-preview-skin")).toBe("midnight");
});

test("Android custom skin editor applies Apple templates, undo, materials and shared selection", async () => {
  const save = vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences }));
  render(<SettingsPage client={{ load: async () => initial, save, customTouchKeyboardSkins: true }} />);
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "屏幕键盘" }));
  expect(screen.getAllByRole("switch", { name: /屏幕键盘皮肤/ })).toHaveLength(9);
  fireEvent.click(screen.getByRole("button", { name: "设计我的皮肤" }));
  const editor = screen.getByLabelText("自定义皮肤编辑器");
  fireEvent.click(within(editor).getByRole("tab", { name: "设计" }));
  expect(within(editor).getAllByRole("button", { name: /皮肤模板/ })).toHaveLength(14);
  fireEvent.click(within(editor).getByRole("button", { name: "皮肤模板 奶油桃桃" }));
  const preview = within(editor).getByRole("img", { name: "屏幕键盘完整布局预览" });
  expect(preview.getAttribute("data-key-shape")).toBe("pebble");
  expect(preview.getAttribute("data-key-material")).toBe("raised");
  fireEvent.click(within(editor).getByRole("button", { name: "撤销设计" }));
  expect(preview.getAttribute("data-key-shape")).toBe("rounded");
  fireEvent.click(within(editor).getByRole("button", { name: "重做" }));
  expect(preview.getAttribute("data-key-shape")).toBe("pebble");
  fireEvent.click(within(editor).getByRole("button", { name: "皮肤模板 工程蓝图" }));
  expect(preview.getAttribute("data-key-material")).toBe("glass");
  fireEvent.click(within(editor).getByRole("button", { name: "撤销设计" }));
  expect(preview.getAttribute("data-key-shape")).toBe("pebble");
  fireEvent.click(within(editor).getByRole("tab", { name: "按键" }));
  fireEvent.change(within(editor).getByLabelText("键帽不透明度"), { target: { value: ".45" } });
  fireEvent.click(within(editor).getByRole("button", { name: "使用皮肤" }));
  expect(screen.getByRole("switch", { name: "屏幕键盘皮肤 我的皮肤" }).getAttribute("aria-checked")).toBe("true");
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await waitFor(() => expect(save).toHaveBeenCalledWith(7, expect.objectContaining({
    touch_keyboard_skin: "custom",
    custom_touch_keyboard_skin: expect.objectContaining({
      background: 0xFFE0D0, keyShape: "pebble", keyMaterial: "raised",
      keyOpacity: .45, cornerRadius: 18, pattern: 3,
    }),
  })));
});

const savedSkinDesign = (patch: Partial<TouchKeyboardSkinDesign> = {}): TouchKeyboardSkinDesign => ({
  background: 0xE8F0EB, keyBackground: 0xFFFFFF, keyForeground: 0x17251D,
  accent: 0x185C47, actionBackground: 0x185C47, cornerRadius: 8,
  borderWidth: 0, shadow: 0, pattern: 0, monospaced: false, ...patch,
});

test("Android named skin library loads and completes create, apply, update, rename and delete", async () => {
  let saved: SavedTouchKeyboardSkin[] = [{
    id: "11111111-1111-4111-8111-111111111111", name: "雾光样例",
    design: savedSkinDesign({ keyShape: "ticket", keyMaterial: "paper" }),
  }];
  const load = vi.fn(async () => saved);
  const mutate = vi.fn(async (action: CustomSkinLibraryAction) => {
    if (action.operation === "create") saved = [...saved, { id: "22222222-2222-4222-8222-222222222222", name: action.name, design: action.design }];
    if (action.operation === "rename") saved = saved.map(item => item.id === action.id ? { ...item, name: action.name } : item);
    if (action.operation === "update") saved = saved.map(item => item.id === action.id ? { ...item, design: action.design } : item);
    if (action.operation === "delete") saved = saved.filter(item => item.id !== action.id);
    return saved;
  });
  render(<SettingsPage client={{ load: async () => initial, save: vi.fn(), customTouchKeyboardSkins: true, customSkinLibrary: { load, mutate } }} />);
  fireEvent.click(await screen.findByRole("button", { name: "屏幕键盘" }));
  fireEvent.click(screen.getByRole("button", { name: "设计我的皮肤" }));
  const editor = screen.getByLabelText("自定义皮肤编辑器");
  await waitFor(() => expect(load).toHaveBeenCalledTimes(1));
  fireEvent.click(within(editor).getByRole("tab", { name: "我的" }));
  await within(editor).findByRole("button", { name: "应用已保存皮肤 雾光样例" });

  fireEvent.click(within(editor).getByRole("button", { name: "应用已保存皮肤 雾光样例" }));
  expect(within(editor).getByRole("img", { name: "屏幕键盘完整布局预览" }).getAttribute("data-key-shape")).toBe("ticket");

  fireEvent.click(within(editor).getByRole("tab", { name: "设计" }));
  fireEvent.click(within(editor).getByRole("button", { name: "皮肤模板 奶油桃桃" }));
  fireEvent.click(within(editor).getByRole("tab", { name: "我的" }));
  fireEvent.click(within(editor).getByRole("button", { name: "用当前设计更新 雾光样例" }));
  fireEvent.click(within(editor).getByRole("button", { name: "确认更新" }));
  await waitFor(() => expect(mutate).toHaveBeenCalledWith(expect.objectContaining({
    operation: "update", id: "11111111-1111-4111-8111-111111111111",
    design: expect.objectContaining({ keyShape: "pebble", keyMaterial: "raised" }),
  })));

  fireEvent.click(within(editor).getByRole("button", { name: "重命名 雾光样例" }));
  fireEvent.change(within(editor).getByLabelText("皮肤名称"), { target: { value: "桃色样例" } });
  fireEvent.click(within(editor).getByRole("button", { name: "确认重命名" }));
  await within(editor).findByRole("button", { name: "应用已保存皮肤 桃色样例" });
  expect(mutate).toHaveBeenCalledWith({ operation: "rename", id: "11111111-1111-4111-8111-111111111111", name: "桃色样例" });

  fireEvent.click(within(editor).getByRole("button", { name: "删除 桃色样例" }));
  fireEvent.click(within(editor).getByRole("button", { name: "确认删除" }));
  await waitFor(() => expect(within(editor).queryByRole("button", { name: "应用已保存皮肤 桃色样例" })).toBeNull());
  expect(mutate).toHaveBeenCalledWith({ operation: "delete", id: "11111111-1111-4111-8111-111111111111" });

  fireEvent.click(within(editor).getByRole("button", { name: "保存设计" }));
  fireEvent.change(within(editor).getByLabelText("皮肤名称"), { target: { value: "新建样例" } });
  fireEvent.click(within(editor).getByRole("button", { name: "确认保存" }));
  await within(editor).findByRole("button", { name: "应用已保存皮肤 新建样例" });
  expect(mutate).toHaveBeenCalledWith(expect.objectContaining({ operation: "create", name: "新建样例" }));
  expect(screen.getByRole("switch", { name: "屏幕键盘皮肤 我的皮肤" }).getAttribute("aria-checked")).toBe("true");
});

test("Android named skin library reports duplicate names and concurrent twelve-item limits", async () => {
  const mutate = vi.fn()
    .mockRejectedValueOnce({ code: "custom_skin_duplicate_name" })
    .mockRejectedValueOnce({ code: "custom_skin_full" });
  render(<SettingsPage client={{ load: async () => initial, save: vi.fn(), customTouchKeyboardSkins: true,
    customSkinLibrary: { load: async () => [], mutate } }} />);
  fireEvent.click(await screen.findByRole("button", { name: "屏幕键盘" }));
  fireEvent.click(screen.getByRole("button", { name: "设计我的皮肤" }));
  const editor = screen.getByLabelText("自定义皮肤编辑器");
  const saveDesign = within(editor).getByRole("button", { name: "保存设计" }) as HTMLButtonElement;
  await waitFor(() => expect(saveDesign.disabled).toBe(false));
  fireEvent.click(saveDesign);
  fireEvent.change(within(editor).getByLabelText("皮肤名称"), { target: { value: "重复样例" } });
  fireEvent.click(within(editor).getByRole("button", { name: "确认保存" }));
  await within(editor).findByText("已经有同名皮肤，请换一个名称。");
  fireEvent.change(within(editor).getByLabelText("皮肤名称"), { target: { value: "容量样例" } });
  fireEvent.click(within(editor).getByRole("button", { name: "确认保存" }));
  await within(editor).findByText("最多保存 12 套皮肤，请先删除不需要的设计。");
  expect(mutate).toHaveBeenCalledTimes(2);
});

test("Android AI skin draw prepares artwork, saves a proposal and continues editing", async () => {
  const aiSkins = {
    generate: vi.fn().mockResolvedValue([1, 2, 3].map(index => ({
      name: `AI 测试 ${index}`, description: "仅用于界面自动化的合成设计", artworkPrompt: "原创背景场景，角色位于边缘，柔和插画，中央安静留白",
      design: savedSkinDesign({ keyShape: index === 1 ? "rounded" : index === 2 ? "capsule" : "ticket", keyMaterial: index === 1 ? "flat" : index === 2 ? "raised" : "paper" }),
      artwork: { b64_json: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=", mime_type: "image/png" as const, width: 1, height: 1 },
    }))),
    cancel: vi.fn().mockResolvedValue(undefined),
    onProgress: vi.fn().mockResolvedValue(() => {}),
  };
  const mutate = vi.fn().mockImplementation(async (action: CustomSkinLibraryAction) => [{ id: "33333333-3333-4333-8333-333333333333", name: action.operation === "create" ? action.name : "AI 测试 1", design: savedSkinDesign() }]);
  render(<SettingsPage client={{ load: async () => initial, save: vi.fn(), customTouchKeyboardSkins: true, aiSkins, customSkinLibrary: { load: async () => [], mutate } }} />);
  fireEvent.click(await screen.findByRole("button", { name: "屏幕键盘" }));
  fireEvent.click(screen.getByRole("button", { name: "设计我的皮肤" }));
  const editor = screen.getByLabelText("自定义皮肤编辑器");
  await waitFor(() => expect((within(editor).getByRole("button", { name: "AI 皮肤抽卡" }) as HTMLButtonElement).disabled).toBe(false));
  fireEvent.click(within(editor).getByRole("button", { name: "AI 皮肤抽卡" }));
  fireEvent.click(screen.getByRole("button", { name: "抽三张皮肤" }));
  await screen.findByRole("heading", { name: "AI 测试 1" });
  fireEvent.click(screen.getAllByRole("button", { name: "保存到我的皮肤" })[0]);
  await screen.findByText("已保存到“我的皮肤”。");
  expect(aiSkins.generate).toHaveBeenCalledTimes(1);
  expect(mutate).toHaveBeenCalledWith(expect.objectContaining({ operation: "create", name: "AI 测试 1", design: expect.objectContaining({ photo: expect.any(String), keyOpacity: .92 }) }));
  fireEvent.click(screen.getAllByRole("button", { name: "使用并继续编辑" })[0]);
  expect(screen.queryByRole("dialog", { name: "AI 皮肤抽卡" })).toBeNull();
});

test("toolbar theme loads, previews independently, saves and reloads", async () => {
  let snapshot: Snapshot = { ...initial, preferences: { ...initial.preferences, theme: "dark", settings_theme: "dark", candidate_theme: "dark", toolbar_theme: "light" } };
  const save = vi.fn().mockImplementation(async (_revision, preferences) => {
    snapshot = { ...snapshot, revision: 8, preferences }; return snapshot;
  });
  render(<SettingsPage client={{ load: async () => snapshot, save }} />);
  const select = await screen.findByLabelText("工具栏主题") as HTMLSelectElement;
  expect(select.value).toBe("light");
  fireEvent.click(screen.getByRole("button", { name: "悬浮工具栏" }));
  const preview = screen.getByLabelText("悬浮工具栏预览").querySelector(".toolbar-settings-preview")!;
  expect(preview.getAttribute("data-preview-theme")).toBe("light");
  fireEvent.click(screen.getByRole("button", { name: "外观" }));
  fireEvent.change(select, { target: { value: "follow" } });
  expect(preview.getAttribute("data-preview-theme")).toBe("dark");
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await waitFor(() => expect(save).toHaveBeenCalledWith(7, expect.objectContaining({ toolbar_theme: "follow", candidate_theme: "dark", settings_theme: "dark" })));
  fireEvent.change(select, { target: { value: "dark" } });
  const confirm = vi.spyOn(window, "confirm").mockReturnValueOnce(true);
  fireEvent.click(screen.getByRole("button", { name: "重新读取" }));
  confirm.mockRestore();
  await waitFor(() => expect(select.value).toBe("follow"));
});

test("candidate text colour loads, previews, saves and resets to theme", async () => {
  const saved = { ...initial, preferences: { ...initial.preferences, candidate_text_color: "#123456" } };
  const save = vi.fn().mockImplementation(async (_revision, preferences) => ({ ...saved, revision: 8, preferences }));
  render(<SettingsPage client={{ load: async () => saved, save }} />);
  const color = await screen.findByLabelText("候选文字颜色") as HTMLInputElement;
  expect(color.value).toBe("#123456");
  expect(screen.getByRole("button", { name: "跟随主题" }).getAttribute("aria-pressed")).toBe("false");
  const preview = screen.getByRole("region", { name: "候选窗口预览" }).querySelector<HTMLElement>(".appearance-candidate-preview")!;
  expect(preview.style.getPropertyValue("--cand-text")).toBe("#123456");
  fireEvent.change(color, { target: { value: "#abcdef" } });
  expect(preview.style.getPropertyValue("--cand-num")).toBe("#abcdef9d");
  expect(save).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(save).toHaveBeenLastCalledWith(7, { ...saved.preferences, candidate_text_color: "#abcdef" });
  fireEvent.click(screen.getByRole("button", { name: "跟随主题" }));
  expect(preview.style.getPropertyValue("--cand-text")).toBe("");
  expect(preview.style.getPropertyValue("--cand-num")).toBe("");
  expect(color.value).toBe("#e9e8e8");
  expect(screen.getByRole("button", { name: "跟随主题" }).getAttribute("aria-pressed")).toBe("true");
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await waitFor(() => expect(save).toHaveBeenLastCalledWith(8, { ...saved.preferences, candidate_text_color: null }));
});

test("complete candidate and preedit font sizes load, preview independently and save", async () => {
  const saved = { ...initial, preferences: { ...initial.preferences, candidate_font_size: 19, candidate_preedit_font_size: 27 } };
  const save = vi.fn().mockImplementation(async (_revision, preferences) => ({ ...saved, revision: 8, preferences }));
  render(<SettingsPage client={{ load: async () => saved, save }} />);
  const size = await screen.findByLabelText("候选字号") as HTMLSelectElement;
  const preedit = screen.getByLabelText("候选窗预编辑字号") as HTMLSelectElement;
  expect(size.value).toBe("19"); expect(preedit.value).toBe("27");
  expect([...size.options].map(option => option.value)).toEqual(Array.from({ length: 21 }, (_, index) => String(index + 12)));
  expect([...preedit.options].map(option => option.value)).toEqual([...size.options].map(option => option.value));
  const preview = screen.getByRole("region", { name: "候选窗口预览" }).querySelector<HTMLElement>(".appearance-candidate-preview")!;
  for (let value = 12; value <= 32; value++) {
    fireEvent.change(size, { target: { value: String(value) } });
    fireEvent.change(preedit, { target: { value: String(44 - value) } });
    expect(preview.style.getPropertyValue("--appearance-font-size")).toBe(`${value}px`);
    expect(preview.style.getPropertyValue("--appearance-preedit-font-size")).toBe(`${44 - value}px`);
  }
  expect(save).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(save).toHaveBeenCalledWith(7, { ...saved.preferences, candidate_font_size: 32, candidate_preedit_font_size: 12 });
});

test("appearance preview follows drafts, skin selection and reload without saving", async () => {
  const save = vi.fn();
  render(<SettingsPage client={{ load: async () => initial, save }} />);
  const preview = await screen.findByRole("region", { name: "候选窗口预览" });
  expect(preview.querySelectorAll(".cand")).toHaveLength(5);
  expect(preview.querySelector('[data-preview-layout="vertical"]')).not.toBeNull();
  expect(preview.querySelector('[data-font-size="16"]')).not.toBeNull();
  fireEvent.change(screen.getByLabelText("候选布局"), { target: { value: "horizontal" } });
  fireEvent.change(screen.getByLabelText("候选字号"), { target: { value: "20" } });
  fireEvent.change(screen.getByLabelText("每页候选数量"), { target: { value: "9" } });
  fireEvent.change(screen.getByLabelText("候选窗预编辑"), { target: { value: "empty" } });
  expect(preview.querySelectorAll(".cand")).toHaveLength(9);
  expect(preview.querySelector('[data-preview-layout="horizontal"]')).not.toBeNull();
  expect(preview.querySelector('[data-font-size="20"]')).not.toBeNull();
  expect(preview.querySelector<HTMLElement>(".pinyin")?.hidden).toBe(true);
  expect(preview.querySelector(".container.preedit-hidden > .pinyin + .row-wrapper > .first")).not.toBeNull();
  fireEvent.click(screen.getByRole("button", { name: "皮肤" }));
  fireEvent.click(screen.getByRole("switch", { name: /微信绿/ }));
  fireEvent.click(screen.getByRole("button", { name: "外观" }));
  expect(preview.querySelector(".skin-wechat")).not.toBeNull();
  expect(save).not.toHaveBeenCalled();
  const confirm = vi.spyOn(window, "confirm").mockReturnValue(true);
  fireEvent.click(screen.getByRole("button", { name: "重新读取" }));
  confirm.mockRestore();
  await waitFor(() => expect(preview.querySelectorAll(".cand")).toHaveLength(5));
  expect(preview.querySelector(".skin-fluent")).not.toBeNull();
  expect(preview.querySelector(".pinyin")).not.toBeNull();
  expect(preview.querySelector<HTMLElement>(".pinyin")?.hidden).toBe(false);
  expect(preview.querySelector(".preedit-hidden")).toBeNull();
});

test("appearance preview identifies external skins instead of showing a false built-in match", async () => {
  render(<SettingsPage client={{ load: async () => ({ ...initial, preferences: { ...initial.preferences, candidate_skin: "external.sample" } }), save: vi.fn() }} />);
  const preview = await screen.findByRole("region", { name: "候选窗口预览" });
  expect(preview.textContent).toContain("当前宿主不支持扫描外部皮肤");
  expect(preview.querySelector(".candidate")).toBeNull();
});

test.each(["quanpin", "shuangpin", "wubi", "japanese"] as const)("appearance preview honors helpcode visibility for %s", async scheme => {
  render(<SettingsPage client={{ load: async () => ({ ...initial, preferences: { ...initial.preferences, scheme,
    quanpin_helpcode: { enabled: false, schema: "ziranma" }, shuangpin_helpcode: { enabled: true, schema: "ziranma" },
  } }), save: vi.fn() }} />);
  const preview = await screen.findByRole("region", { name: "候选窗口预览" });
  expect(preview.querySelectorAll(".cand-helpcode")).toHaveLength(scheme === "shuangpin" ? 5 : 0);
});

test("touch keyboard geometry mirrors Apple defaults and persists height and spacing", async () => {
  const save = vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences }));
  render(<SettingsPage client={{ load: async () => initial, save }} />);
  fireEvent.click(await screen.findByRole("button", { name: "屏幕键盘" }));
  const height = screen.getByRole("slider", { name: "键盘高度" }) as HTMLInputElement;
  const keys = screen.getByRole("slider", { name: "按键间距" }) as HTMLInputElement;
  const rows = screen.getByRole("slider", { name: "行间距" }) as HTMLInputElement;
  expect(height.value).toBe("0");
  expect(keys.value).toBe("60");
  expect(rows.value).toBe("70");
  expect(screen.getByText("0 dp")).toBeDefined();
  expect(screen.getByText("6.0 dp")).toBeDefined();
  expect(screen.getByText("7.0 dp")).toBeDefined();
  const voice = screen.getByRole("checkbox", { name: "顶部语音入口" }) as HTMLInputElement;
  expect(voice.checked).toBe(false);
  fireEvent.change(height, { target: { value: "24" } });
  fireEvent.change(keys, { target: { value: "35" } });
  fireEvent.change(rows, { target: { value: "95" } });
  fireEvent.click(voice);
  expect(screen.getByText("+24 dp")).toBeDefined();
  expect(screen.getByText("3.5 dp")).toBeDefined();
  expect(screen.getByText("9.5 dp")).toBeDefined();
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(save).toHaveBeenCalledWith(7, {
    ...initial.preferences,
    touch_keyboard_height_adjustment: 24,
    touch_key_spacing_tenths: 35,
    touch_row_spacing_tenths: 95,
    touch_voice_shortcut: true,
  });
});

test("skin preview switches are independent, reversible and do not change saved selection", async () => {
  const save = vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences }));
  const mounted = render(<SettingsPage client={{ load: async () => initial, save }} />);
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "皮肤" }));
  const cards = screen.getAllByRole("article");
  expect(cards).toHaveLength(4);
  for (const card of cards) {
    expect(card.querySelector(".skin-card-preview")?.getAttribute("data-preview-theme")).toBe("dark");
    fireEvent.click(within(card).getByRole("button", { name: "预览浅色" }));
    expect(card.querySelector(".skin-card-preview")?.getAttribute("data-preview-theme")).toBe("light");
    expect(screen.getByRole("switch", { name: /Fluent/ }).getAttribute("aria-checked")).toBe("true");
    for (const other of cards.filter(item => item !== card))
      expect(other.querySelector(".skin-card-preview")?.getAttribute("data-preview-theme")).toBe("dark");
    fireEvent.click(within(card).getByRole("button", { name: "预览深色" }));
  }
  expect(save).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole("switch", { name: /微信绿/ }));
  const wechat = mounted.container.querySelector("article .skin-wechat")!.closest("article")!;
  fireEvent.click(within(wechat).getByRole("button", { name: "预览浅色" }));
  fireEvent.click(screen.getByRole("button", { name: "外观" }));
  fireEvent.click(screen.getByRole("button", { name: "皮肤" }));
  expect(wechat.querySelector(".skin-card-preview")?.getAttribute("data-preview-theme")).toBe("light");
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(save).toHaveBeenCalledWith(7, { ...initial.preferences, candidate_skin: "wechat" });
});

test("each skin card includes both six-candidate previews without duplicate IDs", async () => {
  const mounted = render(<SettingsPage client={{ load: async () => initial, save: vi.fn() }} />);
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "皮肤" }));
  const cards = screen.getAllByRole("article");
  expect(cards).toHaveLength(4);
  for (const card of cards) {
    const previews = card.querySelectorAll("[data-preview-layout]");
    expect(previews).toHaveLength(2);
    expect(card.querySelectorAll(".ftb-preview-host .status-bar")).toHaveLength(1);
    for (const layout of ["horizontal", "vertical"]) {
      const preview = card.querySelector(`[data-preview-layout="${layout}"]`)!;
      expect(preview.querySelectorAll(".row-wrapper")).toHaveLength(6);
      expect(preview.querySelectorAll(".first")).toHaveLength(1);
      expect(preview.querySelector(".pinyin .text")?.textContent).toBe("ni'mf");
      expect(preview.querySelectorAll(".cand-helpcode")).toHaveLength(6);
      expect(preview.querySelector(".first .text")?.textContent).toBe("1你们(rR)");
      expect(Array.from(preview.querySelectorAll(layout === "horizontal" ? ".num" : ".cand-no"), node => node.textContent))
        .toEqual(["1", "2", "3", "4", "5", "6"]);
    }
  }
  expect(mounted.container.querySelectorAll("#realContainer")).toHaveLength(0);
  const ids = Array.from(mounted.container.querySelectorAll("[id]"), element => element.id);
  expect(new Set(ids).size).toBe(ids.length);
});

test("skin header controls precede previews and always keep one selected skin", async () => {
  const save = vi.fn();
  render(<SettingsPage client={{ load: async () => initial, save }} />);
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "皮肤" }));
  const cards = screen.getAllByRole("article");
  for (const card of cards) {
    const header = card.querySelector(".skin-card-header")!;
    expect(header.nextElementSibling).toBe(card.querySelector(".skin-card-preview"));
    const control = within(card).getByRole("switch");
    expect(control.tagName).toBe("BUTTON");
    expect(header.contains(control)).toBe(true);
    expect(card.querySelectorAll(".skin-preview-stage")).toHaveLength(3);
    fireEvent.click(control);
    fireEvent.click(control);
    expect(control.getAttribute("aria-checked")).toBe("true");
    expect(screen.getAllByRole("switch").filter(item => item.getAttribute("aria-checked") === "true")).toHaveLength(1);
    // Static samples cannot select a different skin by clicking their labels.
    const other = cards.find(item => item !== card)!;
    fireEvent.click(other.querySelector(".skin-card-preview")!);
    expect(control.getAttribute("aria-checked")).toBe("true");
  }
  expect(save).not.toHaveBeenCalled();
});

test("floating toolbar settings use Windows defaults and persist independently", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "悬浮工具栏" }));
  const enabled = await screen.findByRole("checkbox", { name: "在桌面显示悬浮工具栏" }) as HTMLInputElement;
  expect(enabled.checked).toBe(true);
  expect((screen.getByLabelText("工具栏缩放") as HTMLSelectElement).value).toBe("100");
  expect((screen.getByLabelText("图标尺寸") as HTMLSelectElement).value).toBe("24");
  expect((screen.getByRole("checkbox", { name: "英文输入模式" }) as HTMLInputElement).checked).toBe(true);
  expect((screen.getByRole("checkbox", { name: "全角 / 半角" }) as HTMLInputElement).checked).toBe(true);
  expect((screen.getByRole("checkbox", { name: "屏幕键盘" }) as HTMLInputElement).checked).toBe(false);
  fireEvent.change(screen.getByLabelText("工具栏缩放"), { target: { value: "125" } });
  fireEvent.change(screen.getByLabelText("图标尺寸"), { target: { value: "28" } });
  fireEvent.click(screen.getByRole("checkbox", { name: "在桌面显示悬浮工具栏" }));
  fireEvent.click(screen.getByRole("checkbox", { name: "全角 / 半角" }));
  fireEvent.click(screen.getByRole("checkbox", { name: "屏幕键盘" }));
  fireEvent.click(screen.getByRole("checkbox", { name: "英文输入模式" }));
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, floating_toolbar: {
    enabled: false, english_mode: false, fullwidth: false, punctuation: true, character_set: true, emoji: true,
    screen_keyboard: true, settings: true, scale_percent: 125, font_size: 28,
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

test("Android help and about pages use mobile instructions and project links", async () => {
  const openExternalUrl = vi.fn().mockResolvedValue(undefined);
  const client: SettingsClient = {
    load: vi.fn().mockResolvedValue(initial), save: vi.fn(), openExternalUrl,
    host: { platform: "android", floating_toolbar: false } as never,
  };
  render(<SettingsPage client={client} />);

  fireEvent.click(screen.getByRole("button", { name: "帮助" }));
  expect(await screen.findByText(/Android 平台的中文输入法/)).toBeDefined();
  expect(screen.getByText(/语言和输入法/)).toBeDefined();
  expect(screen.queryByText(/Win \+ Space/)).toBeNull();

  fireEvent.click(screen.getByRole("button", { name: "关于" }));
  expect(await screen.findByText(/Android 触屏输入体验/)).toBeDefined();
  expect(screen.queryByRole("button", { name: "悬浮工具栏" })).toBeNull();
  fireEvent.click(screen.getByRole("button", { name: "开源许可协议" }));
  await waitFor(() => expect(openExternalUrl).toHaveBeenCalledWith("https://github.com/metasequoiaime/MSIME-Client/blob/main/LICENSE"));
  fireEvent.click(screen.getByRole("button", { name: "隐私政策" }));
  await waitFor(() => expect(openExternalUrl).toHaveBeenCalledWith("https://msime.app/privacy/"));

  fireEvent.click(screen.getByRole("button", { name: "反馈" }));
  fireEvent.click(screen.getByRole("button", { name: "查看 Issues" }));
  await waitFor(() => expect(openExternalUrl).toHaveBeenCalledWith("https://github.com/metasequoiaime/MSIME-Client/issues"));
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
  fireEvent.pointerDown(canvas, { isPrimary: true, clientX: 20, clientY: 20, pointerId: 1 });
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

test("voice panel requests recognition and submits the bounded result", async () => {
  const close = vi.fn().mockResolvedValue(undefined);
  const recognizeVoice = vi.fn().mockResolvedValue({ text: "你好" });
  const sendText = vi.fn().mockResolvedValue(undefined);
  const panel = render(<VoicePanel client={{ close, recognizeVoice, sendText }} />);
  fireEvent.click(screen.getByRole("button", { name: "开始录音" }));
  await waitFor(() => expect(recognizeVoice).toHaveBeenCalledWith("zh-CN"));
  expect((screen.getByRole("textbox", { name: "识别结果" }) as HTMLTextAreaElement).value).toBe("你好");
  fireEvent.click(screen.getByRole("button", { name: "提交到当前窗口" }));
  await waitFor(() => expect(sendText).toHaveBeenCalledWith("你好"));
  fireEvent.click(screen.getByRole("button", { name: "关闭" }));
  await waitFor(() => expect(close).toHaveBeenCalledTimes(1));
});

test("cloud clipboard panel lists, uploads, deletes and submits entries", async () => {
  const close = vi.fn().mockResolvedValue(undefined);
  const sendText = vi.fn().mockResolvedValue(undefined);
  const request = vi.fn().mockImplementation(async (action: { operation: string }) => {
    if (action.operation === "list") return { items: [{ id: "entry-1", text: "云端内容" }], enabled: true };
    if (action.operation === "set_enabled") return { enabled: true };
    return { items: [{ id: "entry-1", text: "云端内容" }], enabled: true };
  });
  const panel = render(<CloudClipboardPanel client={{ close, sendText, request }} />);
  expect(await screen.findByText("云端内容")).toBeDefined();
  fireEvent.click(screen.getByRole("button", { name: "云端内容" }));
  await waitFor(() => expect(sendText).toHaveBeenCalledWith("云端内容"));
  fireEvent.change(screen.getByRole("textbox", { name: "待上传文本" }), { target: { value: "新的云端内容" } });
  fireEvent.click(screen.getByRole("button", { name: "上传明确选择的文本" }));
  await waitFor(() => expect(request).toHaveBeenCalledWith({ operation: "add", text: "新的云端内容" }));
  fireEvent.click(screen.getByRole("button", { name: "删除 云端内容" }));
  await waitFor(() => expect(request).toHaveBeenCalledWith({ operation: "delete", id: "entry-1" }));
  fireEvent.click(screen.getByRole("button", { name: "关闭" }));
  await waitFor(() => expect(close).toHaveBeenCalledTimes(1));
  panel.unmount();
});

test("cloud dictionary panel supports paging and CRUD actions", async () => {
  const close = vi.fn().mockResolvedValue(undefined);
  const request = vi.fn().mockImplementation(async (action: { operation: string; offset?: number }) => {
    if (action.operation === "list") return { entries: [{ id: "a".repeat(64), kind: "pinyin", code: "ni", word: "你", weight: 100, revision: 2 }], has_more: true, offset: action.offset ?? 0 };
    if (action.operation === "export") return { text: "ni\t你\n" };
    return {};
  });
  const panel = render(<CloudDictionaryPanel client={{ close, request }} />);
  expect(await screen.findByText("你")).toBeDefined();
  fireEvent.click(screen.getByRole("button", { name: "下一页" }));
  await waitFor(() => expect(request).toHaveBeenCalledWith({ operation: "list", kind: "pinyin", offset: 100, search: "" }));
  fireEvent.click(screen.getByRole("button", { name: "添加词条" }));
  fireEvent.change(screen.getByRole("textbox", { name: "编码" }), { target: { value: "hao" } });
  fireEvent.change(screen.getByRole("textbox", { name: "词条" }), { target: { value: "好" } });
  fireEvent.click(screen.getByRole("button", { name: "保存" }));
  await waitFor(() => expect(request).toHaveBeenCalledWith({ operation: "add", kind: "pinyin", code: "hao", word: "好", weight: 100000 }));
  fireEvent.click(screen.getByRole("button", { name: "导出" }));
  await waitFor(() => expect(request).toHaveBeenCalledWith({ operation: "export", kind: "pinyin", format: "standard" }));
  fireEvent.change(screen.getByRole("combobox", { name: "文件格式" }), { target: { value: "windows" } });
  fireEvent.click(screen.getByRole("button", { name: "导出" }));
  await waitFor(() => expect(request).toHaveBeenCalledWith({ operation: "export", kind: "pinyin", format: "windows" }));
  fireEvent.change(screen.getByRole("combobox", { name: "文件格式" }), { target: { value: "hans" } });
  expect((screen.getByRole("button", { name: "导出" }) as HTMLButtonElement).disabled).toBe(true);
  fireEvent.click(screen.getByRole("button", { name: "关闭" }));
  await waitFor(() => expect(close).toHaveBeenCalledTimes(1));
  panel.unmount();
});

test("cloud dictionary panel can queue an entry for the local dictionary", async () => {
  const close = vi.fn().mockResolvedValue(undefined);
  const confirm = vi.spyOn(window, "confirm").mockReturnValue(true);
  const entry = { id: "a".repeat(64), kind: "pinyin" as const, code: "ni", word: "你", weight: 100, revision: 2 };
  const downloadToLocal = vi.fn().mockResolvedValue(undefined);
  const request = vi.fn().mockResolvedValue({ entries: [entry], has_more: false, offset: 0 });
  const panel = render(<CloudDictionaryPanel client={{ close, request, downloadToLocal }} />);
  expect(await screen.findByText("你")).toBeDefined();
  fireEvent.click(screen.getByRole("button", { name: "下载到本机 你" }));
  expect(confirm).toHaveBeenCalledWith("确认将云词条“你”加入本机个人词典？");
  await waitFor(() => expect(downloadToLocal).toHaveBeenCalledWith(entry));
  expect(screen.getByRole("status").textContent).toContain("云词条已加入本机词典队列");
  confirm.mockRestore();
  panel.unmount();
});

test("cloud dictionary snapshot requires preview and explicit confirmation", async () => {
  const close = vi.fn().mockResolvedValue(undefined);
  const confirm = vi.spyOn(window, "confirm").mockReturnValue(true);
  const request = vi.fn().mockImplementation(async (action: { operation: string }) => {
    if (action.operation === "list") return { entries: [], has_more: false, offset: 0 };
    if (action.operation === "snapshot_preview") return {
      previewToken: "snapshot-token",
      snapshot: { cloudRevision: 42, sha256: "a".repeat(64), bytes: 2048, records: 12, entries: 4, overlays: 4, positions: 2, selections: 2 },
    };
    return { request: { id: "request", cloudRevision: 42, fileSha256: "a".repeat(64), status: action.operation === "snapshot_cancel" ? "cancelled" : "queued" } };
  });
  render(<CloudDictionaryPanel client={{ close, request, snapshot: true }} />);
  await screen.findByText("暂无词条");
  fireEvent.click(screen.getByRole("button", { name: "下载并预览" }));
  expect(await screen.findByText(/云端 revision 42/)).toBeDefined();
  expect(request).not.toHaveBeenCalledWith({ operation: "snapshot_enqueue", token: "snapshot-token" });
  fireEvent.click(screen.getByRole("button", { name: "确认加入本机" }));
  await waitFor(() => expect(request).toHaveBeenCalledWith({ operation: "snapshot_enqueue", token: "snapshot-token" }));
  expect(confirm).toHaveBeenCalledWith("确认将此云词典快照加入本机词库？输入法会在下一次空闲边界应用。");
  fireEvent.click(screen.getByRole("button", { name: "取消待应用" }));
  await waitFor(() => expect(request).toHaveBeenCalledWith({ operation: "snapshot_cancel" }));
});

test("cloud dictionary snapshot backup and restore stay behind validation and confirmation", async () => {
  const close = vi.fn().mockResolvedValue(undefined);
  const confirm = vi.spyOn(window, "confirm").mockReturnValue(true);
  const request = vi.fn().mockImplementation(async (action: { operation: string }) => {
    if (action.operation === "list") return { entries: [], has_more: false, offset: 0 };
    if (action.operation === "snapshot_export") return { text: "{\"type\":\"header\"}\n", filename: "snapshot.ndjson" };
    if (action.operation === "snapshot_restore_preview") return {
      snapshot: { cloudRevision: 7, sha256: "b".repeat(64), bytes: 20, records: 0, entries: 0, overlays: 0, positions: 0, selections: 0 },
      expectedRevision: 12,
    };
    if (action.operation === "snapshot_restore") return { revision: 13, reset: true };
    return {};
  });
  render(<CloudDictionaryPanel client={{ close, request, snapshot: true }} />);
  await screen.findByText("暂无词条");
  const file = new File(["snapshot fixture"], "snapshot.ndjson", { type: "application/x-ndjson" });
  fireEvent.change(screen.getByLabelText("恢复快照"), { target: { files: [file] } });
  expect(await screen.findByText(/当前云端 revision：12/)).toBeDefined();
  fireEvent.click(screen.getByRole("button", { name: "确认恢复云端词库" }));
  await waitFor(() => expect(request).toHaveBeenCalledWith({
    operation: "snapshot_restore", text: "snapshot fixture", expected_sha256: "b".repeat(64), revision: 12,
  }));
  expect(confirm).toHaveBeenCalledWith("确认用此快照替换全部云端词库和排序记录？");
  if (typeof URL.createObjectURL === "function") vi.spyOn(URL, "createObjectURL").mockReturnValue("blob:fixture");
  else Object.defineProperty(URL, "createObjectURL", { configurable: true, value: vi.fn(() => "blob:fixture") });
  fireEvent.click(screen.getByRole("button", { name: "导出完整快照" }));
  await waitFor(() => expect(request).toHaveBeenCalledWith({ operation: "snapshot_export" }));
});

test("cloud dictionary catalog panel queries and edits complete directory entries", async () => {
  const close = vi.fn().mockResolvedValue(undefined);
  const back = vi.fn().mockResolvedValue(undefined);
  const request = vi.fn().mockImplementation(async (action: { operation: string }) => {
    if (action.operation === "catalog") {
      return { catalog_entries: [{ kind: "pinyin", code: "ni", word: "你", weight: 100, }], has_more: false, offset: 0, revision: 42, normalized: "ni" };
    }
    return { revision: 43, previous: null, replacement: null };
  });
  render(<CloudDictionaryCatalogPanel client={{ close, back, request }} />);
  fireEvent.change(screen.getByRole("textbox", { name: "完整目录编码" }), { target: { value: "ni" } });
  fireEvent.click(screen.getByRole("button", { name: "查询完整目录" }));
  expect(await screen.findByText("你")).toBeDefined();
  fireEvent.click(screen.getByRole("button", { name: "编辑" }));
  fireEvent.change(screen.getByRole("textbox", { name: "词条" }), { target: { value: "你们" } });
  fireEvent.click(screen.getByRole("button", { name: "保存" }));
  await waitFor(() => expect(request).toHaveBeenCalledWith({ operation: "edit_catalog", kind: "pinyin", code: "ni", word: "你", revision: 42, replacement: { code: "ni", word: "你们", weight: 100 } }));
  fireEvent.click(screen.getByRole("button", { name: "返回云词典" }));
  await waitFor(() => expect(back).toHaveBeenCalledTimes(1));
  fireEvent.click(screen.getByRole("button", { name: "关闭" }));
  await waitFor(() => expect(close).toHaveBeenCalledTimes(1));
});

test("cloud candidates panel uses canonical pinyin and manages ranking and fixed positions", async () => {
  const close = vi.fn().mockResolvedValue(undefined);
  const back = vi.fn().mockResolvedValue(undefined);
  const confirm = vi.spyOn(window, "confirm").mockReturnValue(true);
  const request = vi.fn().mockImplementation(async (action: { operation: string }) => {
    if (action.operation === "candidates") return { candidates: [{ code: "nihc", canonical_pinyin: "ni'hao", word: "你好", weight: 10 }], context: "server:context", revision: 42 };
    if (action.operation === "fixed_positions") return { positions: [{ context: "server:context", code: "ni'hao", word: "你好", position: 1 }], offset: 0, has_more: false };
    if (action.operation === "rank") return { revision: 43, changed: true, selection_count: 0 };
    return { revision: 43 };
  });
  render(<CloudCandidatesPanel client={{ close, back, request }} />);
  fireEvent.change(screen.getByRole("textbox", { name: "云端候选编码" }), { target: { value: "nihc" } });
  fireEvent.click(screen.getByRole("button", { name: "查询云端候选" }));
  expect(await screen.findByText("你好")).toBeDefined();
  fireEvent.click(screen.getByRole("button", { name: "调频" }));
  await waitFor(() => expect(request).toHaveBeenCalledWith(expect.objectContaining({ operation: "rank", code: "ni'hao", revision: 42 })));
  fireEvent.click(screen.getByRole("button", { name: "固定" }));
  await waitFor(() => expect(request).toHaveBeenCalledWith(expect.objectContaining({ operation: "set_fixed_position", code: "ni'hao", position: 1 })));
  fireEvent.click(screen.getByRole("button", { name: "取消固定" }));
  await waitFor(() => expect(request).toHaveBeenCalledWith(expect.objectContaining({ operation: "set_fixed_position", position: null })));
  fireEvent.click(screen.getByRole("button", { name: "返回云词典" }));
  await waitFor(() => expect(back).toHaveBeenCalledTimes(1));
  fireEvent.click(screen.getByRole("button", { name: "关闭" }));
  await waitFor(() => expect(close).toHaveBeenCalledTimes(1));
  confirm.mockRestore();
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

test("legacy autocorrect seeds both correction toggles and saves them separately", async () => {
  const client: SettingsClient = { load: vi.fn().mockResolvedValue(initial), save: vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 8, preferences })) };
  render(<SettingsPage client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "输入" }));
  // A configuration that only knows the old single switch starts with both
  // granular corrections on.
  const transposition = await screen.findByLabelText("全拼纠错：字母顺序错位") as HTMLInputElement;
  const neighbor = screen.getByLabelText("全拼纠错：相邻键误触") as HTMLInputElement;
  expect(transposition.checked).toBe(true);
  expect(neighbor.checked).toBe(true);
  fireEvent.click(transposition);
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, {
    ...initial.preferences,
    quanpin: { autocorrect_transposition: false, autocorrect_neighbor: true },
  });
  expect(transposition.checked).toBe(false);
  expect(neighbor.checked).toBe(true);
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
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, candidate_page_size: 9, quanpin_helpcode: { enabled: false, schema: "ziranma", show_in_candidate_window: true } });
  expect(client.load).toHaveBeenCalledTimes(1);
});


test.each(["undo", "clear", "next stroke", "host replacement"])("handwriting ignores delayed recognition after %s", async action => {
  let resolve!: (result: { candidates: string[] }) => void;
  const recognizeHandwriting = vi.fn(() => new Promise<{ candidates: string[] }>(done => { resolve = done; }));
  const client = { close: vi.fn().mockResolvedValue(undefined), recognizeHandwriting };
  const panel = render(<HandwritingPanel client={client} />);
  const canvas = screen.getByLabelText("手写画布");
  fireEvent.pointerDown(canvas, { isPrimary: true, clientX: 20, clientY: 20, pointerId: 1 });
  fireEvent.pointerMove(canvas, { clientX: 80, clientY: 80, pointerId: 1 });
  fireEvent.pointerUp(canvas, { pointerId: 1 });
  expect(recognizeHandwriting).toHaveBeenCalledTimes(1);
  if (action === "undo") fireEvent.click(screen.getByRole("button", { name: /撤销/ }));
  if (action === "clear") fireEvent.click(screen.getByRole("button", { name: /重写/ }));
  if (action === "next stroke") fireEvent.pointerDown(canvas, { isPrimary: true, clientX: 30, clientY: 30, pointerId: 2 });
  if (action === "host replacement") panel.rerender(<HandwritingPanel client={{ close: client.close }} />);
  await act(async () => resolve({ candidates: ["fixture-stale"] }));
  expect(screen.queryByRole("button", { name: "fixture-stale" })).toBeNull();
  if (action === "next stroke") {
    fireEvent.pointerMove(canvas, { clientX: 90, clientY: 90, pointerId: 2 });
    fireEvent.pointerUp(canvas, { pointerId: 2 });
    await act(async () => resolve({ candidates: ["fixture-current"] }));
    expect(screen.getByRole("button", { name: "fixture-current" })).toBeDefined();
  }
});

test("a host can open the settings window on the section its menu named", async () => {
  const client: SettingsClient = { load: async () => initial, save: vi.fn() };
  render(<SettingsPage client={client} initialPage="about" />);
  expect(await screen.findByRole("heading", { name: "关于" })).toBeDefined();
  cleanup();

  // An id this build does not have keeps the default section rather than
  // opening an empty one.
  render(<SettingsPage client={client} initialPage="not-a-page" />);
  await screen.findByRole("button", { name: "保存设置" });
  expect(screen.getByRole("heading", { name: "外观" })).toBeDefined();
});
