// Rules are generated from validated palette values, not arbitrary skin CSS.
// Constructed sheets preserve style-src 'self' without inline style elements.
export function installSkinPalette(rules: readonly string[], owner: Document = document): () => void {
  if (!("adoptedStyleSheets" in owner)) throw new Error("constructed stylesheets unavailable");
  const sheet = new CSSStyleSheet();
  for (const rule of rules) sheet.insertRule(rule, sheet.cssRules.length);
  owner.adoptedStyleSheets = [...owner.adoptedStyleSheets, sheet];
  return () => { owner.adoptedStyleSheets = owner.adoptedStyleSheets.filter(existing => existing !== sheet); };
}
