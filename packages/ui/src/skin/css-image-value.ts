import { normalizeImageSets } from "./css-image-set";
import { maskVariableNames } from "./css-custom-property";
const imageData =
  /^data:image\/(?:png|jpeg|gif|webp|svg\+xml|x-icon|bmp|avif);base64,[A-Za-z0-9+/]*={0,2}$/;
// Consume strings as opaque tokens before considering URL functions, so e.g.
// content: "url(icon.png)" never starts a resource request.
const escape = "\\\\(?:[0-9a-f]{1,6}(?:\\r\\n|[ \\t\\r\\n\\f])?|\\r\\n|[\\s\\S])";
const doubleString = '"(?:[^"\\\\\\r\\n\\f]|' + escape + ')*"';
const singleString = "'(?:[^'\\\\\\r\\n\\f]|" + escape + ")*'";
const urlPattern = new RegExp(
  doubleString +
    "|" +
    singleString +
    '|(?<![a-zA-Z0-9_\\\\-])url\\([ \\t\\r\\n\\f]*(?:"((?:[^"\\\\\\r\\n\\f]|' +
    escape +
    ")*)\"|'((?:[^'\\\\\\r\\n\\f]|" +
    escape +
    ")*)'|((?:[^\\s)'\"(\\\\]|" +
    escape +
    ")*))[ \\t\\r\\n\\f]*\\)",
  "gi",
);

// CSS Syntax 3: preprocess newlines, then consume escaped code points.
// Decode before the package path allowlist; escapes never bypass containment.
export function decodeCssUrl(raw: string, quoted: boolean): string | null {
  raw = raw.replace(/\r\n?|\f/g, "\n");
  let result = "";
  for (let index = 0; index < raw.length; index++) {
    const character = raw[index];
    if (character !== "\\") {
      if (character === "\n") return null;
      result += character;
      continue;
    }
    if (++index === raw.length) return null;
    if (raw[index] === "\n") {
      if (!quoted) return null;
      continue;
    }
    const hex = /^[0-9a-f]{1,6}/i.exec(raw.slice(index, index + 6));
    if (hex) {
      const point = Number.parseInt(hex[0], 16);
      result += String.fromCodePoint(
        !point || point > 0x10ffff || (point >= 0xd800 && point <= 0xdfff) ? 0xfffd : point,
      );
      index += hex[0].length - 1;
      if (/[ \t\n]/.test(raw[index + 1] ?? "")) index++;
    } else {
      result += raw[index];
    }
  }
  return result;
}
export function isImageDataUrl(value: string): boolean {
  return value.length <= 12 * 1024 * 1024 && imageData.test(value);
}

// Turn resources relative to a stylesheet into package-root paths before
// imported sheets are flattened. `..` may walk within the package but never
// above it; the host validates the resulting path again when reading bytes.
export function rebaseCssResources(value: string, stylesheet: string): string | null {
  const normalized = normalizeImageSets(value);
  if (normalized === null) return null;
  value = normalized;
  const base = stylesheet.split("/").filter(Boolean);
  base.pop();
  let invalid = false;
  const result = value.replace(
    urlPattern,
    (token, double: string, single: string, bare: string) => {
      if (double === undefined && single === undefined && bare === undefined) return token;
      const decoded = decodeCssUrl(double ?? single ?? bare, bare === undefined);
      if (decoded === null || isImageDataUrl(decoded))
        return decoded === null ? ((invalid = true), token) : token;
      if (/^(?:[a-z][a-z0-9+.-]*:|\/|\\)/i.test(decoded)) {
        invalid = true;
        return token;
      }
      const parts = [...base];
      for (const part of decoded.replace(/^\.\//, "").split("/")) {
        if (!part || part === "." || !/^[a-zA-Z0-9._-]+$/.test(part)) {
          invalid = true;
          return token;
        }
        if (part === "..") {
          if (!parts.length) {
            invalid = true;
            return token;
          }
          parts.pop();
        } else parts.push(part);
      }
      const relative = parts.join("/");
      if (!relative || relative.length > 256) {
        invalid = true;
        return token;
      }
      return `url("${relative}")`;
    },
  );
  return invalid ? null : result;
}
export function hasUnresolvedCssResource(value: string): boolean {
  const normalized = normalizeImageSets(value);
  if (normalized === null) return true;
  value = normalized;
  const remaining = value.replace(
    urlPattern,
    (token, double: string, single: string, bare: string) =>
      double === undefined && single === undefined && bare === undefined
        ? ""
        : isImageDataUrl(double ?? single ?? bare)
          ? ""
          : token,
  );
  return /url\s*\(|src\s*\(|\\/i.test(maskVariableNames(remaining));
}

export async function rewriteCssImages(
  value: string,
  resolve: (relative: string) => Promise<string>,
): Promise<string | null> {
  if (value.length > 16 * 1024 * 1024) return null;
  const normalized = normalizeImageSets(value);
  if (normalized === null) return null;
  value = normalized;
  const matches = Array.from(value.matchAll(urlPattern)).filter(
    (match) => match[1] !== undefined || match[2] !== undefined || match[3] !== undefined,
  );
  let result = "",
    offset = 0;
  for (const match of matches) {
    const url = decodeCssUrl(match[1] ?? match[2] ?? match[3], match[3] === undefined);
    if (url === null) return null;
    let data = url;
    if (!isImageDataUrl(data)) {
      const relative = url.replace(/^\.\//, "");
      if (
        !relative ||
        relative.length > 256 ||
        !relative
          .split("/")
          .every((part) => part !== "." && part !== ".." && /^[a-zA-Z0-9._-]+$/.test(part))
      )
        return null;
      try {
        data = await resolve(relative);
      } catch {
        return null;
      }
      if (!isImageDataUrl(data)) return null;
    }
    result += value.slice(offset, match.index) + `url("${data}")`;
    if (result.length > 16 * 1024 * 1024) return null;
    offset = match.index! + match[0].length;
  }
  result += value.slice(offset);
  return hasUnresolvedCssResource(result) ? null : result;
}
