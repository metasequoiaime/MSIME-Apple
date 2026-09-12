// @vitest-environment jsdom
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { AppearanceCandidatePreview } from "../../../packages/ui/src/appearance-candidate-preview";
import type { Preferences, SkinCatalog } from "@msime/ui";

afterEach(cleanup);
beforeEach(() => Object.defineProperty(document, "adoptedStyleSheets", { configurable: true, writable: true, value: [] }));
const preferences: Preferences = { scheme: "quanpin", shuangpin_profile: "xiaohe", candidate_page_size: 4,
  learning: true, chinese_punctuation: true, candidate_skin: "sample" };
const catalog: SkinCatalog = { directory: "/synthetic/skins", issues: [], packages: [{ id: "sample", name: "Sample", version: "1",
  base: "fluent", author: null, description: null, layouts: ["horizontal", "vertical"], themes: ["dark"],
  minWidthDip: 100, decorationTopDip: 20, decorationWidthDip: 100, toolbarStylesheet: null, preview: "sample.svg",
  candidate: { dark: { surface: "#123456" }, light: {} },
}] };
const image = { contentType: "image/svg+xml", bytes: [...new TextEncoder().encode('<svg xmlns="http://www.w3.org/2000/svg"/>')] };

test("external appearance loads palette/image, updates draft, refreshes and cleans up", async () => {
  const scan = vi.fn().mockResolvedValue(catalog), readImage = vi.fn().mockResolvedValue(image);
  const view = render(<AppearanceCandidatePreview preferences={preferences} scan={scan} readImage={readImage} />);
  await waitFor(() => expect(view.container.querySelector("img.skin-decoration-image")).not.toBeNull());
  expect(scan).toHaveBeenCalledTimes(1);
  expect(readImage).toHaveBeenCalledExactlyOnceWith("sample", "sample.svg");
  expect(view.container.querySelectorAll(".cand")).toHaveLength(4);
  expect(document.adoptedStyleSheets).toHaveLength(1);
  expect(document.adoptedStyleSheets[0].cssRules[0].cssText).toContain("rgb(18, 52, 86)");
  view.rerender(<AppearanceCandidatePreview preferences={{ ...preferences, candidate_layout: "horizontal", candidate_page_size: 9 }} scan={scan} readImage={readImage} />);
  expect(view.container.querySelectorAll(".wnd-h .cand")).toHaveLength(9);
  expect(scan).toHaveBeenCalledTimes(1);
  fireEvent.click(screen.getByRole("button", { name: "刷新预览" }));
  await waitFor(() => expect(readImage).toHaveBeenCalledTimes(2));
  expect(document.adoptedStyleSheets).toHaveLength(1);
  view.unmount();
  expect(document.adoptedStyleSheets).toHaveLength(0);
});

test("late catalog from a replaced host cannot overwrite the current preview", async () => {
  let resolve!: (value: SkinCatalog) => void;
  const scan = () => new Promise<SkinCatalog>(done => { resolve = done; });
  const view = render(<AppearanceCandidatePreview preferences={preferences} scan={scan} />);
  const replacement = vi.fn().mockResolvedValue({ ...catalog, packages: [] });
  view.rerender(<AppearanceCandidatePreview preferences={preferences} scan={replacement} />);
  await screen.findByText(/未找到所选皮肤/);
  await act(async () => resolve(catalog));
  expect(view.container.querySelector(".candidate")).toBeNull();
  expect(document.adoptedStyleSheets).toHaveLength(0);
});

test("hidden appearance does not scan and switching to a builtin discards pending results", async () => {
  let resolve!: (value: SkinCatalog) => void;
  const scan = vi.fn(() => new Promise<SkinCatalog>(done => { resolve = done; }));
  const readImage = vi.fn();
  const view = render(<AppearanceCandidatePreview preferences={preferences} scan={scan} readImage={readImage} active={false} />);
  expect(scan).not.toHaveBeenCalled();
  view.rerender(<AppearanceCandidatePreview preferences={preferences} scan={scan} readImage={readImage} />);
  expect(scan).toHaveBeenCalledTimes(1);
  view.rerender(<AppearanceCandidatePreview preferences={{ ...preferences, candidate_skin: "wechat" }} scan={scan} readImage={readImage} />);
  await act(async () => resolve(catalog));
  expect(view.container.querySelector(".skin-wechat")).not.toBeNull();
  expect(readImage).not.toHaveBeenCalled();
  expect(document.adoptedStyleSheets).toHaveLength(0);
});

test("scan failure can retry; incompatible layout never shows a misleading candidate", async () => {
  const scan = vi.fn().mockRejectedValueOnce(Error("synthetic failure")).mockResolvedValue({ ...catalog,
    packages: [{ ...catalog.packages[0], layouts: ["horizontal"] }],
  });
  const view = render(<AppearanceCandidatePreview preferences={preferences} scan={scan} />);
  await screen.findByText(/读取所选皮肤失败/);
  fireEvent.click(screen.getByRole("button", { name: "刷新预览" }));
  await screen.findByText(/所选皮肤不支持/);
  expect(view.container.querySelector(".candidate")).toBeNull();
  expect(document.adoptedStyleSheets).toHaveLength(0);
});

test("image failures retain palette and report the limitation", async () => {
  const view = render(<AppearanceCandidatePreview preferences={preferences} scan={async () => catalog} readImage={async () => { throw Error("synthetic failure"); }} />);
  await screen.findByText(/皮肤图片加载失败/);
  expect(view.container.querySelectorAll(".cand")).toHaveLength(4);
  expect(document.adoptedStyleSheets).toHaveLength(1);
});
