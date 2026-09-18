const escape = "\\\\(?:[0-9a-f]{1,6}(?:\\r\\n|[ \\t\\r\\n\\f])?|[^\\r\\n\\f])";
const identifier = "(?:[a-zA-Z0-9_-]|[^\\x00-\\x7f]|" + escape + ")+";
const wholeName = new RegExp("^[ \\t\\r\\n\\f]*(" + identifier + ")[ \\t\\r\\n\\f]*$", "i");

export function decodeCustomPropertyName(raw: string): string | null {
  const match = wholeName.exec(raw);
  if (!match) return null;
  const decoded = match[1].replace(new RegExp(escape, "gi"), token => {
    const hex = /^[0-9a-f]{1,6}/i.exec(token.slice(1));
    if (!hex) return token.slice(1);
    const point = Number.parseInt(hex[0], 16);
    return String.fromCodePoint(!point || point > 0x10ffff || (point >= 0xd800 && point <= 0xdfff) ? 0xfffd : point);
  });
  return decoded.startsWith("--") && decoded.length > 2 ? decoded : null;
}

export function customPropertyNames(value: string): string[] {
  return Array.from(value.matchAll(new RegExp(identifier, "gi")))
    .map(match => decodeCustomPropertyName(match[0])).filter((name): name is string => name !== null);
}

// Only a validated var() name is opaque to resource checks. Its fallback is
// deliberately left in the value so escaped/remote URLs cannot hide there.
export function maskVariableNames(value: string): string {
  const tokens = new RegExp('"(?:[^"\\\\]|\\\\[\\s\\S])*"|\\\'(?:[^\\\'\\\\]|\\\\[\\s\\S])*\\\'|/\\*[\\s\\S]*?\\*/|(?<![a-zA-Z0-9_\\\\-])var\\([ \\t\\r\\n\\f]*(' + identifier + ')[ \\t\\r\\n\\f]*(?=[,)])', "gi");
  return value.replace(tokens, (token, name: string | undefined) =>
    name !== undefined && decodeCustomPropertyName(name) !== null ? "var(--validated" : token);
}
