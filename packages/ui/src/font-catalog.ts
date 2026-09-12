import { useEffect, useMemo, useState } from "react";
import { validFontFamily } from "./candidate-font-family";
export type FontCatalogReader = () => Promise<string[]>;
export function normalizeFontCatalog(value: unknown): string[] {
  if (!Array.isArray(value) || value.length > 16384 || !value.every(validFontFamily)) throw new Error("invalid font catalog");
  return [...new Set(value)].sort((a, b) => a.localeCompare(b));
}
export function useFontCatalog(read?: FontCatalogReader) {
  const [requested, setRequested] = useState(false), [revision, setRevision] = useState(0);
  const key = useMemo(() => ({}), [read, revision]);
  const [result, setResult] = useState<{ key: object; fonts: string[]; failed?: boolean }>();
  useEffect(() => {
    let active = true;
    if (requested && read) void (async () => {
      try { const fonts = normalizeFontCatalog(await read()); if (active) setResult({ key, fonts }); }
      catch { if (active) setResult({ key, fonts: [], failed: true }); }
    })();
    return () => { active = false; };
  }, [read, key, requested]);
  const current = result?.key === key ? result : undefined;
  const status = !read ? "unsupported" : !requested ? "idle" : !current ? "loading" : current.failed ? "failed" : "ready";
  return { fonts: current?.fonts ?? [], status, request: () => setRequested(true), refresh: () => { setRequested(true); setRevision(value => value + 1); } };
}
