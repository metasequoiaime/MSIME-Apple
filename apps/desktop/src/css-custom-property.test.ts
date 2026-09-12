import { expect, test, vi } from "vitest";
import { customPropertyNames, decodeCustomPropertyName, maskVariableNames } from "../../../packages/ui/src/css-custom-property";
import { parseAnimationVariable } from "../../../packages/ui/src/skin-animation-variables";
import { hasUnresolvedCssResource, rewriteCssImages } from "../../../packages/ui/src/css-image-value";

test.each([
  ["--动画", "--动画"],
  ["--\\61", "--a"],
  ["--\\000061", "--a"],
  ["\\2d\\2d motion", "--motion"],
  ["--a\\,b", "--a,b"],
  ["--a\\ ", "--a "],
  ["--a\\2e\r\nb", "--a.b"],
  ["--\\0", "--\ufffd"],
])("decodes custom-property identifiers %s", (raw, name) => {
  expect(decodeCustomPropertyName(raw)).toBe(name);
  expect(parseAnimationVariable("var(" + raw + ", pulse)")).toEqual({ name, fallback: "pulse" });
});
test.each(["--", "name", "--a b", "--a\\", "--a\\\n", "--a)", "--a/*x*/b"])("rejects invalid property tokens %s", raw => {
  expect(decodeCustomPropertyName(raw)).toBeNull();
});
test("reserves escaped names and masks names without hiding fallback resources", async () => {
  expect(customPropertyNames('color:var(--\\74 est-var-0); --动画:pulse')).toEqual(["--test-var-0", "--动画"]);
  expect(maskVariableNames("var(--a\\,b, url(remote.png))")).toBe("var(--validated, url(remote.png))");
  expect(hasUnresolvedCssResource("var(--\\61, url(https://invalid.example/a.png))")).toBe(true);
  const resolve = vi.fn();
  expect(await rewriteCssImages("var(--\\61)", resolve)).toBe("var(--\\61)");
  expect(await rewriteCssImages("var(--\\61, url(https://invalid.example/a.png))", resolve)).toBeNull();
  expect(resolve).not.toHaveBeenCalled();
});
