import parse from "postcss/lib/parse";
import type { Declaration } from "postcss";
import { animationVariables, parseAnimationVariable } from "./skin-animation-variables.js";
import { decodeCustomPropertyName } from "./css-custom-property.js";

let generation = 0;
// CSSOM loses pending shorthand substitution when even one longhand is
// overridden. Expand whole-value variable shorthands before that lossy parse.
export function preserveAnimationShorthands(css: string): { css: string; partial: boolean } {
  return preserveShorthands(css, "animation");
}

export function preserveFontShorthands(css: string): { css: string; partial: boolean } {
  return preserveShorthands(css, "font");
}

function preserveShorthands(css: string, shorthand: "animation" | "font"): { css: string; partial: boolean } {
  if (css.length > 16 * 1024 * 1024) return { css: "", partial: true };
  if (!new RegExp(shorthand + "\\s*:", "i").test(css) || !/var\(/i.test(css)) return { css, partial: false };
  let root;
  try { root = parse(css, { from: undefined, map: false }); }
  catch { return { css, partial: true }; } // Keep browser recovery for malformed sheets.
  const declarations: Declaration[] = [];
  root.walkDecls(declaration => { declarations.push(declaration); });
  const shorthands = declarations.filter(declaration =>
    (shorthand === "animation" ? /^(?:-webkit-)?animation$/i : /^font$/i).test(declaration.prop) && parseAnimationVariable(declaration.value));
  if (!shorthands.length) return { css, partial: false };
  const parsed = new CSSStyleSheet();
  const styles = declarations.map(declaration => {
    const index = parsed.insertRule(".source-declaration {}", parsed.cssRules.length);
    const style = (parsed.cssRules[index] as CSSStyleRule).style;
    style.setProperty(decodeCustomPropertyName(declaration.prop) ?? declaration.prop, declaration.value, declaration.important ? "important" : "");
    return style;
  });
  const parser = new CSSStyleSheet();
  parser.insertRule(".projection {}", 0);
  const projection = (parser.cssRules[0] as CSSStyleRule).style;
  projection.setProperty(shorthand, shorthand === "animation" ? "none" : "16px serif");
  const components = Array.from(projection);
  const prefix = "msime-" + shorthand + "-source-" + ++generation + "-";
  const variables = animationVariables<string>(styles, prefix, (value, property) => {
    projection.cssText = "";
    projection.setProperty(shorthand, value);
    const projected = projection.getPropertyValue(property);
    // Keep invalid-but-defined custom values invalid, rather than making them
    // missing and incorrectly activating a var() fallback.
    return { value: projected || "msime-invalid-" + shorthand, partial: !projected };
  });
  for (const declaration of shorthands) {
    for (const property of components) declaration.cloneBefore({
      prop: property, value: variables.rewrite(declaration.value, property),
    });
    declaration.remove();
  }
  const partial = variables.install();
  declarations.forEach((declaration, index) => {
    if (!declaration.parent) return;
    const style = styles[index];
    for (const property of Array.from(style)) {
      if (property === (decodeCustomPropertyName(declaration.prop) ?? declaration.prop) || !property.startsWith("--" + prefix)) continue;
      declaration.cloneBefore({ prop: property, value: style.getPropertyValue(property),
        important: style.getPropertyPriority(property) === "important" });
    }
  });
  const output = root.toString();
  return output.length > 16 * 1024 * 1024 ? { css: "", partial: true } : { css: output, partial };
}
