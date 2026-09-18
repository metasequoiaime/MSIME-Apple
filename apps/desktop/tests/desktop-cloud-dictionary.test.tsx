// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { DesktopCloudDictionary } from "../src/desktop-cloud-dictionary";
import { CloudCandidatesPanel, CloudDictionaryCatalogPanel } from "@msime/ui";

afterEach(cleanup);

test("catalog discards entries and editing state when the account request fails", async () => {
  const request = vi.fn().mockResolvedValue({ catalog_entries: [{ kind: "pinyin", code: "he", word: "合成", weight: 1 }], offset: 0, has_more: true, revision: 1, normalized: "he" });
  render(<CloudDictionaryCatalogPanel client={{ close: async () => {}, request }} />);
  fireEvent.change(screen.getByRole("textbox", { name: "完整目录编码" }), { target: { value: "he" } });
  fireEvent.click(screen.getByRole("button", { name: "查询完整目录" }));
  expect(await screen.findByText("合成")).toBeTruthy();
  fireEvent.click(screen.getByRole("button", { name: "编辑" }));
  request.mockRejectedValue(new Error("unavailable"));
  fireEvent.click(screen.getByRole("button", { name: "查询完整目录" }));
  await waitFor(() => expect(screen.queryByText("合成")).toBeNull());
  expect(screen.queryByRole("button", { name: "保存" })).toBeNull();
});

test("candidate lookup failure removes old candidates and fixed positions", async () => {
  const request = vi.fn().mockImplementation(async ({ operation }) => operation === "candidates"
    ? { candidates: [{ code: "he", word: "合成", weight: 1 }], context: "pinyin:he", revision: 1 }
    : { positions: [{ context: "pinyin:he", code: "he", word: "合成", position: 1 }] });
  render(<CloudCandidatesPanel client={{ close: async () => {}, request }} />);
  fireEvent.change(screen.getByRole("textbox", { name: "云端候选编码" }), { target: { value: "he" } });
  fireEvent.click(screen.getByRole("button", { name: "查询云端候选" }));
  expect(await screen.findByRole("button", { name: "取消固定" })).toBeTruthy();
  request.mockRejectedValue(new Error("unavailable"));
  fireEvent.click(screen.getByRole("button", { name: "查询云端候选" }));
  await waitFor(() => expect(screen.queryByRole("button", { name: "调频" })).toBeNull());
  expect(screen.queryByRole("button", { name: "取消固定" })).toBeNull();
});

test("desktop dictionary subpages reuse the session client and return without closing its window", async () => {
  const close = vi.fn().mockResolvedValue(undefined);
  const request = vi.fn().mockResolvedValue({ entries: [], has_more: false, offset: 0 });
  render(<DesktopCloudDictionary client={{ close, request }} />);
  await waitFor(() => expect(request).toHaveBeenCalledWith(expect.objectContaining({ operation: "list" })));
  fireEvent.click(screen.getByRole("button", { name: "完整目录" }));
  expect(screen.getByText("完整云词库目录")).toBeTruthy();
  fireEvent.click(screen.getByRole("button", { name: "返回云词典" }));
  await waitFor(() => expect(screen.getByRole("button", { name: "云端候选排序" }).hasAttribute("disabled")).toBe(false));
  fireEvent.click(screen.getByRole("button", { name: "云端候选排序" }));
  expect(screen.getByText("仅在点击查询时发送编码；修改只保存到当前账号")).toBeTruthy();
  expect(close).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole("button", { name: "关闭" }));
  expect(close).toHaveBeenCalledTimes(1);
});

test("desktop dictionary apply page previews, confirms and cancels through the shared queue", async () => {
  const close = vi.fn().mockResolvedValue(undefined);
  const confirm = vi.spyOn(window, "confirm").mockReturnValue(true);
  const request = vi.fn().mockImplementation(async (action: { operation: string }) => {
    if (action.operation === "list") return { entries: [], has_more: false, offset: 0 };
    if (action.operation === "snapshot_status") return { localVersion: "local-v1", request: null };
    if (action.operation === "snapshot_preview") return { previewToken: "preview-token", snapshot: { cloudRevision: 7, sha256: "a".repeat(64), bytes: 128, records: 4, entries: 2, overlays: 1, positions: 1, selections: 0 } };
    if (action.operation === "snapshot_enqueue") return { request: { id: "request", cloudRevision: 7, status: "queued" } };
    if (action.operation === "snapshot_cancel") return { request: { id: "request", cloudRevision: 7, status: "cancelled" } };
    return {};
  });
  render(<DesktopCloudDictionary client={{ close, request, snapshot: true }} />);
  await waitFor(() => expect(request).toHaveBeenCalledWith({ operation: "list", kind: "pinyin", offset: 0, search: "" }));
  fireEvent.click(screen.getByRole("button", { name: "应用到本机" }));
  await waitFor(() => expect(screen.getByText("已获取本机词库版本")).toBeTruthy());
  fireEvent.click(screen.getByRole("button", { name: "下载云词库并预览" }));
  expect(await screen.findByText(/云端 revision 7/)).toBeTruthy();
  fireEvent.click(screen.getByRole("button", { name: "替换本机词库" }));
  await waitFor(() => expect(request).toHaveBeenCalledWith({ operation: "snapshot_enqueue", token: "preview-token" }));
  fireEvent.click(screen.getByRole("button", { name: "取消待应用快照" }));
  await waitFor(() => expect(request).toHaveBeenCalledWith({ operation: "snapshot_cancel" }));
  expect(confirm).toHaveBeenCalledWith(expect.stringContaining("确认用这份云端快照替换"));
  confirm.mockRestore();
});

test("desktop dictionary file page reuses the authenticated client and returns to entries", async () => {
  const close = vi.fn().mockResolvedValue(undefined);
  const request = vi.fn().mockImplementation(async (action: { operation: string }) => action.operation === "export" ? { text: "ni\t你\n" } : { entries: [], has_more: false, offset: 0 });
  render(<DesktopCloudDictionary client={{ close, request }} />);
  await waitFor(() => expect(request).toHaveBeenCalledWith(expect.objectContaining({ operation: "list" })));
  fireEvent.click(screen.getByRole("button", { name: "导入与导出" }));
  expect(screen.getByText("导入与导出")).toBeTruthy();
  fireEvent.click(screen.getByRole("button", { name: "返回云词典" }));
  await waitFor(() => expect(screen.getByRole("button", { name: "导入与导出" })).toBeTruthy());
  expect(close).not.toHaveBeenCalled();
});
