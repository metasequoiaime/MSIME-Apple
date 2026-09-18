// Let the browser turn image-set string options into explicit url() tokens.
// This also works for custom properties, which otherwise retain raw strings.
export function normalizeImageSets(value: string): string | null {
  const tokens = /"(?:[^"\\]|\\[\s\S])*"|'(?:[^'\\]|\\[\s\S])*'|\/\*[\s\S]*?\*\/|(?<![a-zA-Z0-9_\\-])((?:-webkit-)?image-set)\s*\(/gi;
  let output = "", offset = 0;
  for (let match = tokens.exec(value); match; match = tokens.exec(value)) {
    if (!match[1]) continue;
    if (typeof CSSStyleSheet === "undefined") return null;
    let end = tokens.lastIndex, depth = 1;
    while (end < value.length && depth) {
      const character = value[end++];
      if (character === '"' || character === "'") {
        // Escaped quotes and line continuations belong to the string. Let the
        // browser validate/decode them after we find the expression boundary.
        let closed = false;
        while (end < value.length) {
          const next = value[end++];
          if (next === "\\") end++;
          else if (next === character) { closed = true; break; }
        }
        if (!closed) return null;
      } else if (character === "\\") {
        // A simple escape may contain a parenthesis; a hex escape contains no
        // literal delimiters. Neither changes the expression's nesting depth.
        end++;
      } else if (character === "/" && value[end] === "*") {
        const closing = value.indexOf("*/", end + 1);
        if (closing < 0) return null;
        end = closing + 2;
      } else if (character === "(") depth++;
      else if (character === ")") depth--;
    }
    if (depth) return null;
    const parsed = new CSSStyleSheet();
    parsed.insertRule(".image-set-parser {}", 0);
    const style = (parsed.cssRules[0] as CSSStyleRule).style;
    style.setProperty("background-image", value.slice(match.index, end));
    const canonical = style.getPropertyValue("background-image");
    if (!canonical) return null;
    // Older parsers may retain bare image strings. Never treat them as resolved
    // resources: only canonical url() options and non-resource type() strings
    // may contain quotes when we hand the value to the bounded URL rewriter.
    const residue = canonical.replace(/\b(?:url|type)\(\s*(?:"(?:[^"\\]|\\[\s\S])*"|'(?:[^'\\]|\\[\s\S])*'|(?:[^\s)'"(\\]|\\[\s\S])*)\s*\)/gi, "");
    if (/["']/.test(residue)) return null;
    output += value.slice(offset, match.index) + canonical;
    offset = end;
    tokens.lastIndex = end;
  }
  return output + value.slice(offset);
}
