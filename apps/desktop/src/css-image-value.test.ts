import { expect, test, vi } from "vitest";
import { hasUnresolvedCssResource, rewriteCssImages } from "../../../packages/ui/src/css-image-value";
const data = "data:image/png;base64,AAH/";

test.each([
  ["url(images/a\\2e png)", "images/a.png"],
  ['url("images/\\61.svg")', "images/a.svg"],
  ["url('images/\\000061.svg')", "images/a.svg"],
  ["url(images/a\\.png)", "images/a.png"],
  ["url(images/a\\2E\r\npng)", "images/a.png"],
  ['url("images/a\\\r\n.png")', "images/a.png"],
  ['url("images/a\\\f.png")', "images/a.png"],
  ["url(images\\2f a.png)", "images/a.png"],
])("decodes CSS URL escapes before resolving %s", async (value, relative) => {
  const resolve = vi.fn().mockResolvedValue(data);
  expect(await rewriteCssImages(value, resolve)).toBe('url("' + data + '")');
  expect(resolve.mock.calls).toEqual([[relative]]);
});

test.each([
  "url(\\2e\\2e/a.png)",
  "url(\\2f a.png)",
  "url(\\68 ttps://example.invalid/a.png)",
  "url(images/\\0.png)",
  "url(images/\\d800.png)",
  "url(images/\\110000.png)",
  "url(images/a\\\n.png)",
  'url("images/a\n.png")',
  "url(images/a.png\\)",
  "u\\72l(images/a.png)",
])("rejects unsafe or unsupported escapes without reading %s", async value => {
  const resolve = vi.fn();
  expect(await rewriteCssImages(value, resolve)).toBeNull();
  expect(resolve).not.toHaveBeenCalled();
});

test("keeps escaped non-resource strings opaque", async () => {
  const resolve = vi.fn();
  for (const value of ['"\\e101"', '"src(icon.png)"', '"escaped \\" url(icon.png)"']) {
    expect(await rewriteCssImages(value, resolve)).toBe(value);
    expect(hasUnresolvedCssResource(value)).toBe(false);
  }
  expect(resolve).not.toHaveBeenCalled();
});

test("rewrites quoted and unquoted package images, preserving non-resource content", async () => {
  const resolve = vi.fn().mockResolvedValue(data);
  expect(await rewriteCssImages("url('./images/a.png') center, url(images/b.png)", resolve))
    .toBe(`url("${data}") center, url("${data}")`);
  expect(resolve.mock.calls).toEqual([["images/a.png"], ["images/b.png"]]);
  expect(await rewriteCssImages('"url(icon.png)"', resolve)).toBe('"url(icon.png)"');
  expect(resolve).toHaveBeenCalledTimes(2);
});
test.each(["../a.png", "/a.png", "https://example.invalid/a.png", "//example.invalid/a.png", "C:/a.png", "%2e%2e/a.png"])("rejects non-package URL %s without reading", async url => {
  const resolve = vi.fn();
  expect(await rewriteCssImages(`url("${url}")`, resolve)).toBeNull();
  expect(resolve).not.toHaveBeenCalled();
});
test("allows bounded image data only, and rejects failed or invalid resolver output", async () => {
  expect(await rewriteCssImages(`url("${data}")`, vi.fn())).toBe(`url("${data}")`);
  expect(hasUnresolvedCssResource(`url("${data}")`)).toBe(false);
  expect(hasUnresolvedCssResource('url("data:text/html;base64,AA==")')).toBe(true);
  expect(await rewriteCssImages("url(a.png)", vi.fn().mockRejectedValue(new Error("synthetic")))).toBeNull();
  expect(await rewriteCssImages("url(a.png)", vi.fn().mockResolvedValue('x"); body {display:none}'))).toBeNull();
  expect(await rewriteCssImages('image-set("a.png" 1x)', vi.fn())).toBeNull();
});
test("oversized declarations are rejected before image requests", async () => {
  const resolve = vi.fn();
  expect(await rewriteCssImages("a".repeat(16 * 1024 * 1024 + 1), resolve)).toBeNull();
  expect(resolve).not.toHaveBeenCalled();
});
