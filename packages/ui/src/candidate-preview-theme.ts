import { useEffect, useState } from "react";
import type { SurfaceTheme, ThemeMode } from "./index";

export function useCandidatePreviewTheme(mode: ThemeMode = "dark", surface: SurfaceTheme = "follow"): "dark" | "light" {
  const [systemLight, setSystemLight] = useState(false);
  useEffect(() => {
    if (mode !== "system" || surface !== "follow" || typeof window.matchMedia !== "function") return;
    const media = window.matchMedia("(prefers-color-scheme: light)");
    const update = () => setSystemLight(media.matches);
    update();
    media.addEventListener("change", update);
    return () => media.removeEventListener("change", update);
  }, [mode, surface]);
  if (surface !== "follow") return surface;
  return mode === "system" ? (systemLight ? "light" : "dark") : mode;
}
