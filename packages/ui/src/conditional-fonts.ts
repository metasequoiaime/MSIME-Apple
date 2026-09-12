export type ConditionalFont = { face: FontFace; media: readonly MediaQueryList[] };

// Keep source order when a condition changes: font matching must not depend on
// which media query happened to activate first. No font reads occur here.
export function installConditionalFonts(fonts: readonly ConditionalFont[]): () => void {
  const queries = [...new Set(fonts.flatMap(font => font.media))];
  const listening: MediaQueryList[] = [];
  let active = true, added: FontFace[] = [];
  const remove = () => {
    active = false;
    for (const query of listening) query.removeEventListener("change", refresh);
    listening.length = 0;
    for (const face of added) document.fonts.delete(face);
    added = [];
  };
  const refresh = () => {
    if (!active) return;
    const wanted = fonts.filter(font => font.media.every(query => query.matches)).map(font => font.face);
    if (wanted.length === added.length && wanted.every((face, index) => face === added[index])) return;
    for (const face of added) document.fonts.delete(face);
    added = [];
    try { for (const face of wanted) { document.fonts.add(face); added.push(face); } }
    catch { remove(); throw new Error("font installation failed"); }
  };
  try {
    for (const query of queries) { query.addEventListener("change", refresh); listening.push(query); }
    refresh();
  } catch { remove(); throw new Error("font installation failed"); }
  return remove;
}
