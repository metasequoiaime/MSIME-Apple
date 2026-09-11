// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { act, cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { ExternalSkins } from "../../../packages/ui/src/external-skins";
import { SettingsPage, type SkinCatalog, type Snapshot } from "@msime/ui";
import geometryCss from "../../../packages/ui/src/external-skin-geometry.css?raw";

afterEach(cleanup);
const catalog: SkinCatalog = {
  directory: "/synthetic/state/skins", issues: [{ folder: "Bad", reason: "invalid manifest" }],
  packages: [{ id: "sample", name: "Sample skin", version: "1", base: "fluent", author: "Example", description: "Sample description",
    layouts: ["horizontal"], themes: ["dark", "light"], minWidthDip: 0, decorationTopDip: 0, decorationWidthDip: 0,
    toolbarStylesheet: null, preview: null, candidate: { dark: { surface: "#123456" }, light: { surface: "#abcdef" } } }],
};
const initial: Snapshot = { format_version: 1, revision: 3, preferences: {
  scheme: "quanpin", shuangpin_profile: "xiaohe", candidate_page_size: 6, candidate_layout: "horizontal", learning: true, chinese_punctuation: true,
} };
const props = { selected: "fluent", layout: "horizontal", onSelect: vi.fn() };
function refresh() { fireEvent.click(screen.getByRole("button", { name: "刷新皮肤" })); }

test("decorated previews preserve upstream geometry in both layouts without decorating toolbar", async () => {
  render(<ExternalSkins {...props} scan={async () => ({ ...catalog, packages: [{ ...catalog.packages[0],
    minWidthDip: 280.5, decorationTopDip: 32.5, decorationWidthDip: 150 }] })} />);
  refresh();
  const card = await screen.findByRole("article");
  expect(card.classList.contains("external-skin-decorated")).toBe(true);
  const preview = card.querySelector<HTMLElement>(".skin-card-preview")!;
  expect(preview.style.getPropertyValue("--msime-skin-min-width")).toBe("280.5px");
  expect(preview.style.getPropertyValue("--msime-skin-decoration-top")).toBe("32.5px");
  expect(preview.style.getPropertyValue("--msime-skin-decoration-width")).toBe("150px");
  for (const layout of ["horizontal", "vertical"]) {
    expect(card.querySelector(`[data-preview-layout="${layout}"] > .containerParent > .container`)).not.toBeNull();
  }
  expect(card.querySelectorAll(".containerParent")).toHaveLength(2);
  expect(card.querySelector(".skin-preview-stage:last-child .containerParent")).toBeNull();
});

test.each([
  [0, 0], [12, 0], [0, 12], [-1, 12], [501, 12], [12, 1001], [Infinity, 12], [12, NaN],
])("invalid or absent decoration %s/%s retains plain candidate markup", async (decorationTopDip, decorationWidthDip) => {
  render(<ExternalSkins {...props} scan={async () => ({ ...catalog, packages: [{ ...catalog.packages[0],
    minWidthDip: Infinity, decorationTopDip, decorationWidthDip }] })} />);
  refresh();
  const card = await screen.findByRole("article");
  expect(card.classList.contains("external-skin-decorated")).toBe(false);
  expect(card.querySelector(".containerParent")).toBeNull();
  const preview = card.querySelector<HTMLElement>(".skin-card-preview")!;
  expect(preview.style.getPropertyValue("--msime-skin-min-width")).toBe("0px");
  expect(preview.style.getPropertyValue("--msime-skin-decoration-top")).toBe("0px");
  expect(preview.style.getPropertyValue("--msime-skin-decoration-width")).toBe("0px");
});

test("refresh removes stale geometry and independent cards do not inherit it", async () => {
  const scan = vi.fn().mockResolvedValueOnce({ ...catalog, packages: [
    { ...catalog.packages[0], decorationTopDip: 500, decorationWidthDip: 1000, minWidthDip: 1000 },
    { ...catalog.packages[0], id: "plain", name: "Plain" },
  ] }).mockResolvedValue(catalog);
  render(<ExternalSkins {...props} scan={scan} />);
  refresh();
  const card = await screen.findByRole("article", { name: "Sample skin" });
  expect(card.querySelectorAll(".containerParent")).toHaveLength(2);
  expect(screen.getByRole("article", { name: "Plain" }).querySelector(".containerParent")).toBeNull();
  refresh();
  await act(async () => {});
  expect(card.querySelector(".containerParent")).toBeNull();
  expect(card.classList.contains("external-skin-decorated")).toBe(false);
});

test("geometry stylesheet retains upstream stacking, dimensions and candidate-only scope", () => {
  const style = document.createElement("style");
  style.textContent = geometryCss;
  document.head.append(style);
  try {
    const rules = Array.from(style.sheet!.cssRules) as CSSStyleRule[];
    const parent = rules.find(rule => rule.selectorText === ".external-skin-decorated .candidate .containerParent")!;
    expect(parent.style.getPropertyValue("padding-top")).toBe("var(--msime-skin-decoration-top, 0px)");
    const ornament = rules.find(rule => rule.selectorText?.endsWith("::before"))!;
    expect(ornament.style.getPropertyValue("height")).toBe("118px");
    expect(ornament.style.getPropertyValue("pointer-events")).toBe("none");
    expect(ornament.style.getPropertyValue("z-index")).toBe("0");
    const container = rules.find(rule => rule.selectorText === ".external-skin-decorated .candidate .container")!;
    expect(container.style.getPropertyValue("z-index")).toBe("1");
    expect(container.style.getPropertyValue("min-width")).toBe("max(7em, var(--msime-skin-min-width, 0px))");
    expect(geometryCss).not.toContain("url(");
  } finally { style.remove(); }
});

test("light preview inherits dark palette fields before applying its sparse overrides", async () => {
  render(<ExternalSkins {...props} scan={async () => ({ ...catalog, packages: [{ ...catalog.packages[0], candidate: {
    dark: { surface: "#123456", text: "#112233", showSelectedBar: false }, light: { surface: "#abcdef" },
  } }] })} />);
  refresh();
  const card = await screen.findByRole("article");
  fireEvent.click(within(card).getByRole("button", { name: "预览浅色" }));
  const css = card.querySelector("style")!.textContent!;
  expect(css).toContain("#112233");
  expect(css).toContain("display:none");
  expect(css.indexOf("#abcdef")).toBeGreaterThan(css.indexOf("#123456"));
  fireEvent.click(within(card).getByRole("button", { name: "预览深色" }));
  expect(card.querySelector("style")!.textContent).not.toContain("#abcdef");
});

test("open directory is explicit, path-free and independent of scanning and selection", async () => {
  const openDirectory = vi.fn().mockResolvedValue(undefined);
  const scan = vi.fn().mockResolvedValue(catalog);
  const onSelect = vi.fn();
  render(<ExternalSkins {...props} openDirectory={openDirectory} scan={scan} onSelect={onSelect} />);
  expect(openDirectory).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole("button", { name: "打开目录" }));
  await screen.findByRole("button", { name: "打开目录" });
  expect(openDirectory).toHaveBeenCalledWith();
  expect(scan).not.toHaveBeenCalled();
  expect(onSelect).not.toHaveBeenCalled();
});

test("settings forwards the open directory capability", async () => {
  const openSkinDirectory = vi.fn().mockResolvedValue(undefined);
  const save = vi.fn();
  render(<SettingsPage client={{ load: async () => initial, save, openSkinDirectory }} />);
  fireEvent.click(await screen.findByRole("button", { name: "皮肤" }));
  fireEvent.click(screen.getByRole("button", { name: "打开目录" }));
  await screen.findByRole("button", { name: "打开目录" });
  expect(openSkinDirectory).toHaveBeenCalledWith();
  expect(save).not.toHaveBeenCalled();
});

test("directory opener is disabled when unavailable and retries sanitized failures", async () => {
  const mounted = render(<ExternalSkins {...props} />);
  expect((screen.getByRole("button", { name: "打开目录" }) as HTMLButtonElement).disabled).toBe(true);
  const openDirectory = vi.fn().mockImplementationOnce(() => { throw new Error("private diagnostic"); }).mockResolvedValue(undefined);
  mounted.rerender(<ExternalSkins {...props} openDirectory={openDirectory} />);
  fireEvent.click(screen.getByRole("button", { name: "打开目录" }));
  expect((await screen.findByRole("alert")).textContent).toBe("无法打开皮肤目录，请重试。");
  expect(screen.queryByText("private diagnostic")).toBeNull();
  fireEvent.click(screen.getByRole("button", { name: "打开目录" }));
  await screen.findByRole("button", { name: "打开目录" });
  expect(screen.queryByRole("alert")).toBeNull();
  expect(openDirectory).toHaveBeenCalledTimes(2);
});

test("opening deduplicates requests and ignores late failures after host replacement", async () => {
  let reject!: (error: Error) => void;
  const openDirectory = vi.fn(() => new Promise<void>((_resolve, fail) => { reject = fail; }));
  const mounted = render(<ExternalSkins {...props} openDirectory={openDirectory} />);
  fireEvent.click(screen.getByRole("button", { name: "打开目录" }));
  fireEvent.click(screen.getByRole("button", { name: "正在打开…" }));
  expect(openDirectory).toHaveBeenCalledTimes(1);
  mounted.rerender(<ExternalSkins {...props} openDirectory={async () => {}} />);
  await act(async () => reject(new Error("synthetic")));
  expect(screen.queryByRole("alert")).toBeNull();
  expect((screen.getByRole("button", { name: "打开目录" }) as HTMLButtonElement).disabled).toBe(false);
});

test("catalog is scanned only on request and displays host directory, metadata and diagnostics", async () => {
  const scan = vi.fn().mockResolvedValue(catalog);
  render(<ExternalSkins {...props} scan={scan} />);
  expect(scan).not.toHaveBeenCalled();
  expect(screen.getByRole("status").textContent).toContain("尚未扫描");
  refresh();
  const card = await screen.findByRole("article", { name: "Sample skin" });
  expect(scan).toHaveBeenCalledWith();
  expect(screen.getByText(catalog.directory)).toBeTruthy();
  expect(within(card).getByText("sample · v1 · Example")).toBeTruthy();
  expect(screen.getByText("已忽略 1 个无效皮肤目录")).toBeTruthy();
  expect(screen.getByText("Bad：invalid manifest")).toBeTruthy();
  expect(card.querySelectorAll(".skin-preview-stage")).toHaveLength(3);
});

test("external selection enters the revisioned draft; preview toggles never save or select", async () => {
  const save = vi.fn().mockImplementation(async (_revision, preferences) => ({ ...initial, revision: 4, preferences }));
  render(<SettingsPage client={{ load: async () => initial, save, scanSkinCatalog: async () => catalog }} />);
  fireEvent.click(await screen.findByRole("button", { name: "皮肤" }));
  refresh();
  const card = await screen.findByRole("article", { name: "Sample skin" });
  fireEvent.click(within(card).getByRole("button", { name: "预览浅色" }));
  expect(within(card).getByRole("switch").getAttribute("aria-checked")).toBe("false");
  expect(card.querySelector("style")?.textContent).toContain("#abcdef");
  expect(save).not.toHaveBeenCalled();
  fireEvent.click(within(card).getByRole("switch"));
  fireEvent.click(within(card).getByRole("switch"));
  expect(within(card).getByRole("switch").getAttribute("aria-checked")).toBe("true");
  expect(save).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  expect(save).toHaveBeenCalledWith(3, expect.objectContaining({ candidate_skin: "sample" }));
});

test("manifest compatibility follows actual layout and dark host theme, not preview override", async () => {
  const onSelect = vi.fn();
  const mounted = render(<ExternalSkins {...props} onSelect={onSelect} scan={async () => catalog} layout="vertical" />);
  refresh();
  const toggle = await screen.findByRole("switch", { name: "Sample skin" });
  expect((toggle as HTMLButtonElement).disabled).toBe(true);
  fireEvent.click(toggle);
  fireEvent.click(screen.getByRole("button", { name: "预览浅色" }));
  expect((toggle as HTMLButtonElement).disabled).toBe(true);
  expect(onSelect).not.toHaveBeenCalled();
  mounted.unmount();
  render(<ExternalSkins {...props} scan={async () => ({ ...catalog, packages: [{ ...catalog.packages[0], themes: ["light"] }] })} />);
  refresh();
  expect((await screen.findByRole("switch") as HTMLButtonElement).disabled).toBe(true);
});

test("settings without a layout use the same vertical default for skin compatibility", async () => {
  render(<SettingsPage client={{ load: async () => ({ ...initial, preferences: { ...initial.preferences, candidate_layout: undefined } }),
    save: vi.fn(), scanSkinCatalog: async () => catalog }} />);
  fireEvent.click(await screen.findByRole("button", { name: "皮肤" }));
  refresh();
  expect((await screen.findByRole("switch", { name: "Sample skin" }) as HTMLButtonElement).disabled).toBe(true);
});

test("errors retain last catalog, hide raw exception and permit retry to empty results", async () => {
  const scan = vi.fn().mockResolvedValueOnce(catalog).mockRejectedValueOnce(new Error("sensitive diagnostic"))
    .mockResolvedValueOnce({ directory: catalog.directory, packages: [], issues: [] });
  render(<ExternalSkins {...props} scan={scan} />);
  refresh(); await screen.findByRole("article");
  refresh();
  expect((await screen.findByRole("alert")).textContent).toContain("仍显示上次扫描结果");
  expect(screen.queryByText("sensitive diagnostic")).toBeNull();
  expect(screen.getByRole("article")).toBeTruthy();
  refresh();
  await screen.findByText("没有发现外部皮肤。");
  expect(screen.queryByRole("article")).toBeNull();
  expect(screen.queryByRole("alert")).toBeNull();
});

test("late old-host result cannot overwrite current catalog; busy scan cannot be duplicated", async () => {
  let resolve!: (result: SkinCatalog) => void;
  const scan = vi.fn(() => new Promise<SkinCatalog>(done => { resolve = done; }));
  const mounted = render(<ExternalSkins {...props} scan={scan} />);
  refresh();
  fireEvent.click(screen.getByRole("button", { name: "正在扫描…" }));
  expect(scan).toHaveBeenCalledTimes(1);
  mounted.rerender(<ExternalSkins {...props} scan={async () => ({ ...catalog, packages: [], issues: [] })} />);
  refresh(); await screen.findByText("没有发现外部皮肤。");
  await act(async () => resolve(catalog));
  expect(screen.queryByRole("article")).toBeNull();
});

test("unavailable hosts and synchronous scan exceptions are handled", async () => {
  const mounted = render(<ExternalSkins {...props} />);
  expect((screen.getByRole("button", { name: "刷新皮肤" }) as HTMLButtonElement).disabled).toBe(true);
  mounted.rerender(<ExternalSkins {...props} scan={() => { throw new Error("synthetic"); }} />);
  refresh();
  expect(await screen.findByRole("alert")).toBeTruthy();
  expect((screen.getByRole("button", { name: "刷新皮肤" }) as HTMLButtonElement).disabled).toBe(false);
});

test("manifest text is escaped and palette cannot inject CSS or resource URLs", async () => {
  const hostile = "</style><img src=x onerror=alert(1)>";
  render(<ExternalSkins {...props} scan={async () => ({ ...catalog, packages: [{ ...catalog.packages[0], name: hostile,
    candidate: { dark: { surface: "red;} body{display:none}", text: "url(https://invalid.example)", accent: "#123456", showSelectedBar: false }, light: {} } }] })} />);
  refresh();
  const card = await screen.findByRole("article", { name: hostile });
  expect(card.querySelector("img[src=x]")).toBeNull();
  const css = card.querySelector("style")!.textContent!;
  expect(css).toContain("#123456");
  expect(css).toContain("display:none");
  expect(css).not.toContain("body");
  expect(css).not.toContain("url(");
});
