import { useEffect, useState } from "react";
import { installToolbarCss } from "./skin-toolbar-css";
import { prepareToolbarImages } from "./toolbar-images";
import { skinImageUrl, type SkinImageReader } from "./skin-image";

export type ToolbarCssReader = (id: string) => Promise<string | null>;
export function useToolbarCss(read: ToolbarCssReader | undefined, id: string, filename: string | null, revision: number, scope: string, readImage?: SkinImageReader) {
  const [state, setState] = useState<"idle" | "loading" | "ready" | "partial" | "failed">("idle");
  useEffect(() => {
    let active = true;
    let remove: (() => void) | undefined;
    setState(read && filename ? "loading" : "idle");
    if (read && filename) void (async () => {
      try {
        const css = await read(id);
        if (!active) return;
        if (css !== null) {
          const prepared = readImage ? await prepareToolbarImages(css, async relative => {
            if (!active) throw new Error("stale request");
            return skinImageUrl(await readImage(id, relative));
          }) : { css, partial: false };
          if (!active) return;
          const result = installToolbarCss(scope, prepared.css);
          remove = result.remove;
          setState(result.partial || prepared.partial ? "partial" : "ready");
        } else setState("ready");
      } catch { if (active) setState("failed"); }
    })();
    return () => { active = false; remove?.(); };
  }, [read, id, filename, revision, scope, readImage]);
  return state;
}
