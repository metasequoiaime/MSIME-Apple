import { afterEach, expect, test, vi } from "vitest";
import { normalizeImageSets } from "../../../packages/ui/src/css-image-set";

afterEach(() => vi.unstubAllGlobals());
test("ordinary values and quoted image-set text are unchanged without a parser", () => {
  vi.stubGlobal("CSSStyleSheet", undefined);
  expect(normalizeImageSets('"image-set(a.png)"')).toBe('"image-set(a.png)"');
  expect(normalizeImageSets("linear-gradient(red, blue)")).toBe("linear-gradient(red, blue)");
  expect(normalizeImageSets('image-set("a.png" 1x)')).toBeNull();
});
function parserResult(canonical: string) {
  const setProperty = vi.fn();
  vi.stubGlobal("CSSStyleSheet", class {
    cssRules = [{ style: { setProperty, getPropertyValue: () => canonical } }];
    insertRule() { return 0; }
  });
  return setProperty;
}
test("parsers that retain unresolved strings or reject syntax fail closed", () => {
  parserResult('image-set("https://invalid.example/a.png" 1x)');
  expect(normalizeImageSets('image-set("a.png" 1x)')).toBeNull();
  parserResult("");
  expect(normalizeImageSets('image-set("a.png" 1x)')).toBeNull();
});
test("canonical URL options retain surrounding layers and type hints", () => {
  const canonical = 'image-set(url("a.png") 1x, url("b.png") 2x type("image/png"))';
  parserResult(canonical);
  expect(normalizeImageSets('linear-gradient(red, blue), image-set("a.png" 1x, "b.png" 2x type("image/png"))'))
    .toBe(`linear-gradient(red, blue), ${canonical}`);
  expect(normalizeImageSets('-webkit-image-set("a.png" 1x)')).toBe(canonical);
  expect(normalizeImageSets('image-set("a.png" 1x')).toBeNull();
});

test.each([
  'image-set("images/\\61.png" 1x)',
  'image-set("images/a\\\r\n.png" 1x)',
  'image-set("images/a\\"(b).png" 1x)',
  "image-set('images/a\\'(b).png' 1x)",
  'image-set(url(images/a\\).png) 1x)',
  'image-set(url(images/a\\(.png) 1x)',
  'image-set(/* ) */ "images/a.png" 1x)',
])("passes the complete escaped expression to the browser: %s", expression => {
  const canonical = 'image-set(url("images/a.png") 1x)';
  const parse = parserResult(canonical);
  expect(normalizeImageSets(expression + ", linear-gradient(red, blue)")).toBe(canonical + ", linear-gradient(red, blue)");
  expect(parse.mock.calls).toEqual([["background-image", expression]]);
});

test("escaped non-resource text does not interfere with image-set parsing", () => {
  const canonical = 'image-set(url("a.png") 1x)';
  const parse = parserResult(canonical);
  const text = '"escaped \\" image-set(a.png)\\\ncontinued"';
  expect(normalizeImageSets(text + ', image-set("a.png" 1x)')).toBe(text + ", " + canonical);
  expect(parse).toHaveBeenCalledTimes(1);
});

test.each([
  'image-set("images/a\\" 1x)',
  'image-set(url(images/a\\)',
  'image-set(/* unterminated',
])("does not parse an unterminated escaped expression: %s", expression => {
  const parse = parserResult('image-set(url("a.png") 1x)');
  expect(normalizeImageSets(expression)).toBeNull();
  expect(parse).not.toHaveBeenCalled();
});

test("retained escaped string options still fail closed", () => {
  parserResult('image-set("images/a\\".png" 1x)');
  expect(normalizeImageSets('image-set("a.png" 1x)')).toBeNull();
});
