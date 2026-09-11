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
  vi.stubGlobal("CSSStyleSheet", class {
    cssRules = [{ style: { setProperty() {}, getPropertyValue: () => canonical } }];
    insertRule() { return 0; }
  });
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
