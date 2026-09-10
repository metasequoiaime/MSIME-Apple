// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { SettingsPage, type SettingsClient, type Snapshot } from "@msime/ui";

afterEach(cleanup);

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
  const profile = await screen.findByLabelText("双拼方案") as HTMLSelectElement;
  expect(profile.disabled).toBe(true);
  fireEvent.change(screen.getByLabelText("输入方案"), { target: { value: "shuangpin" } });
  expect(profile.disabled).toBe(false);
  fireEvent.change(profile, { target: { value: "microsoft" } });
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await screen.findByText("设置已保存。");
  expect(client.save).toHaveBeenCalledWith(7, { ...initial.preferences, scheme: "shuangpin", shuangpin_profile: "microsoft" });
  fireEvent.change(screen.getByLabelText("输入方案"), { target: { value: "quanpin" } });
  expect(profile.disabled).toBe(true);
  expect(profile.value).toBe("microsoft");
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
