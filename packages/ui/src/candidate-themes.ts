export type CandidateTheme = "fluent" | "wechat" | "graphite" | "willow_green";
export type CandidateOrientation = "horizontal" | "vertical";
export type CandidateAppearance = "light" | "dark";

/** Files copied from the upstream WebView2 candidate renderer. */
export function candidateThemeStylesheet(
  theme: CandidateTheme,
  orientation: CandidateOrientation,
  appearance: CandidateAppearance,
): URL {
  return new URL(
    `./upstream/candidate-themes/skins/${theme}/${orientation}_${appearance}.css`,
    import.meta.url,
  );
}

export function candidateTemplate(
  orientation: CandidateOrientation,
  appearance: CandidateAppearance,
): URL {
  return new URL(
    `./upstream/candidate-themes/${orientation}_candidate_window${appearance === "dark" ? "_dark" : ""}.html`,
    import.meta.url,
  );
}
