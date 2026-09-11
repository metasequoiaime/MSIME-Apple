import { useEffect, useState } from "react";
import { installToolbarCss } from "./skin-toolbar-css";

export type ToolbarCssReader = (id: string) => Promise<string | null>;
export function useToolbarCss(read: ToolbarCssReader | undefined, id: string, filename: string | null, revision: number, scope: string) {
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
          const result = installToolbarCss(scope, css);
          remove = result.remove;
          setState(result.partial ? "partial" : "ready");
        } else setState("ready");
      } catch { if (active) setState("failed"); }
    })();
    return () => { active = false; remove?.(); };
  }, [read, id, filename, revision, scope]);
  return state;
}
