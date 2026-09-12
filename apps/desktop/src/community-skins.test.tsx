// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import {
  CommunitySkinsPage,
  SettingsPage,
  type CommunitySkin,
  type CommunitySkinClient,
  type CommunitySkinPage,
  type Snapshot,
} from "@msime/ui";

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

const preferences: Snapshot = {
  format_version: 1,
  revision: 1,
  preferences: {
    scheme: "quanpin",
    shuangpin_profile: "xiaohe",
    candidate_page_size: 5,
    learning: true,
    chinese_punctuation: true,
  },
};

const design = {
  background: 0xE8F0EB,
  keyBackground: 0xFFFFFF,
  keyForeground: 0x17251D,
  accent: 0x185C47,
  actionBackground: 0x185C47,
  cornerRadius: 8,
  borderWidth: 0,
  shadow: 0,
  pattern: 0 as const,
  monospaced: false,
};

function skin(id: string, name: string): CommunitySkin {
  return {
    id,
    name,
    description: `${name} 的公开说明`,
    author: "示例作者",
    design,
    downloads: 12,
    rating_count: 2,
    rating_average: 4.5,
    owned: false,
    my_rating: 0,
  };
}

function client(overrides: Partial<CommunitySkinClient> = {}): CommunitySkinClient {
  return {
    list: vi.fn().mockResolvedValue({ skins: [], has_more: false }),
    detail: vi.fn().mockImplementation(async id => skin(id, "详情皮肤")),
    download: vi.fn().mockResolvedValue({ skin: skin("10000000-0000-4000-8000-000000000099", "下载皮肤"), trial: { id: "trial", name: "下载皮肤" } }),
    rate: vi.fn().mockResolvedValue(undefined),
    publish: vi.fn().mockResolvedValue(undefined),
    unpublish: vi.fn().mockResolvedValue(undefined),
    finishTrial: vi.fn().mockResolvedValue(undefined),
    ...overrides,
  };
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>(accept => { resolve = accept; });
  return { promise, resolve };
}

test("settings expose community only with the Android capability and omit preference actions", async () => {
  const without = render(<SettingsPage client={{ load: async () => preferences, save: vi.fn() }} />);
  await screen.findByRole("button", { name: "保存设置" });
  expect(screen.queryByRole("button", { name: "社区" })).toBeNull();
  without.unmount();

  const communitySkins = client();
  render(<SettingsPage client={{ load: async () => preferences, save: vi.fn(), communitySkins }} initialPage="community" />);
  expect(await screen.findByRole("heading", { name: "社区" })).not.toBeNull();
  await waitFor(() => expect(communitySkins.list).toHaveBeenCalledWith(0, ""));
  expect(screen.queryByRole("button", { name: "保存设置" })).toBeNull();
  expect(screen.queryByRole("button", { name: "重新读取" })).toBeNull();
});

test("initial load and submitted search preserve the exact query", async () => {
  const communitySkins = client();
  render(<CommunitySkinsPage client={communitySkins} theme="light" />);
  await waitFor(() => expect(communitySkins.list).toHaveBeenCalledWith(0, ""));
  fireEvent.change(screen.getByRole("textbox", { name: "搜索皮肤设计" }), { target: { value: " C++ 星 " } });
  fireEvent.click(screen.getByRole("button", { name: "搜索" }));
  await waitFor(() => expect(communitySkins.list).toHaveBeenLastCalledWith(0, " C++ 星 "));
});

test("load more advances the transport offset and removes duplicate ids", async () => {
  const first = skin("10000000-0000-4000-8000-000000000001", "第一款");
  const second = skin("10000000-0000-4000-8000-000000000002", "第二款");
  const third = skin("10000000-0000-4000-8000-000000000003", "第三款");
  const list = vi.fn()
    .mockResolvedValueOnce({ skins: [first, second], has_more: true })
    .mockResolvedValueOnce({ skins: [second, third], has_more: false });
  render(<CommunitySkinsPage client={client({ list })} theme="dark" />);
  fireEvent.click(await screen.findByRole("button", { name: "加载更多" }));
  await waitFor(() => expect(list).toHaveBeenLastCalledWith(2, ""));
  expect(await screen.findByRole("button", { name: "查看皮肤 第三款" })).not.toBeNull();
  expect(screen.getAllByRole("button", { name: /查看皮肤/ })).toHaveLength(3);
});

test("an older response cannot replace a newer search", async () => {
  const oldPage = deferred<CommunitySkinPage>();
  const newer = skin("10000000-0000-4000-8000-000000000004", "新搜索结果");
  const list = vi.fn()
    .mockReturnValueOnce(oldPage.promise)
    .mockResolvedValueOnce({ skins: [newer], has_more: false });
  render(<CommunitySkinsPage client={client({ list })} theme="dark" />);
  await waitFor(() => expect(list).toHaveBeenCalledTimes(1));
  fireEvent.change(screen.getByRole("textbox", { name: "搜索皮肤设计" }), { target: { value: "新查询" } });
  fireEvent.submit(screen.getByRole("search"));
  expect(await screen.findByRole("button", { name: "查看皮肤 新搜索结果" })).not.toBeNull();
  oldPage.resolve({ skins: [skin("10000000-0000-4000-8000-000000000005", "迟到旧结果")], has_more: false });
  await waitFor(() => expect(screen.queryByRole("button", { name: "查看皮肤 迟到旧结果" })).toBeNull());
  expect(screen.getByRole("button", { name: "查看皮肤 新搜索结果" })).not.toBeNull();
});

test("opening a card refreshes detail without mutating preferences or the local library", async () => {
  const original = skin("10000000-0000-4000-8000-000000000006", "列表名称");
  const detail = vi.fn().mockResolvedValue({ ...original, name: "详情名称", description: "详细说明" });
  const communitySkins = client({ list: vi.fn().mockResolvedValue({ skins: [original], has_more: false }), detail });
  const save = vi.fn();
  const mutate = vi.fn();
  render(<SettingsPage client={{ load: async () => preferences, save, communitySkins,
    customSkinLibrary: { load: vi.fn().mockResolvedValue([]), mutate } }} initialPage="community" />);
  fireEvent.click(await screen.findByRole("button", { name: "查看皮肤 列表名称" }));
  await waitFor(() => expect(detail).toHaveBeenCalledWith(original.id));
  expect(await screen.findByRole("heading", { name: "详情名称" })).not.toBeNull();
  expect(screen.getByText("详细说明")).not.toBeNull();
  expect(save).not.toHaveBeenCalled();
  expect(mutate).not.toHaveBeenCalled();
});

test("community failures use stable messages and never expose backend details", async () => {
  const communitySkins = client({
    list: vi.fn().mockRejectedValue({ code: "community_rate_limited", message: "private backend detail" }),
  });
  render(<CommunitySkinsPage client={communitySkins} theme="dark" />);
  expect((await screen.findByRole("alert")).textContent).toBe("请求过于频繁，请稍后再试。");
  expect(screen.queryByText(/private backend detail/)).toBeNull();
});

test("downloads enter a recoverable trial and can restore the previous skin", async () => {
  const original = skin("10000000-0000-4000-8000-000000000007", "可试用皮肤");
  const downloaded = { ...original, design: { ...design, background: 0x123456 } };
  const download = vi.fn().mockResolvedValue({
    skin: downloaded,
    trial: { id: "20000000-0000-4000-8000-000000000001", name: original.name },
  });
  const finishTrial = vi.fn().mockResolvedValue(undefined);
  render(<CommunitySkinsPage client={client({
    list: vi.fn().mockResolvedValue({ skins: [original], has_more: false }),
    detail: vi.fn().mockResolvedValue(original), download, finishTrial,
  })} theme="dark" />);
  fireEvent.click(await screen.findByRole("button", { name: `查看皮肤 ${original.name}` }));
  fireEvent.click(await screen.findByRole("button", { name: "下载并试用" }));
  await waitFor(() => expect(download).toHaveBeenCalledWith(original.id, original.name));
  expect(await screen.findByText(`正在试用：${original.name}`)).not.toBeNull();
  fireEvent.click(screen.getByRole("button", { name: "恢复原皮肤" }));
  await waitFor(() => expect(finishTrial).toHaveBeenCalledWith(
    "20000000-0000-4000-8000-000000000001", false,
  ));
  expect(await screen.findByText("已恢复试用前的皮肤。")).not.toBeNull();
});

test("leaving an active trial restores it and keeping it suppresses later recovery", async () => {
  const original = skin("10000000-0000-4000-8000-000000000008", "退出恢复皮肤");
  const finishTrial = vi.fn().mockResolvedValue(undefined);
  const communitySkins = client({
    list: vi.fn().mockResolvedValue({ skins: [original], has_more: false }),
    detail: vi.fn().mockResolvedValue(original),
    download: vi.fn().mockResolvedValue({
      skin: original,
      trial: { id: "20000000-0000-4000-8000-000000000002", name: original.name },
    }),
    finishTrial,
  });
  const view = render(<CommunitySkinsPage client={communitySkins} theme="light" />);
  fireEvent.click(await screen.findByRole("button", { name: `查看皮肤 ${original.name}` }));
  fireEvent.click(await screen.findByRole("button", { name: "下载并试用" }));
  await screen.findByRole("button", { name: "保留使用" });
  view.unmount();
  await waitFor(() => expect(finishTrial).toHaveBeenCalledWith(
    "20000000-0000-4000-8000-000000000002", false,
  ));
});

test("rating refreshes detail while owned skins omit rating controls", async () => {
  const original = skin("10000000-0000-4000-8000-000000000009", "评分皮肤");
  const rated = { ...original, my_rating: 4, rating_count: 3, rating_average: 4.3 };
  const detail = vi.fn().mockResolvedValueOnce(original).mockResolvedValueOnce(rated);
  const rate = vi.fn().mockResolvedValue(undefined);
  const view = render(<CommunitySkinsPage client={client({
    list: vi.fn().mockResolvedValue({ skins: [original], has_more: false }), detail, rate,
  })} theme="dark" />);
  fireEvent.click(await screen.findByRole("button", { name: `查看皮肤 ${original.name}` }));
  fireEvent.click(await screen.findByRole("button", { name: "评 4 星" }));
  await waitFor(() => expect(rate).toHaveBeenCalledWith(original.id, 4));
  expect(await screen.findByText("我的评分：4 星")).not.toBeNull();
  view.unmount();

  const owned = { ...original, id: "10000000-0000-4000-8000-000000000010", owned: true };
  render(<CommunitySkinsPage client={client({
    list: vi.fn().mockResolvedValue({ skins: [owned], has_more: false }),
    detail: vi.fn().mockResolvedValue(owned),
  })} theme="dark" />);
  fireEvent.click(await screen.findByRole("button", { name: `查看皮肤 ${owned.name}` }));
  await screen.findByRole("heading", { name: owned.name });
  expect(screen.queryByRole("button", { name: "评 4 星" })).toBeNull();
});

test("publishes a selected local design only after explicit rights confirmation", async () => {
  const local = { id: "30000000-0000-4000-8000-000000000001", name: "我的森林", design };
  const publish = vi.fn().mockResolvedValue(undefined);
  const list = vi.fn().mockResolvedValue({ skins: [], has_more: false });
  render(<CommunitySkinsPage client={client({ list, publish })} theme="light" localSkinLibrary={{
    load: vi.fn().mockResolvedValue([local]),
    mutate: vi.fn(),
  }} />);
  fireEvent.click(await screen.findByRole("button", { name: "发布我的设计" }));
  expect(await screen.findByRole("dialog", { name: "发布我的皮肤" })).not.toBeNull();
  const submit = screen.getByRole("button", { name: "公开发布" }) as HTMLButtonElement;
  expect(submit.disabled).toBe(true);
  fireEvent.click(screen.getByRole("checkbox", { name: "确认拥有发布素材权利" }));
  fireEvent.click(submit);
  await waitFor(() => expect(publish).toHaveBeenCalledWith(
    expect.stringMatching(/^[0-9a-f-]{36}$/), "我的森林", "", design,
  ));
  await waitFor(() => expect(screen.queryByRole("dialog", { name: "发布我的皮肤" })).toBeNull());
});

test("keeps the publication id for retries but changes it when metadata changes", async () => {
  const local = { id: "30000000-0000-4000-8000-000000000002", name: "可重试设计", design };
  const publish = vi.fn().mockRejectedValue(new Error("temporary failure"));
  render(<CommunitySkinsPage client={client({ publish })} theme="light" localSkinLibrary={{
    load: vi.fn().mockResolvedValue([local]),
    mutate: vi.fn(),
  }} />);
  fireEvent.click(await screen.findByRole("button", { name: "发布我的设计" }));
  fireEvent.click(await screen.findByRole("checkbox", { name: "确认拥有发布素材权利" }));
  const submit = screen.getByRole("button", { name: "公开发布" });
  fireEvent.click(submit);
  await waitFor(() => expect(publish).toHaveBeenCalledTimes(1));
  fireEvent.click(submit);
  await waitFor(() => expect(publish).toHaveBeenCalledTimes(2));
  expect(publish.mock.calls[1][0]).toBe(publish.mock.calls[0][0]);

  fireEvent.change(screen.getByRole("textbox", { name: "发布皮肤名称" }), { target: { value: "另一款设计" } });
  fireEvent.click(submit);
  await waitFor(() => expect(publish).toHaveBeenCalledTimes(3));
  expect(publish.mock.calls[2][0]).not.toBe(publish.mock.calls[0][0]);
});

test("my works scope filters owned skins and can unpublish with confirmation", async () => {
  const mine = { ...skin("40000000-0000-4000-8000-000000000001", "我的公开皮肤"), owned: true };
  const publicSkin = skin("40000000-0000-4000-8000-000000000002", "别人的皮肤");
  const list = vi.fn().mockResolvedValue({ skins: [mine, publicSkin], has_more: false });
  const detail = vi.fn().mockResolvedValue(mine);
  const unpublish = vi.fn().mockResolvedValue(undefined);
  render(<CommunitySkinsPage client={client({ list, detail, unpublish })} theme="dark" />);
  fireEvent.click(await screen.findByRole("button", { name: "我的作品" }));
  expect(await screen.findByRole("button", { name: "查看皮肤 我的公开皮肤" })).not.toBeNull();
  expect(screen.queryByRole("button", { name: "查看皮肤 别人的皮肤" })).toBeNull();
  fireEvent.click(screen.getByRole("button", { name: "查看皮肤 我的公开皮肤" }));
  fireEvent.click(await screen.findByRole("button", { name: "下架这款皮肤" }));
  expect(screen.getByRole("alertdialog", { name: "确认下架皮肤" })).not.toBeNull();
  fireEvent.click(screen.getByRole("button", { name: "确认下架" }));
  await waitFor(() => expect(unpublish).toHaveBeenCalledWith(mine.id));
  await waitFor(() => expect(list).toHaveBeenCalledTimes(3));
});
