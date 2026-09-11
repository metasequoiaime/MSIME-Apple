import { normalizeImageSets } from "./css-image-set.js";
const imageData = /^data:image\/(?:png|jpeg|gif|webp|svg\+xml|x-icon|bmp|avif);base64,[A-Za-z0-9+/]*={0,2}$/;
// Consume strings as opaque tokens before considering URL functions, so e.g.
// content: "url(icon.png)" never starts a resource request.
const urlPattern = /"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|\burl\(\s*(?:"([^"]*)"|'([^']*)'|([^\s)'"(]*))\s*\)/gi;
export function isImageDataUrl(value: string): boolean {
  return value.length <= 12 * 1024 * 1024 && imageData.test(value);
}
export function hasUnresolvedCssResource(value: string): boolean {
  const normalized = normalizeImageSets(value);
  if (normalized === null) return true;
  value = normalized;
  const remaining = value.replace(urlPattern, (token, double: string, single: string, bare: string) =>
    double === undefined && single === undefined && bare === undefined ? "" : isImageDataUrl(double ?? single ?? bare) ? "" : token);
  return /url\s*\(|src\s*\(|\\/i.test(remaining);
}

export async function rewriteCssImages(value: string, resolve: (relative: string) => Promise<string>): Promise<string | null> {
  if (value.length > 16 * 1024 * 1024) return null;
  if (/src\s*\(|\\/i.test(value)) return null;
  const normalized = normalizeImageSets(value);
  if (normalized === null) return null;
  value = normalized;
  const matches = Array.from(value.matchAll(urlPattern)).filter(match => match[1] !== undefined || match[2] !== undefined || match[3] !== undefined);
  let result = "", offset = 0;
  for (const match of matches) {
    const url = match[1] ?? match[2] ?? match[3];
    let data = url;
    if (!isImageDataUrl(data)) {
      const relative = url.replace(/^\.\//, "");
      if (!relative || relative.length > 256 || !relative.split("/").every(part => part !== "." && part !== ".." && /^[a-zA-Z0-9._-]+$/.test(part))) return null;
      try { data = await resolve(relative); } catch { return null; }
      if (!isImageDataUrl(data)) return null;
    }
    result += value.slice(offset, match.index) + `url("${data}")`;
    if (result.length > 16 * 1024 * 1024) return null;
    offset = match.index! + match[0].length;
  }
  result += value.slice(offset);
  return hasUnresolvedCssResource(result) ? null : result;
}
