// @vitest-environment jsdom
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { act, cleanup, fireEvent, render, screen, within, waitFor } from "@testing-library/react";
import { ExternalSkins } from "../../../packages/ui/src/external-skins";
import { SettingsPage, type SkinCatalog, type Snapshot } from "@msime/ui";
import geometryCss from "../../../packages/ui/src/external-skin-geometry.css?raw";
import { skinImageUrl, type SkinImage } from "../../../packages/ui/src/skin-image";
import desktopConfig from "../src-tauri/tauri.conf.json";
import * as fontPreparation from "../../../packages/ui/src/toolbar-fonts";

afterEach(cleanup);
// jsdom parses CSS rules but does not implement adopted stylesheet rendering.
// Real CSP/computed-style coverage lives in scripts/test-skin-palette-csp.py.
beforeEach(() => Object.defineProperty(document, "adoptedStyleSheets", { configurable: true, writable: true, value: [] }));
function previewCss(card: HTMLElement): string {
  const scope = Array.from(card.querySelector(".skin-card-preview")!.classList).find(value => value.startsWith("external-preview-"))!;
  return document.adoptedStyleSheets.flatMap(sheet => Array.from(sheet.cssRules).map(rule => rule.cssText))
    .filter(rule => rule.includes(`.${scope} `)).join("").replace(/\s+/g, "");
}
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

test("settings forwards the declared toolbar reader using only package id", async () => {
  const readSkinToolbarCss = vi.fn().mockResolvedValue(null);
  render(<SettingsPage client={{ load: async () => initial, save: vi.fn(), readSkinToolbarCss,
    scanSkinCatalog: async () => ({ ...catalog, packages: [{ ...catalog.packages[0], toolbarStylesheet: "toolbar.css" }] }) }} />);
  fireEvent.click(await screen.findByRole("button", { name: "皮肤" }));
  refresh();
  await waitFor(() => expect(readSkinToolbarCss).toHaveBeenCalledExactlyOnceWith("sample"));
});
test("settings forwards the font reader with package id and relative name", async () => {
  const readSkinFont = vi.fn().mockResolvedValue({ contentType: "font/woff2", bytes: [0, 1] });
  const prepare = vi.spyOn(fontPreparation, "prepareToolbarFonts").mockImplementation(async (_css, resolve) => {
    await resolve("fonts/test.woff2");
    return { css: "", partial: false, install: () => () => {} };
  });
  try {
    render(<SettingsPage client={{ load: async () => initial, save: vi.fn(), readSkinFont,
      readSkinToolbarCss: async () => ".sample {}",
      scanSkinCatalog: async () => ({ ...catalog, packages: [{ ...catalog.packages[0], toolbarStylesheet: "toolbar.css" }] }) }} />);
    fireEvent.click(await screen.findByRole("button", { name: "皮肤" }));
    refresh();
    await waitFor(() => expect(readSkinFont).toHaveBeenCalledExactlyOnceWith("sample", "fonts/test.woff2"));
  } finally { prepare.mockRestore(); }
});

test("palette sheets replace on theme change and disappear when cards unmount", async () => {
  const mounted = render(<ExternalSkins {...props} scan={async () => catalog} />);
  refresh();
  const card = await screen.findByRole("article");
  expect(card.querySelector("style")).toBeNull();
  await waitFor(() => expect(document.adoptedStyleSheets).toHaveLength(1));
  const previous = document.adoptedStyleSheets[0];
  fireEvent.click(within(card).getByRole("button", { name: "预览浅色" }));
  expect(document.adoptedStyleSheets).toHaveLength(1);
  expect(document.adoptedStyleSheets[0]).not.toBe(previous);
  mounted.unmount();
  expect(document.adoptedStyleSheets).toHaveLength(0);
});

test("missing adopted stylesheets reports fallback without injecting inline styles", async () => {
  Reflect.deleteProperty(document, "adoptedStyleSheets");
  render(<ExternalSkins {...props} scan={async () => catalog} />);
  refresh();
  await screen.findByText("当前浏览器无法应用皮肤配色，保留基础预览。");
  expect(screen.getByRole("article").querySelector("style")).toBeNull();
});

const imageCatalog: SkinCatalog = { ...catalog, packages: [{ ...catalog.packages[0],
  preview: "images/top.png", decorationTopDip: 32, decorationWidthDip: 150 }] };
const imageData: SkinImage = { contentType: "image/png", bytes: [0, 1, 255] };

test("image data URLs preserve bytes and reject non-image or invalid payloads", () => {
  expect(skinImageUrl(imageData)).toBe("data:image/png;base64,AAH/");
  for (const image of [{ contentType: "text/html", bytes: [] }, { contentType: "image/png;bad", bytes: [] },
    { ...imageData, bytes: [-1] }, { ...imageData, bytes: [256] }, { ...imageData, bytes: [1.5] },
    { ...imageData, bytes: [NaN] }, { ...imageData, bytes: new Array(8 * 1024 * 1024 + 1) }]) {
    expect(() => skinImageUrl(image)).toThrow("invalid image");
  }
});

test("one host image read feeds both preview layouts and refresh reloads unchanged manifests", async () => {
  const readImage = vi.fn().mockResolvedValue(imageData);
  const mounted = render(<ExternalSkins {...props} scan={async () => imageCatalog} readImage={readImage} />);
  expect(readImage).not.toHaveBeenCalled();
  refresh();
  const card = await screen.findByRole("article");
  await waitFor(() => expect(card.querySelectorAll("img.skin-decoration-image")).toHaveLength(2));
  expect(readImage).toHaveBeenCalledExactlyOnceWith("sample", "images/top.png");
  expect(card.querySelector("img.skin-decoration-image")?.getAttribute("src")).toBe(skinImageUrl(imageData));
  fireEvent.click(within(card).getByRole("button", { name: "预览浅色" }));
  expect(readImage).toHaveBeenCalledTimes(1);
  refresh();
  await waitFor(() => expect(readImage).toHaveBeenCalledTimes(2));
  mounted.unmount();
});

test("settings forwards image reader and existing CSP permits image data without broader sources", async () => {
  const readSkinImage = vi.fn().mockResolvedValue(imageData);
  render(<SettingsPage client={{ load: async () => initial, save: vi.fn(), scanSkinCatalog: async () => imageCatalog, readSkinImage }} />);
  fireEvent.click(await screen.findByRole("button", { name: "皮肤" }));
  refresh();
  await waitFor(() => expect(readSkinImage).toHaveBeenCalledExactlyOnceWith("sample", "images/top.png"));
  const imgDirective = desktopConfig.app.security.csp.split(";").find(value => value.trim().startsWith("img-src"));
  expect(imgDirective?.trim()).toBe("img-src 'self' data:");
});

test("image read and decode failures retain base preview and can be retried", async () => {
  const readImage = vi.fn().mockRejectedValueOnce(new Error("private diagnostic")).mockResolvedValue(imageData);
  render(<ExternalSkins {...props} scan={async () => imageCatalog} readImage={readImage} />);
  refresh();
  await screen.findByText("皮肤图片加载失败，保留基础预览。可刷新皮肤重试。");
  expect(screen.queryByText("private diagnostic")).toBeNull();
  refresh();
  const card = screen.getByRole("article");
  await waitFor(() => expect(card.querySelector("img.skin-decoration-image")).not.toBeNull());
  fireEvent.error(card.querySelector("img.skin-decoration-image")!);
  expect(card.querySelector("img.skin-decoration-image")).toBeNull();
  expect(card.querySelectorAll(".candidate .container")).toHaveLength(2);
  refresh();
  await waitFor(() => expect(card.querySelectorAll("img.skin-decoration-image")).toHaveLength(2));
});

test("old image response cannot replace current resource after catalog refresh", async () => {
  let finish!: (image: SkinImage) => void;
  const readImage = vi.fn().mockImplementationOnce(() => new Promise<SkinImage>(resolve => { finish = resolve; }))
    .mockResolvedValue({ ...imageData, bytes: [2] });
  render(<ExternalSkins {...props} scan={async () => imageCatalog} readImage={readImage} />);
  refresh();
  await waitFor(() => expect(readImage).toHaveBeenCalledTimes(1));
  refresh();
  const card = screen.getByRole("article");
  await waitFor(() => expect(card.querySelector("img.skin-decoration-image")?.getAttribute("src")).toContain("Ag=="));
  await act(async () => finish(imageData));
  expect(card.querySelector("img.skin-decoration-image")?.getAttribute("src")).toContain("Ag==");
});

test("images are not requested without decoration and optional hosts remain usable", async () => {
  const readImage = vi.fn();
  const scan = async () => ({ ...imageCatalog, packages: [{ ...imageCatalog.packages[0], decorationTopDip: 0, decorationWidthDip: 0 }] });
  const mounted = render(<ExternalSkins {...props} scan={scan} readImage={readImage} />);
  refresh(); await screen.findByRole("article");
  expect(readImage).not.toHaveBeenCalled();
  mounted.rerender(<ExternalSkins {...props} scan={async () => imageCatalog} />);
  refresh();
  await screen.findByText("当前宿主不支持皮肤图片预览。");
});

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
  const css = previewCss(card);
  expect(css).toContain("rgb(17,34,51)");
  expect(css).toContain("display:none");
  expect(css.indexOf("rgb(171,205,239)")).toBeGreaterThan(css.indexOf("rgb(18,52,86)"));
  fireEvent.click(within(card).getByRole("button", { name: "预览深色" }));
  expect(previewCss(card)).not.toContain("rgb(171,205,239)");
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
  expect(previewCss(card)).toContain("rgb(171,205,239)");
  expect(save).not.toHaveBeenCalled();
  fireEvent.click(within(card).getByRole("switch"));
  fireEvent.click(within(card).getByRole("switch"));
  expect(within(card).getByRole("switch").getAttribute("aria-checked")).toBe("true");
  expect(save).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  expect(save).toHaveBeenCalledWith(3, expect.objectContaining({ candidate_skin: "sample" }));
});

test("light-only skin compatibility follows actual theme, not card override", async () => {
  const scan = vi.fn().mockResolvedValue({ ...catalog, packages: [{ ...catalog.packages[0], themes: ["light"] }] });
  const onSelect = vi.fn();
  const view = render(<ExternalSkins {...props} onSelect={onSelect} scan={scan} activeTheme="dark" />);
  refresh();
  const toggle = await screen.findByRole("switch");
  expect((toggle as HTMLButtonElement).disabled).toBe(true);
  view.rerender(<ExternalSkins {...props} onSelect={onSelect} scan={scan} activeTheme="light" />);
  expect((toggle as HTMLButtonElement).disabled).toBe(false);
  fireEvent.click(screen.getByRole("button", { name: "预览深色" }));
  expect((toggle as HTMLButtonElement).disabled).toBe(false);
  fireEvent.click(toggle);
  expect(onSelect).toHaveBeenCalledExactlyOnceWith("sample");
  view.rerender(<ExternalSkins {...props} onSelect={onSelect} scan={scan} activeTheme="dark" />);
  expect((toggle as HTMLButtonElement).disabled).toBe(true);
  expect(view.container.querySelector(".skin-card-preview")?.getAttribute("data-preview-theme")).toBe("light");
  expect(scan).toHaveBeenCalledTimes(1);
});

test("settings synchronize all cards and reset local overrides on candidate theme changes", async () => {
  const save = vi.fn(), scan = vi.fn().mockResolvedValue(catalog);
  render(<SettingsPage client={{ load: async () => initial, save, scanSkinCatalog: scan }} />);
  await screen.findByLabelText("全局主题");
  fireEvent.change(screen.getByLabelText("全局主题"), { target: { value: "light" } });
  fireEvent.click(screen.getByRole("button", { name: "皮肤" }));
  refresh();
  await screen.findByRole("article", { name: "Sample skin" });
  const cards = screen.getAllByRole("article");
  expect(cards).toHaveLength(5);
  for (const card of cards) {
    expect(card.querySelector(".skin-card-preview")?.getAttribute("data-preview-theme")).toBe("light");
    fireEvent.click(within(card).getByRole("button", { name: "预览深色" }));
    expect(card.querySelector(".skin-card-preview")?.getAttribute("data-preview-theme")).toBe("dark");
  }
  fireEvent.click(screen.getByRole("button", { name: "外观" }));
  fireEvent.change(screen.getByLabelText("全局主题"), { target: { value: "dark" } });
  fireEvent.change(screen.getByLabelText("全局主题"), { target: { value: "light" } });
  fireEvent.click(screen.getByRole("button", { name: "皮肤" }));
  for (const card of cards) expect(card.querySelector(".skin-card-preview")?.getAttribute("data-preview-theme")).toBe("light");
  expect(scan).toHaveBeenCalledTimes(1);
  expect(save).not.toHaveBeenCalled();
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
  const css = previewCss(card);
  expect(css).toContain("rgb(18,52,86)");
  expect(css).toContain("display:none");
  expect(css).not.toContain("body");
  expect(css).not.toContain("url(");
});
